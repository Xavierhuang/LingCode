//
//  EditRetryService.swift
//  LingCode
//
//  Retry loop with error feedback to AI for corrected edits
//

import Foundation

struct RetryContext {
    let originalEdits: [Edit]
    let error: Error
    let failedEdit: Edit?
    let previousAttempts: Int
    let isLinterError: Bool
}

class EditRetryService {
    static let shared = EditRetryService()
    
    private let maxRetries = 3
    
    private init() {}
    
    /// Generate retry prompt for AI with error feedback
    func generateRetryPrompt(context: RetryContext) -> String {
        let header: String
        if context.isLinterError {
            header = "The edits were applied but failed linting/validation checks."
        } else {
            header = "The previous edits failed to apply."
        }
        
        var prompt = """
        \(header)
        
        Error:
        \(context.error.localizedDescription)
        
        """
        
        if let failedEdit = context.failedEdit {
            prompt += """
            Failed edit:
            File: \(failedEdit.file)
            Operation: \(failedEdit.operation.rawValue)
            """
            
            if let range = failedEdit.range {
                prompt += """
                Range: \(range.startLine)-\(range.endLine)
                """
            }
            
            prompt += "\n\n"
        }
        
        prompt += """
        Previous edits (for reference):
        """
        
        // Include previous edits as JSON
        let editSchema = EditSchema(edits: context.originalEdits)
        if let jsonData = try? JSONEncoder().encode(editSchema),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            prompt += "\n```json\n\(jsonString)\n```\n\n"
        }
        
        prompt += """
        Please return corrected edits only in the same JSON format.
        Fix the issue that caused the error and ensure all edits are valid.
        """
        
        return prompt
    }
    
    /// Attempt to apply edits with retry logic
    func applyWithRetry(
        edits: [Edit],
        in workspaceURL: URL,
        aiService: AIService,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        applyWithRetryInternal(
            edits: edits,
            in: workspaceURL,
            aiService: aiService,
            attempt: 0,
            onProgress: onProgress,
            onComplete: onComplete,
            onError: onError
        )
    }
    
    private func applyWithRetryInternal(
        edits: [Edit],
        in workspaceURL: URL,
        aiService: AIService,
        attempt: Int,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Try to apply edits
        AtomicEditService.shared.applyEdits(
            edits,
            in: workspaceURL,
            onProgress: onProgress,
            onComplete: { appliedFiles in
                // Validation gate: run linter on changed files (best effort)
                if LinterService.shared.hasLinter(for: workspaceURL) {
                    onProgress("Verifying changes with linter...")
                    LinterService.shared.validate(files: appliedFiles, in: workspaceURL) { linterError in
                        if let linterError = linterError {
                            self.handleRetry(
                                error: linterError,
                                edits: edits,
                                workspaceURL: workspaceURL,
                                aiService: aiService,
                                attempt: attempt,
                                isLinterError: true,
                                onProgress: onProgress,
                                onComplete: onComplete,
                                onError: onError
                            )
                            return
                        }
                        
                        onComplete(appliedFiles)
                    }
                    return
                }
                
                onComplete(appliedFiles)
            },
            onError: { error in
                self.handleRetry(
                    error: error,
                    edits: edits,
                    workspaceURL: workspaceURL,
                    aiService: aiService,
                    attempt: attempt,
                    isLinterError: false,
                    onProgress: onProgress,
                    onComplete: onComplete,
                    onError: onError
                )
            }
        )
    }
    
    private func handleRetry(
        error: Error,
        edits: [Edit],
        workspaceURL: URL,
        aiService: AIService,
        attempt: Int,
        isLinterError: Bool,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        if attempt >= self.maxRetries {
            onError(RetryError.maxRetriesReached(originalError: error))
            return
        }
        
        let baseMsg: String
        if isLinterError {
            baseMsg = "Linter issues found, auto-fixing..."
        } else {
            baseMsg = "Edit failed, requesting AI to fix..."
        }
        onProgress("\(baseMsg) (Attempt \(attempt + 1)/\(self.maxRetries))")
        
        let retryContext = RetryContext(
            originalEdits: edits,
            error: error,
            failedEdit: self.findFailedEdit(edits: edits, error: error),
            previousAttempts: attempt,
            isLinterError: isLinterError
        )
        
        let retryPrompt = self.generateRetryPrompt(context: retryContext)
        
        Task { @MainActor in
            do {
                let response = try await aiService.sendMessage(retryPrompt, context: nil, images: [], tools: nil)
                if let correctedEdits = JSONEditSchemaService.shared.parseEdits(from: response) {
                    self.applyWithRetryInternal(
                        edits: correctedEdits,
                        in: workspaceURL,
                        aiService: aiService,
                        attempt: attempt + 1,
                        onProgress: onProgress,
                        onComplete: onComplete,
                        onError: onError
                    )
                } else {
                    onError(RetryError.couldNotParseCorrectedEdits)
                }
            } catch {
                onError(RetryError.aiRetryFailed(error))
            }
        }
    }
    
    private func findFailedEdit(edits: [Edit], error: Error) -> Edit? {
        // Try to identify which edit failed from error message
        let errorMsg = error.localizedDescription.lowercased()
        
        for edit in edits {
            if errorMsg.contains(edit.file.lowercased()) {
                return edit
            }
        }
        
        return edits.first
    }
}

enum RetryError: Error, LocalizedError {
    case maxRetriesReached(originalError: Error)
    case couldNotParseCorrectedEdits
    case aiRetryFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .maxRetriesReached(let originalError):
            return "Failed after maximum retries: \(originalError.localizedDescription)"
        case .couldNotParseCorrectedEdits:
            return "AI returned edits in invalid format"
        case .aiRetryFailed(let error):
            return "AI retry request failed: \(error.localizedDescription)"
        }
    }
}
