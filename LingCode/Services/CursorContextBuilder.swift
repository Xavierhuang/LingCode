//
//  CursorContextBuilder.swift
//  LingCode
//
//  Cursor-like context builder using Editor State, File Graph, Cursor Position, Diagnostics, Git Diff
//

import Foundation

/// Builds comprehensive context for AI requests (Cursor-style)
class CursorContextBuilder {
    static let shared = CursorContextBuilder()
    
    private let fileService = FileService.shared
    private let gitService = GitService.shared
    private let codebaseIndex = CodebaseIndexService.shared
    
    private init() {}
    
    /// Build context from editor state
    func buildContext(
        editorState: EditorState,
        cursorPosition: Int? = nil,
        selectedText: String? = nil,
        projectURL: URL? = nil,
        includeDiagnostics: Bool = true,
        includeGitDiff: Bool = true,
        includeFileGraph: Bool = true
    ) -> String {
        var contextParts: [String] = []
        
        // 1. Current file context
        if let activeDocument = editorState.activeDocument {
            contextParts.append("=== CURRENT FILE ===")
            if let filePath = activeDocument.filePath {
                contextParts.append("File: \(filePath.path)")
            }
            contextParts.append("Language: \(activeDocument.language ?? "unknown")")
            
            if let cursorPos = cursorPosition {
                let lines = activeDocument.content.components(separatedBy: .newlines)
                let lineNumber = activeDocument.content.prefix(cursorPos).components(separatedBy: .newlines).count
                contextParts.append("Cursor: Line \(lineNumber), Column \(cursorPos)")
            }
            
            if let selected = selectedText, !selected.isEmpty {
                contextParts.append("Selected: \(selected.prefix(100))")
            }
            
            contextParts.append("\nFile Content:")
            contextParts.append(activeDocument.content)
            contextParts.append("")
        }
        
        // 2. File graph (related files)
        if includeFileGraph, let activeDoc = editorState.activeDocument, let filePath = activeDoc.filePath {
            let relatedFiles = getRelatedFiles(for: filePath.path)
            if !relatedFiles.isEmpty {
                contextParts.append("=== RELATED FILES ===")
                for file in relatedFiles.prefix(5) { // Limit to 5 related files
                    let fileURL = URL(fileURLWithPath: file)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        contextParts.append("File: \(file)")
                        contextParts.append(content)
                        contextParts.append("")
                    }
                }
            }
        }
        
        // 3. Diagnostics (errors/warnings)
        if includeDiagnostics, let activeDoc = editorState.activeDocument {
            // Note: Diagnostics would come from a diagnostics service
            // For now, we'll skip this but leave the structure
        }
        
        // 4. Git diff (recent changes)
        if includeGitDiff {
            if let activeDoc = editorState.activeDocument, let filePath = activeDoc.filePath {
                // Get diff for current file
                if let diff = gitService.getDiff(for: filePath) {
                    contextParts.append("=== RECENT CHANGES (Git Diff) ===")
                    contextParts.append(diff)
                    contextParts.append("")
                }
            } else if let projectURL = projectURL, let activeDoc = editorState.activeDocument, let filePath = activeDoc.filePath {
                // Try to get diff for the file
                if let diff = gitService.getDiff(for: filePath) {
                    contextParts.append("=== RECENT CHANGES (Git Diff) ===")
                    contextParts.append(diff)
                    contextParts.append("")
                }
            }
        }
        
        // 5. Open files context
        if editorState.documents.count > 1 {
            contextParts.append("=== OTHER OPEN FILES ===")
            for doc in editorState.documents where doc.id != editorState.activeDocument?.id {
                if let filePath = doc.filePath {
                    contextParts.append("File: \(filePath.path)")
                }
                contextParts.append(String(doc.content.prefix(500)) + (doc.content.count > 500 ? "..." : ""))
                contextParts.append("")
            }
        }
        
        return contextParts.joined(separator: "\n")
    }
    
    /// Get related files based on imports/dependencies
    private func getRelatedFiles(for filePath: String) -> [String] {
        // Use codebase index to find related files
        // Get file summary to find symbols
        guard let fileSummary = codebaseIndex.getFileSummary(path: filePath) else {
            return []
        }
        
        var relatedFiles: Set<String> = []
        
        // Find files that might use symbols from this file
        // Search for symbols by name
        for symbol in fileSummary.symbols {
            let foundSymbols = codebaseIndex.findSymbol(named: symbol.name)
            for foundSymbol in foundSymbols {
                if foundSymbol.filePath != filePath {
                    relatedFiles.insert(foundSymbol.filePath)
                }
            }
        }
        
        return Array(relatedFiles)
    }
}
