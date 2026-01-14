//
//  ExecutionPlan.swift
//  LingCode
//
//  Language-agnostic execution planning layer
//  Translates user prompts into explicit, deterministic execution plans
//

import Foundation

/// Explicit execution plan for code edits
/// 
/// CORE INVARIANT: User prompts are always translated into explicit execution plans before edits occur.
/// This ensures deterministic, inspectable, and safe edit operations.
public struct ExecutionPlan: Codable, Equatable {
    /// Type of operation to perform
    public enum OperationType: String, Codable, Equatable {
        case replace = "replace"      // Replace search target with replacement content
        case insert = "insert"        // Insert content at specific location
        case delete = "delete"        // Delete search target
        case rename = "rename"        // Rename identifier (special case of replace)
    }
    
    /// Search target(s) to find in the codebase
    public struct SearchTarget: Codable, Equatable {
        /// The text pattern to search for
        public let pattern: String
        
        /// Whether search is case-sensitive (default: false)
        public let caseSensitive: Bool
        
        /// Whether to match whole words only (default: false)
        public let wholeWordsOnly: Bool
        
        /// Whether pattern is a regular expression (default: false)
        public let isRegex: Bool
        
        public init(
            pattern: String,
            caseSensitive: Bool = false,
            wholeWordsOnly: Bool = false,
            isRegex: Bool = false
        ) {
            self.pattern = pattern
            self.caseSensitive = caseSensitive
            self.wholeWordsOnly = wholeWordsOnly
            self.isRegex = isRegex
        }
    }
    
    /// Operation type
    public let operationType: OperationType
    
    /// Search target(s) to find
    public let searchTargets: [SearchTarget]
    
    /// Replacement content (for replace/insert operations)
    public let replacementContent: String?
    
    /// Scope of the operation (default: entire project)
    public enum Scope: String, Codable, Equatable {
        case entireProject = "entire_project"    // Search entire project
        case currentFile = "current_file"        // Only current file
        case selectedText = "selected_text"      // Only selected text
        case specificFiles = "specific_files"    // Specific file paths
    }
    public let scope: Scope
    
    /// Specific file paths (if scope is .specificFiles)
    public let filePaths: [String]?
    
    /// Safety constraints
    public struct SafetyConstraints: Codable, Equatable {
        /// Maximum number of files that can be modified (default: unlimited)
        public let maxFiles: Int?
        
        /// Maximum number of lines that can be changed (default: unlimited)
        public let maxLines: Int?
        
        /// Whether to prevent syntax-breaking edits (default: true)
        public let preventSyntaxErrors: Bool
        
        /// Whether to require confirmation for large changes (default: true)
        public let requireConfirmationForLargeChanges: Bool
        
        public init(
            maxFiles: Int? = nil,
            maxLines: Int? = nil,
            preventSyntaxErrors: Bool = true,
            requireConfirmationForLargeChanges: Bool = true
        ) {
            self.maxFiles = maxFiles
            self.maxLines = maxLines
            self.preventSyntaxErrors = preventSyntaxErrors
            self.requireConfirmationForLargeChanges = requireConfirmationForLargeChanges
        }
    }
    public let safetyConstraints: SafetyConstraints
    
    /// Original user prompt (for reference)
    public let originalPrompt: String
    
    /// Human-readable description of what this plan will do
    public let description: String
    
    public init(
        operationType: OperationType,
        searchTargets: [SearchTarget],
        replacementContent: String? = nil,
        scope: Scope = .entireProject,
        filePaths: [String]? = nil,
        safetyConstraints: SafetyConstraints = SafetyConstraints(),
        originalPrompt: String,
        description: String
    ) {
        self.operationType = operationType
        self.searchTargets = searchTargets
        self.replacementContent = replacementContent
        self.scope = scope
        self.filePaths = filePaths
        self.safetyConstraints = safetyConstraints
        self.originalPrompt = originalPrompt
        self.description = description
    }
}

/// Execution outcome validation result
public struct ExecutionOutcome: Equatable {
    /// Whether any changes were actually made
    public let changesApplied: Bool
    
    /// Number of files modified
    public let filesModified: Int
    
    /// Number of edits applied
    public let editsApplied: Int
    
    /// Explanation if no changes were made
    public let noOpExplanation: String?
    
    /// Validation issues (if any)
    public let validationIssues: [String]
    
    public init(
        changesApplied: Bool,
        filesModified: Int = 0,
        editsApplied: Int = 0,
        noOpExplanation: String? = nil,
        validationIssues: [String] = []
    ) {
        self.changesApplied = changesApplied
        self.filesModified = filesModified
        self.editsApplied = editsApplied
        self.noOpExplanation = noOpExplanation
        self.validationIssues = validationIssues
    }
    
    /// Convenience initializer for no-op outcome
    public static func noOp(explanation: String) -> ExecutionOutcome {
        ExecutionOutcome(
            changesApplied: false,
            noOpExplanation: explanation
        )
    }
    
    /// Convenience initializer for successful outcome
    public static func success(filesModified: Int, editsApplied: Int) -> ExecutionOutcome {
        ExecutionOutcome(
            changesApplied: true,
            filesModified: filesModified,
            editsApplied: editsApplied
        )
    }
}
