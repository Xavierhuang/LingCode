//
//  EditSafetyCoordinator.swift
//  LingCode
//
//  System-level safety coordinator that enforces all safety invariants
//  Coordinates intent classification, validation, and completion gates
//

import Foundation

/// System-level safety coordinator
///
/// SAFETY INVARIANTS:
/// 1. Small edit requests never cause large file deletions
/// 2. Empty or failed AI responses never reach parse or apply stages
/// 3. SwiftUI state is never mutated during view updates
/// 4. "Response Complete" only appears when valid edits exist
@MainActor
final class EditSafetyCoordinator {
    static let shared = EditSafetyCoordinator()
    
    private init() {}
    
    /// Execution intent for safety validation
    enum ExecutionIntent: Equatable {
        case textReplacement    // Only text replacements allowed
        case symbolRename       // Symbol rename (similar to text replacement)
        case scopedEdit         // Bounded scoped edits (DEFAULT)
        case fullFileRewrite    // Full-file rewrite (explicit only)
    }
    
    /// Classify execution intent from user prompt
    ///
    /// SAFETY INVARIANT: Default intent is scopedEdit
    /// Full-file rewrites are ONLY allowed if user explicitly requests rewrite/refactor/regenerate
    ///
    /// - Parameter prompt: User's edit instruction
    /// - Returns: Execution intent
    func classifyExecutionIntent(_ prompt: String) -> ExecutionIntent {
        let intent = IntentEngine.shared.classifyIntent(prompt)
        
        switch intent {
        case .simpleReplace, .rename:
            return .textReplacement
            
        case .refactor:
            return .scopedEdit // Refactor is bounded, not full rewrite
            
        case .rewrite:
            return .fullFileRewrite // Only explicit rewrite allows full-file replacement
            
        case .globalUpdate, .complex:
            return .scopedEdit // DEFAULT: Scoped edit
        }
    }
    
    /// Validate edit against execution intent
    ///
    /// SAFETY INVARIANT: Large diffs are illegal unless intent == fullFileRewrite
    ///
    /// - Parameters:
    ///   - originalContent: Original file content
    ///   - newContent: Proposed new content
    ///   - intent: Execution intent
    /// - Returns: Validation result with error message if unsafe
    func validateEditScope(
        originalContent: String,
        newContent: String,
        intent: ExecutionIntent
    ) -> (isValid: Bool, errorMessage: String?) {
        let originalLines = originalContent.components(separatedBy: .newlines)
        let newLines = newContent.components(separatedBy: .newlines)
        
        let deletedLines = max(0, originalLines.count - newLines.count)
        let deletionPercentage = originalLines.isEmpty ? 0.0 : Double(deletedLines) / Double(originalLines.count)
        
        // SAFETY RULE: If >20% of file OR >200 lines deleted AND intent != fullFileRewrite, abort
        switch intent {
        case .textReplacement, .symbolRename:
            // Text replacement: Block large deletions
            if deletedLines > 50 || deletionPercentage > 0.3 {
                return (false, "Change exceeds requested scope. Text replacement should not delete large portions of code.")
            }
            return (true, nil)
            
        case .scopedEdit:
            // Scoped edit (default): Block if >20% OR >200 lines
            if deletedLines > 200 {
                return (false, "Change exceeds requested scope. \(deletedLines) lines deleted, but only scoped edits are allowed. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            if deletionPercentage > 0.2 {
                return (false, "Change exceeds requested scope. \(Int(deletionPercentage * 100))% of file deleted, but only scoped edits are allowed. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            return (true, nil)
            
        case .fullFileRewrite:
            // Full rewrite: Allow all changes
            return (true, nil)
        }
    }
    
    /// Check if completion gate passes
    ///
    /// HARD COMPLETION GATE: Session may only complete if ALL are true:
    /// 1. HTTP status is 2xx
    /// 2. Response body is non-empty (responseLength > 0)
    /// 3. At least one parsed file exists (parsedFiles.count > 0)
    /// 4. At least one proposed edit exists (proposedEdits.count > 0)
    /// 5. Each edit passes scope validation
    /// 6. No safety rule was violated
    ///
    /// - Parameters:
    ///   - httpStatus: HTTP status code
    ///   - responseLength: Response body length (must be > 0)
    ///   - parsedFiles: Parsed files from AI response (must have count > 0)
    ///   - proposedEdits: Proposed edits from session (must have count > 0)
    ///   - validationErrors: Any validation errors
    /// - Returns: Whether completion gate passes
    func checkCompletionGate(
        httpStatus: Int?,
        responseLength: Int,
        parsedFiles: [StreamingFileInfo],
        proposedEdits: [Any], // Generic to work with any proposal type
        validationErrors: [String]
    ) -> (passes: Bool, errorMessage: String?) {
        // Condition 1: HTTP status is 2xx
        guard let status = httpStatus, status >= 200 && status < 300 else {
            return (false, "AI request failed with HTTP \(httpStatus ?? 0). Please retry.")
        }
        
        // Condition 2: Response body is non-empty (responseLength > 0)
        guard responseLength > 0 else {
            return (false, "AI service returned an empty response. Please retry.")
        }
        
        // Condition 3: At least one parsed file exists (parsedFiles.count > 0)
        guard !parsedFiles.isEmpty else {
            return (false, "No files were parsed from the AI response. The response may be incomplete or in an unexpected format.")
        }
        
        // Condition 4: At least one proposed edit exists (proposedEdits.count > 0)
        guard !proposedEdits.isEmpty else {
            return (false, "No edits were proposed. The AI response did not generate any valid edit proposals.")
        }
        
        // Condition 5: Each edit passes scope validation (checked by DiffSafetyGuard)
        guard validationErrors.isEmpty else {
            return (false, validationErrors.joined(separator: "\n"))
        }
        
        // Condition 6: No safety rule was violated (implicitly checked above)
        
        return (true, nil)
    }
}
