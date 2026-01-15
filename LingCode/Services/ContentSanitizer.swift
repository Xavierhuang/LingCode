//
//  ContentSanitizer.swift
//  LingCode
//
//  Sanitizes parsed file content to remove any reasoning, markdown headings, or explanations
//  that might leak through from AI output
//
//  ARCHITECTURE: Hard boundary - ensures CursorStreamingFileCard only receives executable code
//

import Foundation

/// Sanitizes file content to remove reasoning, markdown, or explanations
///
/// PROBLEM 1 FIX: Ensures UI only receives parsed, validated file content
/// - Removes markdown headings (##, ###, #)
/// - Removes reasoning text patterns
/// - Removes workflow/planning text
/// - Ensures only executable code reaches the UI
@MainActor
final class ContentSanitizer {
    static let shared = ContentSanitizer()
    
    private init() {}
    
    /// Sanitize file content to remove reasoning/markdown
    ///
    /// - Parameter content: Raw parsed content (may contain reasoning)
    /// - Returns: Sanitized content (only executable code)
    func sanitizeContent(_ content: String) -> String {
        var sanitized = content
        
        // Remove markdown headings (##, ###, #)
        sanitized = removeMarkdownHeadings(sanitized)
        
        // Remove reasoning/planning text patterns
        sanitized = removeReasoningText(sanitized)
        
        // Remove workflow/planning markers
        sanitized = removeWorkflowMarkers(sanitized)
        
        // Clean up excessive whitespace introduced by removals
        sanitized = cleanWhitespace(sanitized)
        
        return sanitized
    }
    
    /// Remove markdown headings
    private func removeMarkdownHeadings(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Remove lines that are markdown headings
            return !trimmed.hasPrefix("#") && 
                   !trimmed.hasPrefix("##") && 
                   !trimmed.hasPrefix("###")
        }.joined(separator: "\n")
    }
    
    /// Remove reasoning/planning text patterns
    private func removeReasoningText(_ content: String) -> String {
        let reasoningPatterns = [
            "thinking:",
            "reasoning:",
            "plan:",
            "planning:",
            "analysis:",
            "summary:",
            "explanation:",
            "here's what",
            "i'll update",
            "i will",
            "let me",
            "step 1:",
            "step 2:",
            "step 3:",
            "first,",
            "next,",
            "finally,"
        ]
        
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { line in
            let lowercased = line.lowercased().trimmingCharacters(in: .whitespaces)
            // Remove lines that start with reasoning patterns
            for pattern in reasoningPatterns {
                if lowercased.hasPrefix(pattern) {
                    return false
                }
            }
            return true
        }.joined(separator: "\n")
    }
    
    /// Remove workflow/planning markers
    private func removeWorkflowMarkers(_ content: String) -> String {
        let workflowMarkers = [
            "plan → do → check → act",
            "workflow:",
            "process:",
            "steps:",
            "todo:",
            "note:",
            "important:",
            "warning:"
        ]
        
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { line in
            let lowercased = line.lowercased().trimmingCharacters(in: .whitespaces)
            // Remove lines that contain workflow markers
            for marker in workflowMarkers {
                if lowercased.contains(marker) {
                    return false
                }
            }
            return true
        }.joined(separator: "\n")
    }
    
    /// Clean up excessive whitespace
    private func cleanWhitespace(_ content: String) -> String {
        // Remove multiple consecutive blank lines (keep max 2)
        var cleaned = content
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        // Trim leading/trailing whitespace
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
