//
//  DiffSafetyGuard.swift
//  LingCode
//
//  Safety guard for edit validation based on intent
//  Blocks unsafe edits (full-file rewrites, massive deletions) for replace/rename intents
//

import Foundation

/// Safety guard for edit validation
///
/// WHY THIS EXISTS:
/// - Prevents full-file rewrites for simple replace/rename intents
/// - Blocks massive deletions that could indicate parsing errors
/// - Ensures user intent matches actual edit behavior
@MainActor
final class DiffSafetyGuard {
    static let shared = DiffSafetyGuard()
    
    private init() {}
    
    /// Safety validation result
    enum ValidationResult: Equatable {
        case safe
        case unsafe(reason: String)
    }
    
    /// Maximum lines that can be deleted for replace/rename intents
    /// SAFETY: If more than this many lines are deleted, it's likely a full-file rewrite
    private let maxDeletionThreshold: Int = 50
    
    /// Maximum percentage of file that can be deleted for replace/rename intents
    /// SAFETY: If more than this percentage is deleted, reject the edit
    private let maxDeletionPercentage: Double = 0.3 // 30%
    
    /// Maximum lines that can be deleted for scoped edits (default intent)
    /// SAFETY: If >200 lines OR >20% deleted AND intent != fullFileRewrite, abort
    private let maxScopedDeletionLines: Int = 200
    
    /// Maximum percentage for scoped edits
    /// SAFETY: If >20% of file deleted AND intent != fullFileRewrite, abort
    private let maxScopedDeletionPercentage: Double = 0.2 // 20%
    
    /// Validate edit safety based on intent
    ///
    /// - Parameters:
    ///   - originalContent: Original file content
    ///   - newContent: Proposed new content
    ///   - intentCategory: Intent category from IntentClassifier
    /// - Returns: Validation result
    func validateEdit(
        originalContent: String,
        newContent: String,
        intentCategory: IntentClassifier.IntentType.EditIntentCategory
    ) -> ValidationResult {
        let originalLines = originalContent.components(separatedBy: .newlines)
        let newLines = newContent.components(separatedBy: .newlines)
        
        let deletedLines = max(0, originalLines.count - newLines.count)
        let deletionPercentage = originalLines.isEmpty ? 0.0 : Double(deletedLines) / Double(originalLines.count)
        
        switch intentCategory {
        case .textReplacement:
            // TEXT REPLACEMENT SAFETY: Block full-file rewrites and large deletions
            // WHY: Simple replace/rename should only change text, not rewrite entire files
            
            // Check 1: Block if entire file is replaced (content completely different)
            if isFullFileRewrite(original: originalContent, new: newContent) {
                return .unsafe(reason: "Full-file rewrite detected. For simple text replacement, only matching text should be changed.")
            }
            
            // Check 2: Block if too many lines deleted
            if deletedLines > maxDeletionThreshold {
                return .unsafe(reason: "Too many lines deleted (\(deletedLines) lines). Simple text replacement should not delete large portions of code.")
            }
            
            // Check 3: Block if too high percentage deleted
            if deletionPercentage > maxDeletionPercentage {
                return .unsafe(reason: "Too much content deleted (\(Int(deletionPercentage * 100))%). Simple text replacement should preserve most of the file.")
            }
            
            return .safe
            
        case .boundedEdit:
            // BOUNDED EDIT SAFETY: Allow edits but block massive deletions
            // WHY: Refactoring should be bounded, not delete entire files
            
            if deletedLines > maxDeletionThreshold * 2 {
                return .unsafe(reason: "Too many lines deleted (\(deletedLines) lines). Refactoring should be bounded.")
            }
            
            if deletionPercentage > 0.5 {
                return .unsafe(reason: "Too much content deleted (\(Int(deletionPercentage * 100))%). Refactoring should preserve most of the code.")
            }
            
            return .safe
            
        case .fullRewrite:
            // FULL REWRITE: Allow all edits
            // WHY: User explicitly requested rewrite
            return .safe
            
        case .complex:
            // SCOPED EDIT SAFETY (default intent)
            // SAFETY INVARIANT: If >20% of file OR >200 lines deleted AND intent != fullFileRewrite, abort
            // WHY: Default intent is scoped edit - large deletions indicate full-file rewrite attempt
            
            // Check 1: Block if too many lines deleted (>200 lines)
            if deletedLines > maxScopedDeletionLines {
                return .unsafe(reason: "Change exceeds requested scope. \(deletedLines) lines deleted, but only scoped edits are allowed. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            
            // Check 2: Block if too high percentage deleted (>20%)
            if deletionPercentage > maxScopedDeletionPercentage {
                return .unsafe(reason: "Change exceeds requested scope. \(Int(deletionPercentage * 100))% of file deleted, but only scoped edits are allowed. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            
            // Check 3: Block full-file rewrites for scoped edits
            if isFullFileRewrite(original: originalContent, new: newContent) {
                return .unsafe(reason: "Full-file rewrite detected. For scoped edits, only specific changes should be made. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            
            return .safe
        }
    }
    
    // MARK: - Private Implementation
    
    /// Check if edit is a full-file rewrite (content completely different)
    private func isFullFileRewrite(original: String, new: String) -> Bool {
        // Heuristic: If less than 30% of original content appears in new content,
        // it's likely a full rewrite
        let originalWords = Set(original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let newWords = Set(new.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        guard !originalWords.isEmpty else { return false }
        
        let commonWords = originalWords.intersection(newWords)
        let similarity = Double(commonWords.count) / Double(originalWords.count)
        
        // If similarity is very low, it's likely a full rewrite
        return similarity < 0.3
    }
}
