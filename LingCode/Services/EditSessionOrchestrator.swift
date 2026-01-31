//
//  EditSessionOrchestrator.swift
//  LingCode
//
//  Single orchestrator for edit streams: intent classification, parse, validation, and Shadow verification.
//  Merges EditIntentCoordinator (intent + validation) with a single flow to reduce delegate-callback overhead.
//  Shadow Workspace verification runs in the same flow after validation for faster feedback.
//

import Foundation
import Combine

/// Parsed and validated edit result
struct EditSessionResult: Equatable {
    let files: [StreamingFileInfo]
    let commands: [ParsedCommand]
    let isValid: Bool
    let errorMessage: String?
    let intentCategory: IntentEngine.IntentType.EditIntentCategory?
    
    static func == (lhs: EditSessionResult, rhs: EditSessionResult) -> Bool {
        lhs.files == rhs.files &&
        lhs.commands.count == rhs.commands.count &&
        lhs.isValid == rhs.isValid &&
        lhs.errorMessage == rhs.errorMessage &&
        lhs.intentCategory == rhs.intentCategory
    }
}

/// Single orchestrator for edit streams: intent -> parse -> validate -> (optional) Shadow verify
@MainActor
final class EditSessionOrchestrator: ObservableObject {
    static let shared = EditSessionOrchestrator()
    
    @Published private(set) var currentResult: EditSessionResult?
    @Published private(set) var isParsing: Bool = false
    /// Shadow verification result when validated files exist (run in same flow for faster feedback)
    @Published private(set) var shadowVerificationResult: (success: Bool, message: String)?
    
    private init() {}
    
    /// Parse and validate AI response; runs Shadow verification when valid files exist
    func parseAndValidate(
        content: String,
        userPrompt: String,
        isLoading: Bool,
        projectURL: URL?,
        actions: [AIAction],
        httpStatus: Int? = nil
    ) async -> EditSessionResult {
        AIResponseDebugLogger.dump(label: "EditSessionOrchestrator.raw", text: content)
        
        let intent = IntentEngine.shared.classifyIntent(userPrompt)
        let intentCategory = intent.editIntentCategory
        
        if let workspaceURL = projectURL {
            let expansion = WorkspaceEditExpansion.shared.expandEditScope(prompt: userPrompt, workspaceURL: workspaceURL)
            if expansion.wasExpanded, !expansion.deterministicEdits.isEmpty {
                let deterministicFiles = WorkspaceEditExpansion.shared.convertToStreamingFileInfo(
                    edits: expansion.deterministicEdits,
                    workspaceURL: workspaceURL
                )
                let executionIntent = ValidationCoordinator.shared.classifyExecutionIntent(userPrompt)
                var validatedFiles: [StreamingFileInfo] = []
                var validationErrors: [String] = []
                for file in deterministicFiles {
                    let fileURL = workspaceURL.appendingPathComponent(file.path)
                    let originalContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                    let scopeResult = ValidationCoordinator.shared.validateEditScope(
                        originalContent: originalContent,
                        newContent: file.content,
                        intent: executionIntent
                    )
                    if scopeResult.isValid { validatedFiles.append(file) }
                    else if let error = scopeResult.errorMessage { validationErrors.append("\(file.path): \(error)") }
                }
                if !validationErrors.isEmpty {
                    let result = EditSessionResult(
                        files: [],
                        commands: [],
                        isValid: false,
                        errorMessage: validationErrors.joined(separator: "\n"),
                        intentCategory: intentCategory
                    )
                    currentResult = result
                    return result
                }
                let result = EditSessionResult(
                    files: validatedFiles,
                    commands: [],
                    isValid: true,
                    errorMessage: nil,
                    intentCategory: intentCategory
                )
                currentResult = result
                runShadowVerificationIfNeeded(files: validatedFiles, projectURL: workspaceURL)
                return result
            }
        }
        
        let outputValidation = ValidationCoordinator.shared.validateEditOutput(content)
        let contentToParse: String
        switch outputValidation {
        case .silentFailure:
            AIResponseDebugLogger.dump(label: "EditSessionOrchestrator.validation.silentFailure", text: content)
            let result = EditSessionResult(
                files: [], commands: [], isValid: false,
                errorMessage: "AI service returned an empty response. Please retry.",
                intentCategory: nil
            )
            currentResult = result
            return result
        case .invalidFormat(let reason):
            AIResponseDebugLogger.dump(label: "EditSessionOrchestrator.validation.invalidFormat", text: content)
            let result = EditSessionResult(
                files: [], commands: [], isValid: false,
                errorMessage: "AI returned non-executable output. \(reason) Please retry.",
                intentCategory: nil
            )
            currentResult = result
            return result
        case .recovered(let recoveredContent):
            contentToParse = recoveredContent
            AIResponseDebugLogger.dump(label: "EditSessionOrchestrator.validation.recovered", text: recoveredContent)
        case .noOp:
            let result = EditSessionResult(files: [], commands: [], isValid: true, errorMessage: nil, intentCategory: nil)
            currentResult = result
            return result
        case .valid:
            contentToParse = content
        }
        
        isParsing = true
        defer { isParsing = false }
        
        let (parsedFiles, parsedCommands) = await Task.detached(priority: .userInitiated) {
            let commands = await Task { @MainActor in TerminalExecutionService.shared.extractCommands(from: contentToParse) }.value
            let files = await Task { @MainActor in
                ApplyCodeService.shared.parseStreamingContent(contentToParse, isLoading: isLoading, projectURL: projectURL, actions: actions)
            }.value
            return (files, commands)
        }.value
        
        let hasParsedOutput = !parsedFiles.isEmpty || !parsedCommands.isEmpty
        guard hasParsedOutput else {
            let errorMessage = parsedFiles.isEmpty && parsedCommands.isEmpty
                ? "No files or commands were parsed from the AI response. The response format may be invalid or incomplete."
                : "No valid edits were found in the AI response."
            let result = EditSessionResult(files: [], commands: [], isValid: false, errorMessage: errorMessage, intentCategory: intentCategory)
            currentResult = result
            return result
        }
        
        let executionIntent = ValidationCoordinator.shared.classifyExecutionIntent(userPrompt)
        var validatedFiles: [StreamingFileInfo] = []
        var validationErrors: [String] = []
        for file in parsedFiles {
            guard let projectURL = projectURL else { validatedFiles.append(file); continue }
            let fileURL = projectURL.appendingPathComponent(file.path)
            guard let originalContent = try? String(contentsOf: fileURL, encoding: .utf8) else { validatedFiles.append(file); continue }
            let scopeResult = ValidationCoordinator.shared.validateEditScope(
                originalContent: originalContent,
                newContent: file.content,
                intent: executionIntent
            )
            if scopeResult.isValid {
                validatedFiles.append(file)
            } else {
                validationErrors.append("\(file.path): \(scopeResult.errorMessage ?? "Change exceeds requested scope")")
            }
        }
        
        let (canComplete, gateError) = ValidationCoordinator.shared.checkCompletionGate(
            httpStatus: httpStatus,
            responseLength: content.count,
            parsedFiles: validatedFiles,
            proposedEdits: validatedFiles,
            validationErrors: validationErrors
        )
        let isValid = canComplete && validationErrors.isEmpty && !validatedFiles.isEmpty
        let errorMessage = canComplete
            ? (validationErrors.isEmpty ? nil : validationErrors.joined(separator: "\n"))
            : gateError
        
        let result = EditSessionResult(
            files: validatedFiles,
            commands: parsedCommands,
            isValid: isValid,
            errorMessage: errorMessage,
            intentCategory: intentCategory
        )
        currentResult = result
        if isValid, !validatedFiles.isEmpty, let projectURL = projectURL {
            runShadowVerificationIfNeeded(files: validatedFiles, projectURL: projectURL)
        }
        return result
    }
    
    /// Run Shadow Workspace verification in the same flow (no delegate/callback chain)
    private func runShadowVerificationIfNeeded(files: [StreamingFileInfo], projectURL: URL) {
        shadowVerificationResult = nil
        ShadowWorkspaceService.shared.verifyFilesInShadow(files: files, originalWorkspace: projectURL) { [weak self] success, message, _ in
            Task { @MainActor in
                self?.shadowVerificationResult = (success, message)
            }
        }
    }
    
    func reset() {
        currentResult = nil
        isParsing = false
        shadowVerificationResult = nil
    }
}
