//
//  ExecutionPlanner.swift
//  LingCode
//
//  Language-agnostic execution planner
//  Translates user prompts into explicit, deterministic execution plans
//

import Foundation

/// Translates user prompts into explicit execution plans
///
/// CORE INVARIANT: User prompts are always translated into explicit execution plans before edits occur.
/// This ensures deterministic, inspectable, and safe edit operations.
///
/// The planner is language-agnostic and works for any codebase.
@MainActor
final class ExecutionPlanner {
    static let shared = ExecutionPlanner()
    
    private init() {}
    
    /// Convert a user prompt into an explicit execution plan
    ///
    /// This method normalizes common patterns like:
    /// - "change X to Y" → replace operation
    /// - "rename X to Y" → rename operation
    /// - "replace X with Y" → replace operation
    /// - "add X" → insert operation
    /// - "remove X" → delete operation
    ///
    /// The plan is deterministic and does not rely on AI inference.
    func createPlan(from prompt: String, context: PlanningContext) -> ExecutionPlan {
        let normalizedPrompt = normalizePrompt(prompt)
        
        // Detect operation type from prompt patterns
        let operationType = detectOperationType(from: normalizedPrompt)
        
        // Extract search targets and replacement content
        let (searchTargets, replacementContent) = extractTargetsAndReplacement(
            from: normalizedPrompt,
            operationType: operationType
        )
        
        // Determine scope
        let scope = determineScope(from: normalizedPrompt, context: context)
        
        // Extract file paths if scope is specific
        let filePaths = extractFilePaths(from: normalizedPrompt, context: context)
        
        // Create safety constraints
        let safetyConstraints = createSafetyConstraints(from: normalizedPrompt, context: context)
        
        // Generate human-readable description
        let description = generateDescription(
            operationType: operationType,
            searchTargets: searchTargets,
            replacementContent: replacementContent,
            scope: scope
        )
        
        return ExecutionPlan(
            operationType: operationType,
            searchTargets: searchTargets,
            replacementContent: replacementContent,
            scope: scope,
            filePaths: filePaths,
            safetyConstraints: safetyConstraints,
            originalPrompt: prompt,
            description: description
        )
    }
    
    // MARK: - Planning Context
    
    /// Context information needed for planning
    public struct PlanningContext {
        /// Currently selected text (if any)
        let selectedText: String?
        
        /// Current file path (if any)
        let currentFilePath: String?
        
        /// All file paths in the project
        let allFilePaths: [String]
        
        /// Whether user wants to limit scope to current file
        let limitToCurrentFile: Bool
        
        public init(
            selectedText: String? = nil,
            currentFilePath: String? = nil,
            allFilePaths: [String] = [],
            limitToCurrentFile: Bool = false
        ) {
            self.selectedText = selectedText
            self.currentFilePath = currentFilePath
            self.allFilePaths = allFilePaths
            self.limitToCurrentFile = limitToCurrentFile
        }
    }
    
    // MARK: - Private Implementation
    
    /// Normalize prompt to lowercase for pattern matching (preserves original for plan)
    private func normalizePrompt(_ prompt: String) -> String {
        prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Detect operation type from prompt patterns
    private func detectOperationType(from normalizedPrompt: String) -> ExecutionPlan.OperationType {
        // Check for rename patterns first (more specific)
        if normalizedPrompt.contains("rename") {
            return .rename
        }
        
        // Check for delete/remove patterns
        if normalizedPrompt.contains("delete") || normalizedPrompt.contains("remove") {
            return .delete
        }
        
        // Check for insert/add patterns
        if normalizedPrompt.contains("add") || normalizedPrompt.contains("insert") {
            return .insert
        }
        
        // Default to replace for "change", "replace", "update", etc.
        return .replace
    }
    
    /// Extract search targets and replacement content from prompt
    private func extractTargetsAndReplacement(
        from normalizedPrompt: String,
        operationType: ExecutionPlan.OperationType
    ) -> ([ExecutionPlan.SearchTarget], String?) {
        // Common patterns:
        // - "change X to Y"
        // - "replace X with Y"
        // - "rename X to Y"
        // - "remove X"
        // - "add Y"
        
        var searchTargets: [ExecutionPlan.SearchTarget] = []
        var replacementContent: String? = nil
        
        switch operationType {
        case .replace, .rename:
            // Extract "X" and "Y" from patterns like "change X to Y"
            if let match = extractChangePattern(from: normalizedPrompt) {
                searchTargets.append(ExecutionPlan.SearchTarget(
                    pattern: match.from,
                    caseSensitive: false,
                    wholeWordsOnly: shouldUseWholeWords(match.from)
                ))
                replacementContent = match.to
            } else {
                // Fallback: try to extract from original prompt
                searchTargets.append(ExecutionPlan.SearchTarget(pattern: ""))
            }
            
        case .delete:
            // Extract "X" from patterns like "remove X" or "delete X"
            if let target = extractDeleteTarget(from: normalizedPrompt) {
                searchTargets.append(ExecutionPlan.SearchTarget(
                    pattern: target,
                    caseSensitive: false,
                    wholeWordsOnly: shouldUseWholeWords(target)
                ))
            } else {
                searchTargets.append(ExecutionPlan.SearchTarget(pattern: ""))
            }
            
        case .insert:
            // Extract "Y" from patterns like "add Y"
            if let content = extractInsertContent(from: normalizedPrompt) {
                replacementContent = content
            }
            // No search target for insert operations
        }
        
        return (searchTargets, replacementContent)
    }
    
    /// Extract "from" and "to" from change patterns
    private func extractChangePattern(from prompt: String) -> (from: String, to: String)? {
        // Patterns: "change X to Y", "replace X with Y", "rename X to Y"
        let patterns = [
            #"change\s+(.+?)\s+to\s+(.+?)$"#,
            #"replace\s+(.+?)\s+with\s+(.+?)$"#,
            #"rename\s+(.+?)\s+to\s+(.+?)$"#,
            #"update\s+(.+?)\s+to\s+(.+?)$"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 3 {
                let fromRange = Range(match.range(at: 1), in: prompt)!
                let toRange = Range(match.range(at: 2), in: prompt)!
                return (
                    from: String(prompt[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                    to: String(prompt[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        
        return nil
    }
    
    /// Extract delete target from prompt
    private func extractDeleteTarget(from prompt: String) -> String? {
        // Patterns: "remove X", "delete X"
        let patterns = [
            #"remove\s+(.+?)$"#,
            #"delete\s+(.+?)$"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 2 {
                let range = Range(match.range(at: 1), in: prompt)!
                return String(prompt[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    /// Extract insert content from prompt
    private func extractInsertContent(from prompt: String) -> String? {
        // Patterns: "add X", "insert X"
        let patterns = [
            #"add\s+(.+?)$"#,
            #"insert\s+(.+?)$"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 2 {
                let range = Range(match.range(at: 1), in: prompt)!
                return String(prompt[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    /// Determine if whole words should be used (for identifiers, keywords, etc.)
    private func shouldUseWholeWords(_ pattern: String) -> Bool {
        // Use whole words for short patterns that look like identifiers
        pattern.count < 20 && !pattern.contains(" ") && !pattern.contains("\n")
    }
    
    /// Determine scope from prompt and context
    private func determineScope(
        from prompt: String,
        context: PlanningContext
    ) -> ExecutionPlan.Scope {
        // Check if prompt mentions specific files
        if !context.allFilePaths.isEmpty {
            let mentionedFiles = context.allFilePaths.filter { filePath in
                let fileName = (filePath as NSString).lastPathComponent
                return prompt.contains(fileName.lowercased())
            }
            if !mentionedFiles.isEmpty {
                return .specificFiles
            }
        }
        
        // Check if user wants to limit to current file
        if context.limitToCurrentFile || context.currentFilePath != nil {
            return .currentFile
        }
        
        // Check if there's selected text
        if let selectedText = context.selectedText, !selectedText.isEmpty {
            return .selectedText
        }
        
        // Default to entire project
        return .entireProject
    }
    
    /// Extract file paths from prompt
    private func extractFilePaths(
        from prompt: String,
        context: PlanningContext
    ) -> [String]? {
        guard !context.allFilePaths.isEmpty else { return nil }
        
        let mentionedFiles = context.allFilePaths.filter { filePath in
            let fileName = (filePath as NSString).lastPathComponent
            return prompt.contains(fileName.lowercased())
        }
        
        return mentionedFiles.isEmpty ? nil : mentionedFiles
    }
    
    /// Create safety constraints from prompt and context
    private func createSafetyConstraints(
        from prompt: String,
        context: PlanningContext
    ) -> ExecutionPlan.SafetyConstraints {
        // Default safety constraints
        // Can be customized based on prompt or context if needed
        return ExecutionPlan.SafetyConstraints(
            maxFiles: nil,  // No limit by default
            maxLines: nil,  // No limit by default
            preventSyntaxErrors: true,
            requireConfirmationForLargeChanges: true
        )
    }
    
    /// Generate human-readable description
    private func generateDescription(
        operationType: ExecutionPlan.OperationType,
        searchTargets: [ExecutionPlan.SearchTarget],
        replacementContent: String?,
        scope: ExecutionPlan.Scope
    ) -> String {
        let operationDesc: String
        switch operationType {
        case .replace:
            if let target = searchTargets.first?.pattern, let replacement = replacementContent {
                operationDesc = "Replace '\(target)' with '\(replacement)'"
            } else {
                operationDesc = "Replace content"
            }
        case .rename:
            if let target = searchTargets.first?.pattern, let replacement = replacementContent {
                operationDesc = "Rename '\(target)' to '\(replacement)'"
            } else {
                operationDesc = "Rename identifier"
            }
        case .delete:
            if let target = searchTargets.first?.pattern {
                operationDesc = "Delete '\(target)'"
            } else {
                operationDesc = "Delete content"
            }
        case .insert:
            if let content = replacementContent {
                operationDesc = "Insert '\(content)'"
            } else {
                operationDesc = "Insert content"
            }
        }
        
        let scopeDesc: String
        switch scope {
        case .entireProject:
            scopeDesc = "across entire project"
        case .currentFile:
            scopeDesc = "in current file"
        case .selectedText:
            scopeDesc = "in selected text"
        case .specificFiles:
            scopeDesc = "in specific files"
        }
        
        return "\(operationDesc) \(scopeDesc)"
    }
}
