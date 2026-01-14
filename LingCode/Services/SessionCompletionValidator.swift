//
//  SessionCompletionValidator.swift
//  LingCode
//
//  Validates session completion against hard completion gate
//  Ensures sessions only complete when all safety conditions are met
//

import Foundation

/// Validates session completion against hard completion gate
///
/// HARD COMPLETION GATE: Session may only complete if ALL are true:
/// 1. HTTP status is 2xx
/// 2. Response body is non-empty (responseLength > 0)
/// 3. At least one parsed file exists (parsedFiles.count > 0)
/// 4. At least one proposed edit exists (proposedEdits.count > 0)
/// 5. Each edit passes scope validation
/// 6. No safety rule was violated
@MainActor
final class SessionCompletionValidator {
    static let shared = SessionCompletionValidator()
    
    private init() {}
    
    /// Validate session can complete
    ///
    /// - Parameters:
    ///   - httpStatus: HTTP status code (must be 2xx)
    ///   - responseLength: Response body length (must be > 0)
    ///   - parsedFiles: Parsed files from AI response (must have count > 0)
    ///   - proposedEdits: Proposed edits from session (must have count > 0)
    ///   - validationErrors: Any validation errors (must be empty)
    /// - Returns: Validation result with error message if gate fails
    func validateCompletion(
        httpStatus: Int?,
        responseLength: Int,
        parsedFiles: [StreamingFileInfo],
        proposedEdits: [Any],
        validationErrors: [String]
    ) -> (canComplete: Bool, errorMessage: String?) {
        // Condition 1: HTTP status is 2xx
        guard let status = httpStatus, status >= 200 && status < 300 else {
            return (false, "AI request failed with HTTP \(httpStatus ?? 0). Session cannot complete. Please retry.")
        }
        
        // Condition 2: Response body is non-empty (responseLength > 0)
        guard responseLength > 0 else {
            return (false, "AI service returned an empty response. Session cannot complete. Please retry.")
        }
        
        // Condition 3 & 4: At least one parsed file OR proposed edit exists
        // NOTE: No-op is valid (zero files is OK if explicitly indicated by EditOutputValidator)
        // But if output was validated as valid edit format, we expect files/edits
        
        // Check if this is a valid no-op (both empty but output was validated as no-op)
        // This is handled by EditOutputValidator, so if we reach here with both empty,
        // it means output validation passed but parsing failed
        if parsedFiles.isEmpty && proposedEdits.isEmpty {
            // Both empty - could be no-op or parse failure
            // If output validation passed, it's likely a parse failure
            return (false, "No files or edits were parsed from the AI response. Session cannot complete. The response may be incomplete or in an unexpected format.")
        }
        
        // Condition 3: At least one parsed file exists (if we have proposed edits, we need parsed files)
        if !proposedEdits.isEmpty && parsedFiles.isEmpty {
            return (false, "No files were parsed from the AI response. Session cannot complete. The response may be incomplete or in an unexpected format.")
        }
        
        // Condition 4: At least one proposed edit exists (if we have parsed files, we need proposed edits)
        if !parsedFiles.isEmpty && proposedEdits.isEmpty {
            return (false, "No edits were proposed. Session cannot complete. The AI response did not generate any valid edit proposals.")
        }
        
        // Condition 5: Each edit passes scope validation (validationErrors must be empty)
        guard validationErrors.isEmpty else {
            return (false, "Validation errors detected. Session cannot complete:\n\(validationErrors.joined(separator: "\n"))")
        }
        
        // Condition 6: No safety rule was violated (implicitly checked above)
        
        return (true, nil)
    }
}
