//
//  EditIntentCoordinator.swift
//  LingCode
//
//  Coordinates AI parsing, validation, and state updates OUTSIDE of SwiftUI views
//  Ensures all state mutations happen asynchronously on MainActor AFTER view updates
//

import Foundation
import Combine

/// Coordinates edit intent classification, parsing, validation, and state updates
///
/// ARCHITECTURE INVARIANT:
/// - All AI parsing, diffing, and state mutation happens OUTSIDE SwiftUI views
/// - SwiftUI views only observe state, never mutate it during render
/// - State updates are dispatched asynchronously on MainActor AFTER view updates
@MainActor
final class EditIntentCoordinator: ObservableObject {
    static let shared = EditIntentCoordinator()
    
    private init() {}
    
    /// Parsed and validated edit result
    struct EditResult: Equatable {
        let files: [StreamingFileInfo]
        let commands: [ParsedCommand]
        let isValid: Bool
        let errorMessage: String?
        let intentCategory: IntentClassifier.IntentType.EditIntentCategory?
        
        // Equatable conformance (StreamingFileInfo is Equatable, ParsedCommand may not be)
        static func == (lhs: EditResult, rhs: EditResult) -> Bool {
            lhs.files == rhs.files &&
            lhs.commands.count == rhs.commands.count && // Compare count since ParsedCommand may not be Equatable
            lhs.isValid == rhs.isValid &&
            lhs.errorMessage == rhs.errorMessage &&
            lhs.intentCategory == rhs.intentCategory
        }
    }
    
    /// Current edit result (published for SwiftUI observation)
    @Published private(set) var currentResult: EditResult?
    
    /// Whether parsing is in progress
    @Published private(set) var isParsing: Bool = false
    
    /// Parse and validate AI response
    ///
    /// NETWORK FAILURE & EMPTY RESPONSE HANDLING:
    /// - If HTTP status is non-2xx OR response is empty, abort immediately
    /// - Do NOT parse, do NOT mark complete, show retry option
    ///
    /// - Parameters:
    ///   - content: AI response content
    ///   - userPrompt: Original user prompt (for intent classification)
    ///   - isLoading: Whether AI is still loading
    ///   - projectURL: Project root URL
    ///   - actions: Current AI actions
    ///   - httpStatus: HTTP status code (for completion gate)
    /// - Returns: EditResult with parsed files and validation status
    func parseAndValidate(
        content: String,
        userPrompt: String,
        isLoading: Bool,
        projectURL: URL?,
        actions: [AIAction],
        httpStatus: Int? = nil
    ) async -> EditResult {
        // DEBUG: Dump raw AI response before validation/parsing so we can diagnose "No edits produced"
        AIResponseDebugLogger.dump(
            label: "EditIntentCoordinator.raw",
            text: content
        )

        // Step 0: Classify intent (PRE-AI)
        // If this is a simple replace/rename, prefer deterministic workspace expansion over model output.
        let intent = IntentClassifier.shared.classify(userPrompt)
        let intentCategory = intent.editIntentCategory

        if let workspaceURL = projectURL {
            let expansion = WorkspaceEditExpansion.shared.expandEditScope(prompt: userPrompt, workspaceURL: workspaceURL)
            if expansion.wasExpanded, !expansion.deterministicEdits.isEmpty {
                let deterministicFiles = WorkspaceEditExpansion.shared.convertToStreamingFileInfo(
                    edits: expansion.deterministicEdits,
                    workspaceURL: workspaceURL
                )

                // Validate scope (same safety rules as AI-generated edits)
                let executionIntent = EditSafetyCoordinator.shared.classifyExecutionIntent(userPrompt)
                var validatedFiles: [StreamingFileInfo] = []
                var validationErrors: [String] = []

                for file in deterministicFiles {
                    let fileURL = workspaceURL.appendingPathComponent(file.path)
                    let originalContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""

                    let scopeValidation = EditSafetyCoordinator.shared.validateEditScope(
                        originalContent: originalContent,
                        newContent: file.content,
                        intent: executionIntent
                    )

                    if scopeValidation.isValid {
                        validatedFiles.append(file)
                    } else if let error = scopeValidation.errorMessage {
                        validationErrors.append("\(file.path): \(error)")
                    }
                }

                if !validationErrors.isEmpty {
                    let result = EditResult(
                        files: [],
                        commands: [],
                        isValid: false,
                        errorMessage: validationErrors.joined(separator: "\n"),
                        intentCategory: intentCategory
                    )
                    await MainActor.run {
                        self.currentResult = result
                    }
                    return result
                }

                let result = EditResult(
                    files: validatedFiles,
                    commands: [],
                    isValid: true,
                    errorMessage: nil,
                    intentCategory: intentCategory
                )

                await MainActor.run {
                    self.currentResult = result
                }

                print("✅ DETERMINISTIC EXPANSION: Returning \(validatedFiles.count) workspace edits without relying on AI output.")
                return result
            }
        }

        // EDIT MODE VALIDATION: Validate response contains ONLY executable edits
        // Distinguish between: no-op (valid), invalid format (error), silent failure (timeout/empty)
        let outputValidation = EditOutputValidator.shared.validateEditOutput(content)
        
        // Determine content to parse (may be recovered from formatting violations)
        let contentToParse: String
        switch outputValidation {
        case .silentFailure:
            AIResponseDebugLogger.dump(
                label: "EditIntentCoordinator.validation.silentFailure",
                text: content
            )
            // Empty response - abort immediately
            let result = EditResult(
                files: [],
                commands: [],
                isValid: false,
                errorMessage: "AI service returned an empty response. Please retry.",
                intentCategory: nil
            )
            await MainActor.run {
                self.currentResult = result
            }
            return result
            
        case .invalidFormat(let reason):
            AIResponseDebugLogger.dump(
                label: "EditIntentCoordinator.validation.invalidFormat",
                text: content
            )
            // True safety/policy violation - hard block
            let result = EditResult(
                files: [],
                commands: [],
                isValid: false,
                errorMessage: "AI returned non-executable output. \(reason) Please retry.",
                intentCategory: nil
            )
            await MainActor.run {
                self.currentResult = result
            }
            return result
            
        case .recovered(let recoveredContent):
            // Formatting violations recovered - parse recovered content
            contentToParse = recoveredContent
            AIResponseDebugLogger.dump(
                label: "EditIntentCoordinator.validation.recovered",
                text: recoveredContent
            )
            
        case .noOp:
            AIResponseDebugLogger.dump(
                label: "EditIntentCoordinator.validation.noOp",
                text: content
            )
            // Explicit no-op - valid, but no files to parse
            // Return valid result with zero files (distinct from parse failure)
            // NOTE: This is a valid terminal state - no edits needed
            let result = EditResult(
                files: [],
                commands: [],
                isValid: true, // No-op is valid
                errorMessage: nil,
                intentCategory: nil
            )
            await MainActor.run {
                self.currentResult = result
            }
            return result
            
        case .valid:
            // Valid edit output - proceed to parsing with original content
            contentToParse = content
        }
        // Mark as parsing
        isParsing = true
        defer { isParsing = false }
        
        // Step 2: Parse content (off main thread)
        // PARSER ROBUSTNESS: Parse with isLoading flag to ensure only complete blocks are accepted when done
        // Use contentToParse (may be recovered content if formatting violations were detected)
        let (parsedFiles, parsedCommands) = await Task.detached(priority: .userInitiated) {
            let commands = TerminalExecutionService.shared.extractCommands(from: contentToParse)
            let files = StreamingContentParser.shared.parseContent(
                contentToParse,
                isLoading: isLoading, // Critical: false when streaming completes, ensures only complete blocks
                projectURL: projectURL,
                actions: actions
            )
            
            // LOGGING: Track parsing results for debugging
            print("📊 PARSER RESULTS:")
            print("   Content length: \(contentToParse.count)")
            print("   Files parsed: \(files.count)")
            print("   Commands parsed: \(commands.count)")
            print("   Is loading: \(isLoading)")
            if case .recovered = outputValidation {
                print("   ⚠️ RECOVERED: Content was recovered from formatting violations")
            }
            if !files.isEmpty {
                print("   Files: \(files.map { "\($0.name) (\($0.isStreaming ? "streaming" : "complete"))" }.joined(separator: ", "))")
            }
            
            return (files, commands)
        }.value
        
        // Step 3: Validate parsed results (COMPLETION GATE)
        // CORE INVARIANT: "Response Complete" may ONLY appear if ALL are true:
        // 1. HTTP response was successful (checked by caller)
        // 2. AI response is non-empty (content parameter is non-empty)
        // 3. At least one file was parsed successfully OR at least one command
        // 4. At least one edit is proposed or applied
        
        let hasParsedOutput = !parsedFiles.isEmpty || !parsedCommands.isEmpty
        let hasProposedChanges = !parsedFiles.isEmpty || !parsedCommands.isEmpty
        
        // PARSE VALIDATION: Distinguish between no-op (valid) and parse failure (error)
        // If output validation passed but no files parsed, it's a parse failure
        guard hasParsedOutput && hasProposedChanges else {
            AIResponseDebugLogger.dump(
                label: "EditIntentCoordinator.parseFailure.contentToParse",
                text: contentToParse
            )
            // PARSE FAILURE: Output was validated as valid edit format, but parsing failed
            // This is distinct from no-op (which is handled above) and invalid format (also handled above)
            let errorMessage = parsedFiles.isEmpty && parsedCommands.isEmpty
                ? "No files or commands were parsed from the AI response. The response format may be invalid or incomplete."
                : "No valid edits were found in the AI response."
            
            let result = EditResult(
                files: [],
                commands: [],
                isValid: false,
                errorMessage: errorMessage,
                intentCategory: intentCategory
            )
            
            // Update state asynchronously (after view updates)
            await MainActor.run {
                self.currentResult = result
            }
            
            return result
        }
        
        // Step 4: Validate edits against intent (DIFF SAFETY GUARD)
        // SAFETY INVARIANT: Large diffs are illegal unless intent == fullFileRewrite
        var validatedFiles: [StreamingFileInfo] = []
        var validationErrors: [String] = []
        
        // Get execution intent for scope validation
        let executionIntent = EditSafetyCoordinator.shared.classifyExecutionIntent(userPrompt)
        
        for file in parsedFiles {
            // Get original content for validation
            guard let projectURL = projectURL else {
                // No project URL - skip validation but include file
                validatedFiles.append(file)
                continue
            }
            
            let fileURL = projectURL.appendingPathComponent(file.path)
            guard let originalContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
                // File doesn't exist - this is a new file, allow it
                validatedFiles.append(file)
                continue
            }
            
            // Validate edit scope (SAFETY: >20% OR >200 lines AND intent != fullFileRewrite → abort)
            let scopeValidation = EditSafetyCoordinator.shared.validateEditScope(
                originalContent: originalContent,
                newContent: file.content,
                intent: executionIntent
            )
            
            if !scopeValidation.isValid {
                // SCOPE VIOLATION: Reject this file
                validationErrors.append("\(file.path): \(scopeValidation.errorMessage ?? "Change exceeds requested scope")")
                // Do NOT add file to validatedFiles - reject it
                continue
            }
            
            // Also validate using DiffSafetyGuard for additional checks
            let safetyValidation = DiffSafetyGuard.shared.validateEdit(
                originalContent: originalContent,
                newContent: file.content,
                intentCategory: intentCategory
            )
            
            switch safetyValidation {
            case .safe:
                validatedFiles.append(file)
                
            case .unsafe(let reason):
                // UNSAFE EDIT: Reject this file, surface error
                validationErrors.append("\(file.path): \(reason)")
                // Do NOT add file to validatedFiles - reject it
            }
        }
        
        // Step 5: Validate completion gate (HARD COMPLETION GATE)
        // CORE INVARIANT: Session may only complete if ALL are true:
        // 1. HTTP status is 2xx
        // 2. Response body is non-empty (responseLength > 0)
        // 3. At least one parsed file exists (parsedFiles.count > 0)
        // 4. At least one proposed edit exists (proposedEdits.count > 0) - checked by session validator
        // 5. Each edit passes scope validation
        // 6. No safety rule was violated
        
        // Use SessionCompletionValidator for final gate check
        // Note: proposedEdits check happens at session level via SessionCompletionValidator
        let completionValidation = SessionCompletionValidator.shared.validateCompletion(
            httpStatus: httpStatus,
            responseLength: content.count,
            parsedFiles: validatedFiles,
            proposedEdits: validatedFiles, // Use validatedFiles as proxy - actual proposals checked at session level
            validationErrors: validationErrors
        )
        
        // If completion gate fails, mark as invalid
        let isValid = completionValidation.canComplete && validationErrors.isEmpty && !validatedFiles.isEmpty
        let errorMessage = completionValidation.canComplete 
            ? (validationErrors.isEmpty ? nil : validationErrors.joined(separator: "\n"))
            : completionValidation.errorMessage
        
        let result = EditResult(
            files: validatedFiles,
            commands: parsedCommands,
            isValid: isValid,
            errorMessage: errorMessage,
            intentCategory: intentCategory
        )
        
        // Step 6: Update state asynchronously (AFTER view updates)
        // ARCHITECTURE: State mutations happen on MainActor but AFTER current view update cycle
        await MainActor.run {
            self.currentResult = result
        }
        
        return result
    }
    
    /// Reset coordinator state
    func reset() {
        currentResult = nil
        isParsing = false
    }
}
