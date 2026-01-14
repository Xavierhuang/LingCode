//
//  EditorView+ContextBuilder.swift
//  LingCode
//
//  Helper extension to build comprehensive context for AI requests
//  Ensures all project files are included in context
//

import Foundation

extension EditorView {
    /// Build comprehensive context that includes all project files
    /// FILE CONTEXT INGESTION: Ensures all imported files are in the AI request payload
    func buildComprehensiveContext(baseContext: String?) -> String {
        var comprehensiveContext = baseContext ?? ""
        
        // Add all project files to context if not already included
        guard let projectURL = viewModel.rootFolderURL else {
            return comprehensiveContext
        }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return comprehensiveContext
        }
        
        var projectFiles: [String] = []
        var existingFilePaths = Set<String>()
        
        // Extract existing file paths from context to avoid duplicates
        let contextLines = comprehensiveContext.components(separatedBy: .newlines)
        for line in contextLines {
            if line.hasPrefix("--- ") && line.hasSuffix(" ---") {
                let fileName = String(line.dropFirst(4).dropLast(4)).trimmingCharacters(in: .whitespaces)
                existingFilePaths.insert(fileName)
            }
        }
        
        // Enumerate all project files
        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath else { continue }
            
            let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
            let fileName = fileURL.lastPathComponent
            
            // Skip if already in context
            if existingFilePaths.contains(relativePath) || existingFilePaths.contains(fileName) {
                continue
            }
            
            // Read file content
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  content.count > 0 else {
                continue
            }
            
            // Only include text files (skip binary files)
            let fileExtension = fileURL.pathExtension.lowercased()
            let textExtensions = ["swift", "js", "jsx", "ts", "tsx", "html", "css", "json", "xml", "py", "java", "cpp", "c", "h", "hpp", "go", "rs", "rb", "php", "sh", "md", "txt", "yaml", "yml", "toml", "ini", "conf", "properties"]
            
            guard textExtensions.contains(fileExtension) || fileExtension.isEmpty else {
                continue
            }
            
            projectFiles.append("--- \(relativePath) ---\n\(content)\n")
        }
        
        // Append project files if any
        if !projectFiles.isEmpty {
            comprehensiveContext += "\n\n--- ALL PROJECT FILES ---\n"
            comprehensiveContext += projectFiles.joined(separator: "\n")
            
            // LOGGING: Track context building for debugging
            print("📁 CONTEXT BUILDER:")
            print("   Project files added: \(projectFiles.count)")
            print("   File names: \(projectFiles.prefix(5).map { $0.components(separatedBy: "\n").first?.replacingOccurrences(of: "--- ", with: "").replacingOccurrences(of: " ---", with: "") ?? "" }.joined(separator: ", "))")
        }
        
        return comprehensiveContext
    }
}
