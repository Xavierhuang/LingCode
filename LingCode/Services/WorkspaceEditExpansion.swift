//
//  WorkspaceEditExpansion.swift
//  LingCode
//
//  Coordinates workspace-aware edit expansion
//  Integrates intent classification, workspace scanning, and deterministic edit generation
//

import Foundation

/// Coordinates workspace-aware edit expansion
///
/// WHY THIS LAYER:
/// - Orchestrates intent classification, workspace scanning, and edit generation
/// - Provides unified interface for both deterministic and AI-generated edits
/// - Tracks matched vs modified files for completion summary
@MainActor
final class WorkspaceEditExpansion {
    static let shared = WorkspaceEditExpansion()
    
    private init() {}
    
    /// Expansion result
    struct ExpansionResult: Equatable {
        /// Whether expansion was performed (simple intent detected)
        let wasExpanded: Bool
        
        /// Deterministic edits generated (if any)
        let deterministicEdits: [DeterministicEditGenerator.GeneratedEdit]
        
        /// Files that matched the search (for completion summary)
        let matchedFiles: [URL]
        
        /// Source of edits (deterministic vs AI)
        let editSource: EditSource
        
        /// Search term that was matched (for summary)
        let searchTerm: String?
        
        enum EditSource: Equatable {
            case deterministic
            case ai
            case mixed
        }
        
        init(
            wasExpanded: Bool,
            deterministicEdits: [DeterministicEditGenerator.GeneratedEdit],
            matchedFiles: [URL],
            editSource: EditSource,
            searchTerm: String? = nil
        ) {
            self.wasExpanded = wasExpanded
            self.deterministicEdits = deterministicEdits
            self.matchedFiles = matchedFiles
            self.editSource = editSource
            self.searchTerm = searchTerm
        }
    }
    
    /// Expand edit scope based on user intent
    ///
    /// - Parameters:
    ///   - prompt: User's edit instruction
    ///   - workspaceURL: Root workspace directory
    /// - Returns: Expansion result with edits and metadata
    func expandEditScope(
        prompt: String,
        workspaceURL: URL?
    ) -> ExpansionResult {
        guard let workspaceURL = workspaceURL else {
            // No workspace - cannot expand
            print("⚠️ WORKSPACE EXPANSION: No workspace URL, skipping expansion")
            return ExpansionResult(
                wasExpanded: false,
                deterministicEdits: [],
                matchedFiles: [],
                editSource: .ai,
                searchTerm: nil
            )
        }
        
        // Step 1: Classify intent (PRE-AI)
        let intent = IntentClassifier.shared.classify(prompt)
        
        print("🎯 INTENT CLASSIFICATION:")
        print("   Prompt: '\(prompt)'")
        print("   Intent: \(intent)")
        
        switch intent {
        case .simpleReplace(let from, let to):
            return handleSimpleReplace(from: from, to: to, workspaceURL: workspaceURL)
            
        case .rename(let from, let to):
            // Rename is treated as a special case of replace
            return handleSimpleReplace(from: from, to: to, workspaceURL: workspaceURL)
            
        case .refactor:
            // Refactor - requires AI processing, not deterministic
            return ExpansionResult(
                wasExpanded: false,
                deterministicEdits: [],
                matchedFiles: [],
                editSource: .ai,
                searchTerm: nil
            )
            
        case .rewrite:
            // Rewrite - requires AI processing, not deterministic
            return ExpansionResult(
                wasExpanded: false,
                deterministicEdits: [],
                matchedFiles: [],
                editSource: .ai,
                searchTerm: nil
            )
            
        case .globalUpdate:
            // Global update - would need more context, treat as complex for now
            return ExpansionResult(
                wasExpanded: false,
                deterministicEdits: [],
                matchedFiles: [],
                editSource: .ai,
                searchTerm: nil
            )
            
        case .complex:
            // Complex intent - requires AI processing
            return ExpansionResult(
                wasExpanded: false,
                deterministicEdits: [],
                matchedFiles: [],
                editSource: .ai,
                searchTerm: nil
            )
        }
    }
    
    /// Convert deterministic edits to StreamingFileInfo
    ///
    /// PARSER CONTRACT: Edits can originate from deterministic IDE generation or AI
    /// Both are treated identically by the execution layer
    func convertToStreamingFileInfo(
        edits: [DeterministicEditGenerator.GeneratedEdit],
        workspaceURL: URL
    ) -> [StreamingFileInfo] {
        return edits.map { edit in
            let fileURL = workspaceURL.appendingPathComponent(edit.filePath)
            let language = detectLanguage(from: edit.filePath)
            
            // Calculate line changes
            let originalLines = edit.originalContent.components(separatedBy: .newlines)
            let newLines = edit.newContent.components(separatedBy: .newlines)
            let addedLines = max(0, newLines.count - originalLines.count)
            let removedLines = max(0, originalLines.count - newLines.count)
            
            return StreamingFileInfo(
                id: edit.filePath,
                path: edit.filePath,
                name: fileURL.lastPathComponent,
                language: language,
                content: edit.newContent,
                isStreaming: false, // Deterministic edits are complete immediately
                changeSummary: "Text replacement (\(edit.matchCount) occurrences)",
                addedLines: addedLines,
                removedLines: removedLines
            )
        }
    }
    
    // MARK: - Private Implementation
    
    /// Handle simple string replacement
    private func handleSimpleReplace(
        from: String,
        to: String,
        workspaceURL: URL
    ) -> ExpansionResult {
        // Step 2: Scan workspace for matches
        let matchedFiles = WorkspaceScanner.shared.scanForMatches(
            target: from,
            in: workspaceURL,
            caseSensitive: false
        )
        
        guard !matchedFiles.isEmpty else {
            print("⚠️ WORKSPACE EXPANSION: No files matched for '\(from)'")
            return ExpansionResult(
                wasExpanded: false,
                deterministicEdits: [],
                matchedFiles: [],
                editSource: .ai,
                searchTerm: from
            )
        }
        
        // Step 3: Generate deterministic edits
        let edits = DeterministicEditGenerator.shared.generateReplacementEdits(
            from: from,
            to: to,
            matchedFiles: matchedFiles,
            workspaceURL: workspaceURL,
            caseSensitive: false
        )
        
        let matchedURLs = matchedFiles.map { $0.fileURL }
        
        print("✅ WORKSPACE EXPANSION COMPLETE:")
        print("   Files matched: \(matchedFiles.count)")
        print("   Edits generated: \(edits.count)")
        print("   Edit source: deterministic")
        
        return ExpansionResult(
            wasExpanded: true,
            deterministicEdits: edits,
            matchedFiles: matchedURLs,
            editSource: .deterministic,
            searchTerm: from
        )
    }
    
    /// Extract search term from edit (for summary)
    private func extractSearchTerm(from edit: DeterministicEditGenerator.GeneratedEdit) -> String {
        // Try to find what was replaced by comparing original and new content
        // This is a heuristic - in practice, we'd pass the search term separately
        return "text" // Placeholder - actual implementation would track this
    }
    
    /// Detect language from file path
    private func detectLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        case "rs": return "rust"
        case "go": return "go"
        default: return "text"
        }
    }
}
