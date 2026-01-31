//
//  ValidationCoordinator.swift
//  LingCode
//
//  Unified validation coordinator consolidating:
//  - EditSafetyCoordinator (intent classification, scope validation)
//  - DiffSafetyGuard (edit scope validation - merged)
//  - SessionCompletionValidator (completion gate - merged)
//  - EditOutputValidator (output format validation)
//  - ExecutionOutcomeValidator (execution outcome validation)
//
//  SAFETY INVARIANTS:
//  1. Small edit requests never cause large file deletions
//  2. Empty or failed AI responses never reach parse or apply stages
//  3. "Response Complete" only appears when valid edits exist
//  4. Terminal commands and sensitive files require approval (AgentSafetyGuard - separate)
//

import Foundation
import EditorCore

// MARK: - ValidationCoordinator

@MainActor
final class ValidationCoordinator {
    static let shared = ValidationCoordinator()
    
    private init() {}
    
    // MARK: - Intent Classification
    
    /// Execution intent for safety validation
    enum ExecutionIntent: Equatable {
        case textReplacement    // Only text replacements allowed
        case symbolRename       // Symbol rename (similar to text replacement)
        case scopedEdit         // Bounded scoped edits (DEFAULT)
        case fullFileRewrite    // Full-file rewrite (explicit only)
        
        /// Map from IntentEngine's EditIntentCategory
        init(from category: IntentEngine.IntentType.EditIntentCategory) {
            switch category {
            case .textReplacement:
                self = .textReplacement
            case .boundedEdit:
                self = .scopedEdit
            case .fullRewrite:
                self = .fullFileRewrite
            case .complex:
                self = .scopedEdit // Default to scoped
            }
        }
    }
    
    /// Classify execution intent from user prompt
    func classifyExecutionIntent(_ prompt: String) -> ExecutionIntent {
        let intent = IntentEngine.shared.classifyIntent(prompt)
        return ExecutionIntent(from: intent.editIntentCategory)
    }
    
    // MARK: - Scope Validation (Merged from DiffSafetyGuard + EditSafetyCoordinator)
    
    /// Thresholds for edit scope validation
    private struct ScopeThresholds {
        // Text replacement thresholds
        static let maxDeletionForReplacement = 50
        static let maxDeletionPercentageForReplacement = 0.3
        
        // Scoped edit thresholds (DEFAULT)
        static let maxDeletionForScoped = 200
        static let maxDeletionPercentageForScoped = 0.2
        
        // Bounded edit thresholds (refactor)
        static let maxDeletionForBounded = 100
        static let maxDeletionPercentageForBounded = 0.5
    }
    
    /// Scope validation result
    enum ScopeValidationResult: Equatable {
        case safe
        case unsafe(reason: String)
        
        var isValid: Bool {
            if case .safe = self { return true }
            return false
        }
        
        var errorMessage: String? {
            if case .unsafe(let reason) = self { return reason }
            return nil
        }
    }
    
    /// Validate edit scope against execution intent
    func validateEditScope(
        originalContent: String,
        newContent: String,
        intent: ExecutionIntent
    ) -> ScopeValidationResult {
        let originalLines = originalContent.components(separatedBy: .newlines)
        let newLines = newContent.components(separatedBy: .newlines)
        
        let deletedLines = max(0, originalLines.count - newLines.count)
        let deletionPercentage = originalLines.isEmpty ? 0.0 : Double(deletedLines) / Double(originalLines.count)
        
        switch intent {
        case .textReplacement, .symbolRename:
            // Check for full-file rewrite
            if isFullFileRewrite(original: originalContent, new: newContent) {
                return .unsafe(reason: "Full-file rewrite detected. For simple text replacement, only matching text should be changed.")
            }
            // Check deletion thresholds
            if deletedLines > ScopeThresholds.maxDeletionForReplacement {
                return .unsafe(reason: "Too many lines deleted (\(deletedLines) lines). Simple text replacement should not delete large portions of code.")
            }
            if deletionPercentage > ScopeThresholds.maxDeletionPercentageForReplacement {
                return .unsafe(reason: "Too much content deleted (\(Int(deletionPercentage * 100))%). Simple text replacement should preserve most of the file.")
            }
            return .safe
            
        case .scopedEdit:
            // Scoped edit (default): Block if >20% OR >200 lines
            if deletedLines > ScopeThresholds.maxDeletionForScoped {
                return .unsafe(reason: "Change exceeds requested scope. \(deletedLines) lines deleted, but only scoped edits are allowed. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            if deletionPercentage > ScopeThresholds.maxDeletionPercentageForScoped {
                return .unsafe(reason: "Change exceeds requested scope. \(Int(deletionPercentage * 100))% of file deleted, but only scoped edits are allowed. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            // Check for full-file rewrite
            if isFullFileRewrite(original: originalContent, new: newContent) {
                return .unsafe(reason: "Full-file rewrite detected. For scoped edits, only specific changes should be made. If you intended a full rewrite, please explicitly request 'rewrite' or 'refactor'.")
            }
            return .safe
            
        case .fullFileRewrite:
            // Full rewrite: Allow all changes
            return .safe
        }
    }
    
    /// Check if edit is a full-file rewrite (content completely different)
    private func isFullFileRewrite(original: String, new: String) -> Bool {
        let originalWords = Set(original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let newWords = Set(new.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        guard !originalWords.isEmpty else { return false }
        
        let commonWords = originalWords.intersection(newWords)
        let similarity = Double(commonWords.count) / Double(originalWords.count)
        
        return similarity < 0.3
    }
    
    // MARK: - Output Validation (From EditOutputValidator)
    
    /// Output validation result
    enum OutputValidationResult {
        case valid
        case recovered(String)
        case invalidFormat(reason: String)
        case noOp
        case silentFailure
    }
    
    /// Validate AI output format
    func validateEditOutput(_ content: String) -> OutputValidationResult {
        // Fast empty check
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .silentFailure
        }
        
        // Fast No-Op check
        if isNoOp(content) { return .noOp }
        
        // Check for forbidden content
        if hasForbiddenContent(content) {
            let recovered = stripGarbage(from: content)
            if recovered.isEmpty { return .noOp }
            return .recovered(recovered)
        }
        
        // Check for code blocks
        if !content.contains("```") {
            if content.count < 50 {
                return .invalidFormat(reason: "Response contains no file edits (invalid format)")
            }
            return .invalidFormat(reason: "Response contains no executable file edits")
        }
        
        return .valid
    }
    
    private func isNoOp(_ content: String) -> Bool {
        if content.contains("\"noop\"") || content.contains("'noop'") { return true }
        if content.count < 200 {
            let lower = content.lowercased()
            if lower.contains("no changes needed") || lower.contains("no changes required") { return true }
        }
        return false
    }
    
    private func hasForbiddenContent(_ content: String) -> Bool {
        let lower = content.lowercased()
        let forbiddenPhrases = ["thinking process", "here's what", "i'll update", "i will", "summary:", "explanation:", "reasoning:", "analysis:"]
        
        for phrase in forbiddenPhrases {
            if lower.contains(phrase) {
                if !isInCodeBlock(content: content, phrase: phrase) {
                    return true
                }
            }
        }
        return false
    }
    
    private func stripGarbage(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return false }
            return true
        }.joined(separator: "\n")
    }
    
    private func isInCodeBlock(content: String, phrase: String) -> Bool {
        guard let range = content.range(of: phrase, options: .caseInsensitive) else { return false }
        let prefix = content[..<range.lowerBound]
        let backtickCount = prefix.filter { $0 == "`" }.count
        return backtickCount % 2 != 0
    }
    
    // MARK: - Completion Gate (Merged from SessionCompletionValidator + EditSafetyCoordinator)
    
    /// HARD COMPLETION GATE: Session may only complete if ALL are true:
    /// 1. HTTP status is 2xx
    /// 2. Response body is non-empty (responseLength > 0)
    /// 3. At least one parsed file exists (parsedFiles.count > 0)
    /// 4. At least one proposed edit exists (proposedEdits.count > 0)
    /// 5. Each edit passes scope validation
    /// 6. No safety rule was violated
    func checkCompletionGate(
        httpStatus: Int?,
        responseLength: Int,
        parsedFiles: [StreamingFileInfo],
        proposedEdits: [Any],
        validationErrors: [String]
    ) -> (canComplete: Bool, errorMessage: String?) {
        // Condition 1: HTTP status is 2xx
        guard let status = httpStatus, status >= 200 && status < 300 else {
            return (false, "AI request failed with HTTP \(httpStatus ?? 0). Please retry.")
        }
        
        // Condition 2: Response body is non-empty
        guard responseLength > 0 else {
            return (false, "AI service returned an empty response. Please retry.")
        }
        
        // Condition 5 (early): Surface validation errors first
        guard validationErrors.isEmpty else {
            return (false, "Validation errors detected:\n\(validationErrors.joined(separator: "\n"))")
        }
        
        // Condition 3 & 4: At least one parsed file OR proposed edit exists
        if parsedFiles.isEmpty && proposedEdits.isEmpty {
            return (false, "No files or edits were parsed from the AI response. The response may be incomplete or in an unexpected format.")
        }
        
        // Condition 3: At least one parsed file exists (if we have proposed edits)
        if !proposedEdits.isEmpty && parsedFiles.isEmpty {
            return (false, "No files were parsed from the AI response. The response may be incomplete or in an unexpected format.")
        }
        
        // Condition 4: At least one proposed edit exists (if we have parsed files)
        if !parsedFiles.isEmpty && proposedEdits.isEmpty {
            return (false, "No edits were proposed. The AI response did not generate any valid edit proposals.")
        }
        
        return (true, nil)
    }
    
    // MARK: - Execution Outcome Validation (From ExecutionOutcomeValidator)
    
    /// Validate the outcome of an edit session
    func validateOutcome(
        editsToApply: [InlineEditToApply],
        filesBefore: [String: String],
        filesAfter: [String: String]
    ) -> ExecutionOutcome {
        guard !editsToApply.isEmpty else {
            return .noOp(explanation: "No edits were proposed")
        }
        
        var filesModified = 0
        var editsApplied = 0
        var validationIssues: [String] = []
        var modifiedFilePaths = Set<String>()
        
        for edit in editsToApply {
            guard let contentBefore = filesBefore[edit.filePath],
                  let contentAfter = filesAfter[edit.filePath] else {
                validationIssues.append("File '\(edit.filePath)' was not found after applying edits")
                continue
            }
            
            if contentBefore != contentAfter {
                editsApplied += 1
                if !modifiedFilePaths.contains(edit.filePath) {
                    modifiedFilePaths.insert(edit.filePath)
                    filesModified += 1
                }
            } else {
                validationIssues.append("Edit to '\(edit.filePath)' did not change file content")
            }
        }
        
        if editsApplied == 0 {
            let explanation: String
            if validationIssues.isEmpty {
                explanation = "No matches found for the requested changes"
            } else {
                explanation = validationIssues.joined(separator: "; ")
            }
            return .noOp(explanation: explanation)
        }
        
        return .success(filesModified: filesModified, editsApplied: editsApplied)
    }
    
    /// Estimate the size of a planned change before execution
    func estimateChangeSize(
        plan: ExecutionPlan,
        files: [String: String]
    ) -> (files: Int, lines: Int, isSafe: Bool, recommendation: String?) {
        let affectedFiles: [String]
        switch plan.scope {
        case .entireProject:
            affectedFiles = Array(files.keys)
        case .currentFile, .selectedText:
            affectedFiles = []
        case .specificFiles:
            affectedFiles = plan.filePaths ?? []
        }
        
        var estimatedLines = 0
        for filePath in affectedFiles {
            guard let content = files[filePath] else { continue }
            
            for target in plan.searchTargets {
                let matches = countMatches(
                    pattern: target.pattern,
                    in: content,
                    caseSensitive: target.caseSensitive,
                    wholeWordsOnly: target.wholeWordsOnly,
                    isRegex: target.isRegex
                )
                estimatedLines += matches
            }
        }
        
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
    
    private func countMatches(
        pattern: String,
        in text: String,
        caseSensitive: Bool,
        wholeWordsOnly: Bool,
        isRegex: Bool
    ) -> Int {
        if isRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return 0
            }
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.numberOfMatches(in: text, options: [], range: range)
        } else {
            let searchText = caseSensitive ? text : text.lowercased()
            let searchPattern = caseSensitive ? pattern : pattern.lowercased()
            
            if wholeWordsOnly {
                let words = searchText.components(separatedBy: CharacterSet.alphanumerics.inverted)
                return words.filter { $0 == searchPattern }.count
            } else {
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
