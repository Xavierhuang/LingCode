//
//  ExecutionOutcomeValidator.swift
//  LingCode
//
//  Validates execution outcomes to ensure UI truthfulness
//  CORE INVARIANT: IDE may only show "Complete" if at least one edit was applied
//

import Foundation
import EditorCore

/// Validates execution outcomes to ensure UI truthfulness
///
/// CORE INVARIANT: The IDE may only show "Complete" if at least one edit was applied.
/// Otherwise, show a failure or no-op explanation.
@MainActor
final class ExecutionOutcomeValidator {
    static let shared = ExecutionOutcomeValidator()
    
    private init() {}
    
    /// Validate the outcome of an edit session
    /// - Parameters:
    ///   - editsToApply: The edits that were supposed to be applied
    ///   - filesBefore: File states before applying edits
    ///   - filesAfter: File states after applying edits (from editor)
    /// - Returns: ExecutionOutcome indicating whether changes were actually made
    func validateOutcome(
        editsToApply: [InlineEditToApply],
        filesBefore: [String: String], // file path -> content before
        filesAfter: [String: String]  // file path -> content after
    ) -> ExecutionOutcome {
        guard !editsToApply.isEmpty else {
            return .noOp(explanation: "No edits were proposed")
        }
        
        var filesModified = 0
        var editsApplied = 0
        var validationIssues: [String] = []
        
        // Track unique files that were modified
        var modifiedFilePaths = Set<String>()
        
        // Check each edit to see if it was actually applied
        for edit in editsToApply {
            guard let contentBefore = filesBefore[edit.filePath],
                  let contentAfter = filesAfter[edit.filePath] else {
                // File not found - this is a validation issue
                validationIssues.append("File '\(edit.filePath)' was not found after applying edits")
                continue
            }
            
            // Check if content actually changed
            if contentBefore != contentAfter {
                editsApplied += 1
                // Track unique files modified
                if !modifiedFilePaths.contains(edit.filePath) {
                    modifiedFilePaths.insert(edit.filePath)
                    filesModified += 1
                }
            } else {
                // Edit was supposed to change this file but content is unchanged
                validationIssues.append("Edit to '\(edit.filePath)' did not change file content")
            }
        }
        
        // Determine if any changes were actually made
        if editsApplied == 0 {
            // No changes were made - determine why
            let explanation: String
            if validationIssues.isEmpty {
                explanation = "No matches found for the requested changes"
            } else {
                explanation = validationIssues.joined(separator: "; ")
            }
            
            return .noOp(explanation: explanation)
        }
        
        return .success(
            filesModified: filesModified,
            editsApplied: editsApplied
        )
    }
    
    /// Estimate the size of a planned change before execution
    /// - Parameters:
    ///   - plan: The execution plan
    ///   - files: Current file states
    /// - Returns: Estimated diff size (files, lines) and safety recommendation
    func estimateChangeSize(
        plan: ExecutionPlan,
        files: [String: String] // file path -> content
    ) -> (files: Int, lines: Int, isSafe: Bool, recommendation: String?) {
        // Count files that would be affected
        let affectedFiles: [String]
        switch plan.scope {
        case .entireProject:
            // Search all files
            affectedFiles = Array(files.keys)
        case .currentFile:
            // Only current file (if specified in context)
            affectedFiles = []
        case .selectedText:
            // Only selected text (no file changes)
            affectedFiles = []
        case .specificFiles:
            // Only specified files
            affectedFiles = plan.filePaths ?? []
        }
        
        // Estimate lines that would change
        var estimatedLines = 0
        for filePath in affectedFiles {
            guard let content = files[filePath] else { continue }
            let lines = content.components(separatedBy: .newlines)
            
            // Count matches for each search target
            for target in plan.searchTargets {
                let matches = countMatches(
                    pattern: target.pattern,
                    in: content,
                    caseSensitive: target.caseSensitive,
                    wholeWordsOnly: target.wholeWordsOnly,
                    isRegex: target.isRegex
                )
                
                // Estimate lines affected (rough: assume 1 line per match)
                estimatedLines += matches
            }
        }
        
        // Check safety constraints
        let isSafe: Bool
        var recommendation: String? = nil
        
        if let maxFiles = plan.safetyConstraints.maxFiles, affectedFiles.count > maxFiles {
            isSafe = false
            recommendation = "Change would affect \(affectedFiles.count) files, exceeding limit of \(maxFiles)"
        } else if let maxLines = plan.safetyConstraints.maxLines, estimatedLines > maxLines {
            isSafe = false
            recommendation = "Change would affect approximately \(estimatedLines) lines, exceeding limit of \(maxLines)"
        } else {
            isSafe = true
        }
        
        return (files: affectedFiles.count, lines: estimatedLines, isSafe: isSafe, recommendation: recommendation)
    }
    
    /// Count matches of a pattern in text
    private func countMatches(
        pattern: String,
        in text: String,
        caseSensitive: Bool,
        wholeWordsOnly: Bool,
        isRegex: Bool
    ) -> Int {
        if isRegex {
            // Use regex matching
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return 0
            }
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.numberOfMatches(in: text, options: [], range: range)
        } else {
            // Simple string matching
            let searchText = caseSensitive ? text : text.lowercased()
            let searchPattern = caseSensitive ? pattern : pattern.lowercased()
            
            if wholeWordsOnly {
                // Count whole word matches
                let words = searchText.components(separatedBy: CharacterSet.alphanumerics.inverted)
                return words.filter { $0 == searchPattern }.count
            } else {
                // Count substring matches
                var count = 0
                var searchRange = searchText.startIndex..<searchText.endIndex
                while let range = searchText.range(of: searchPattern, range: searchRange) {
                    count += 1
                    searchRange = range.upperBound..<searchText.endIndex
                }
                return count
            }
        }
    }
}
