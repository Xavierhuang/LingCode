//
//  IntentClassifier.swift
//  LingCode
//
//  Pre-AI intent classification for workspace-aware edit expansion
//  Detects simple deterministic intents BEFORE calling the AI
//

import Foundation

/// Classifies user intent to determine if workspace expansion is needed
///
/// WHY PRE-AI:
/// - Detects simple intents (rename/replace) before AI call
/// - Allows workspace scan and deterministic edit generation
/// - No hardcoded keywords or project-specific logic
@MainActor
final class IntentClassifier {
    static let shared = IntentClassifier()
    
    private init() {}
    
    /// Classified intent type
    /// 
    /// EDIT INTENT CLASSIFICATION:
    /// - replace/rename → deterministic text edits only, block full-file rewrites
    /// - refactor → bounded edits allowed
    /// - rewrite → full-file replacement allowed
    enum IntentType: Equatable {
        /// Simple string replacement (e.g., "change X to Y")
        /// SAFETY: Blocks full-file rewrites, only allows text replacements
        case simpleReplace(from: String, to: String)
        
        /// Rename operation (e.g., "rename X to Y")
        /// SAFETY: Blocks full-file rewrites, only allows text replacements
        case rename(from: String, to: String)
        
        /// Refactor operation (e.g., "refactor function", "improve code")
        /// SAFETY: Allows bounded edits, blocks massive deletions
        case refactor
        
        /// Full rewrite (e.g., "rewrite file", "complete rewrite")
        /// SAFETY: Allows full-file replacement
        case rewrite
        
        /// Global update (e.g., "update everywhere", "across project")
        case globalUpdate
        
        /// Complex intent - requires AI processing
        case complex
        
        /// Edit intent category for safety validation
        enum EditIntentCategory: Equatable {
            case textReplacement  // Only text replacements allowed, no full-file rewrites
            case boundedEdit      // Bounded edits allowed, block massive deletions
            case fullRewrite      // Full-file replacement allowed
            case complex          // Complex intent, requires AI processing
        }
        
        /// Get edit intent category for safety checks
        var editIntentCategory: EditIntentCategory {
            switch self {
            case .simpleReplace, .rename:
                return .textReplacement // Block full-file rewrites
            case .refactor:
                return .boundedEdit // Allow bounded edits
            case .rewrite:
                return .fullRewrite // Allow full-file replacement
            case .globalUpdate, .complex:
                return .complex // Requires AI processing
            }
        }
    }
    
    /// Classify user intent from prompt
    ///
    /// - Parameter prompt: User's edit instruction
    /// - Returns: Classified intent type
    func classify(_ prompt: String) -> IntentType {
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern 1: "change X to Y" or "replace X with Y"
        if let replaceMatch = extractReplacePattern(from: normalized) {
            return .simpleReplace(from: replaceMatch.from, to: replaceMatch.to)
        }
        
        // Pattern 2: "rename X to Y"
        if let renameMatch = extractRenamePattern(from: normalized) {
            return .rename(from: renameMatch.from, to: renameMatch.to)
        }
        
        // Pattern 3: Explicit rewrite keywords → fullFileRewrite
        // SAFETY: Only allow full-file rewrites if explicitly requested
        if containsRewriteKeywords(normalized) {
            return .rewrite
        }
        
        // Pattern 4: Refactor keywords → boundedEdit
        if containsRefactorKeywords(normalized) {
            return .refactor
        }
        
        // Pattern 5: Global update keywords
        if containsGlobalUpdateKeywords(normalized) {
            return .globalUpdate
        }
        
        // DEFAULT: Scoped edit (complex)
        // SAFETY INVARIANT: If user does NOT explicitly ask for rewrite/refactor/regenerate,
        // full-file output must be rejected
        return .complex
    }
    
    // MARK: - Private Implementation
    
    /// Extract "from" and "to" from replace patterns
    private func extractReplacePattern(from prompt: String) -> (from: String, to: String)? {
        // Patterns: "change X to Y", "replace X with Y", "update X to Y"
        let patterns = [
            #"change\s+(.+?)\s+to\s+(.+?)$"#,
            #"replace\s+(.+?)\s+with\s+(.+?)$"#,
            #"update\s+(.+?)\s+to\s+(.+?)$"#,
            #"switch\s+(.+?)\s+to\s+(.+?)$"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 3 {
                let fromRange = Range(match.range(at: 1), in: prompt)!
                let toRange = Range(match.range(at: 2), in: prompt)!
                let from = String(prompt[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let to = String(prompt[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Only return if both are non-empty and reasonable length
                if !from.isEmpty && !to.isEmpty && from.count < 100 && to.count < 100 {
                    return (from: from, to: to)
                }
            }
        }
        
        return nil
    }
    
    /// Extract "from" and "to" from rename patterns
    private func extractRenamePattern(from prompt: String) -> (from: String, to: String)? {
        // Patterns: "rename X to Y", "rename X as Y"
        let patterns = [
            #"rename\s+(.+?)\s+to\s+(.+?)$"#,
            #"rename\s+(.+?)\s+as\s+(.+?)$"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 3 {
                let fromRange = Range(match.range(at: 1), in: prompt)!
                let toRange = Range(match.range(at: 2), in: prompt)!
                let from = String(prompt[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let to = String(prompt[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !from.isEmpty && !to.isEmpty && from.count < 100 && to.count < 100 {
                    return (from: from, to: to)
                }
            }
        }
        
        return nil
    }
    
    /// Check if prompt contains refactor keywords
    private func containsRefactorKeywords(_ prompt: String) -> Bool {
        let keywords = [
            "refactor",
            "improve",
            "optimize",
            "restructure",
            "reorganize",
            "clean up",
            "cleanup"
        ]
        
        return keywords.contains { prompt.contains($0) }
    }
    
    /// Check if prompt contains rewrite keywords
    private func containsRewriteKeywords(_ prompt: String) -> Bool {
        let keywords = [
            "rewrite",
            "complete rewrite",
            "full rewrite",
            "reimplement",
            "reimplement from scratch"
        ]
        
        return keywords.contains { prompt.contains($0) }
    }
    
    /// Check if prompt contains global update keywords
    private func containsGlobalUpdateKeywords(_ prompt: String) -> Bool {
        let keywords = [
            "everywhere",
            "across project",
            "across the project",
            "in all files",
            "globally",
            "throughout",
            "project-wide"
        ]
        
        return keywords.contains { prompt.contains($0) }
    }
}
