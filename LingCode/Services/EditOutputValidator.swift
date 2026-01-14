//
//  EditOutputValidator.swift
//  LingCode
//
//  Validates AI responses to ensure they contain ONLY executable file edits
//  Rejects responses with prose, summaries, reasoning, or non-executable content
//

import Foundation

/// Validates AI output to ensure strict Edit Mode compliance
///
/// HARD OUTPUT SCHEMA:
/// - Reject responses containing markdown headings, bullet points, or explanations
/// - Distinguish between: no-op (valid), invalid format (error), silent failure (timeout/empty)
@MainActor
final class EditOutputValidator {
    static let shared = EditOutputValidator()
    
    private init() {}
    
    /// Validation result
    enum ValidationResult {
        case valid
        case invalidFormat(reason: String)
        case noOp
        case silentFailure
    }
    
    /// Validate AI response for Edit Mode compliance
    ///
    /// VALIDATION RULES (applied AFTER stream completion):
    /// - Empty output → error (silentFailure)
    /// - NO_OP → valid (explicit no-op format)
    /// - Any prose/markdown → invalid format error
    /// - Partial output must not be discarded silently
    ///
    /// - Parameter content: AI response content (complete stream)
    /// - Returns: Validation result
    func validateEditOutput(_ content: String) -> ValidationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // VALIDATION RULE: Empty output → error
        guard !trimmed.isEmpty else {
            return .silentFailure
        }
        
        // Check for explicit no-op
        if let noOpMatch = detectNoOp(content: trimmed) {
            return .noOp
        }
        
        // Check for forbidden content (markdown headings, bullet points, explanations)
        if let forbiddenReason = detectForbiddenContent(content: trimmed) {
            return .invalidFormat(reason: forbiddenReason)
        }
        
        // Check if response contains at least one file edit pattern
        if !containsFileEditPattern(content: trimmed) {
            // No file edits found - could be no-op or invalid format
            // If it's a short response, likely invalid format
            if trimmed.count < 50 {
                return .invalidFormat(reason: "Response contains no file edits and appears to be invalid format")
            }
            // Longer response without edits might be explanation-only
            return .invalidFormat(reason: "Response contains no executable file edits")
        }
        
        return .valid
    }
    
    /// Detect explicit no-op format
    private func detectNoOp(content: String) -> Bool? {
        // Check for explicit no-op JSON format
        if content.contains("\"noop\"") || content.contains("'noop'") {
            return true
        }
        
        // Check for common no-op phrases
        let noOpPhrases = [
            "no changes needed",
            "no changes required",
            "no modifications",
            "already correct",
            "no updates"
        ]
        
        let lowercased = content.lowercased()
        for phrase in noOpPhrases {
            if lowercased.contains(phrase) && content.count < 200 {
                // Short response with no-op phrase - likely valid no-op
                return true
            }
        }
        
        return nil
    }
    
    /// Detect forbidden content (markdown headings, bullet points, explanations)
    private func detectForbiddenContent(content: String) -> String? {
        // Check for markdown headings
        if content.contains("##") || content.contains("###") || content.contains("####") {
            return "Response contains markdown headings (##, ###) - forbidden in Edit Mode"
        }
        
        // Check for bullet points
        let bulletPatterns = [
            #"^\s*[-*•]\s+"#,  // Line starting with bullet
            #"^\s*\d+\.\s+"#   // Numbered list
        ]
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            for pattern in bulletPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil {
                    return "Response contains bullet points or lists - forbidden in Edit Mode"
                }
            }
        }
        
        // Check for explanatory text patterns
        let explanationPatterns = [
            "thinking process",
            "here's what",
            "i'll update",
            "i will",
            "let me",
            "summary:",
            "explanation:",
            "reasoning:",
            "analysis:"
        ]
        
        let lowercased = content.lowercased()
        for pattern in explanationPatterns {
            if lowercased.contains(pattern) {
                // Check if it's in a code block (allowed) or outside (forbidden)
                if !isInCodeBlock(content: content, pattern: pattern) {
                    return "Response contains explanatory text outside code blocks - forbidden in Edit Mode"
                }
            }
        }
        
        return nil
    }
    
    /// Check if pattern appears inside a code block (allowed) or outside (forbidden)
    private func isInCodeBlock(content: String, pattern: String) -> Bool {
        // Simple heuristic: if pattern appears after ```, it's in a code block
        if let patternRange = content.range(of: pattern, options: .caseInsensitive) {
            let beforePattern = String(content[..<patternRange.lowerBound])
            // Count code block markers before pattern
            let codeBlockCount = beforePattern.components(separatedBy: "```").count - 1
            // If odd number of markers, we're inside a code block
            return codeBlockCount % 2 == 1
        }
        return false
    }
    
    /// Check if content contains file edit patterns
    private func containsFileEditPattern(content: String) -> Bool {
        // Check for file path patterns followed by code blocks
        let fileEditPatterns = [
            #"`[^`]+\.[a-zA-Z0-9]+`[:\s]*\n```"#,  // `file.ext`:\n```
            #"\*\*[^*]+\.[a-zA-Z0-9]+\*\*[:\s]*\n```"#,  // **file.ext**:\n```
            #"###\s+[^\n]+\.[a-zA-Z0-9]+\s*\n```"#,  // ### file.ext\n```
            #"```json\s*\{[\s\S]*"edits"[\s\S]*\}"#,  // JSON edit format
        ]
        
        for pattern in fileEditPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: content, range: NSRange(location: 0, length: content.utf16.count)) != nil {
                return true
            }
        }
        
        return false
    }
}
