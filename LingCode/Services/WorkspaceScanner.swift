//
//  WorkspaceScanner.swift
//  LingCode
//
//  Scans workspace files to find matches for simple replacements
//  Used for workspace-aware edit expansion
//

import Foundation
import UniformTypeIdentifiers

/// Scans workspace files to find matches for string replacements
///
/// WHY WORKSPACE SCAN:
/// - Finds ALL files containing target string BEFORE AI call
/// - Ensures global replacements work across entire codebase
/// - Respects text files only (no binaries)
@MainActor
final class WorkspaceScanner {
    static let shared = WorkspaceScanner()
    
    private init() {}
    
    /// File match result
    struct FileMatch: Equatable {
        let fileURL: URL
        let matchCount: Int
        let isTextFile: Bool
    }
    
    /// Scan workspace for files containing target string
    ///
    /// - Parameters:
    ///   - target: String to search for
    ///   - workspaceURL: Root workspace directory
    ///   - caseSensitive: Whether search is case-sensitive (default: false)
    /// - Returns: Array of matching files with match counts
    func scanForMatches(
        target: String,
        in workspaceURL: URL,
        caseSensitive: Bool = false
    ) -> [FileMatch] {
        guard !target.isEmpty else { return [] }
        
        var matches: [FileMatch] = []
        
        // Get file enumerator
        guard let enumerator = FileManager.default.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("⚠️ WORKSPACE SCAN: Failed to create file enumerator for \(workspaceURL.path)")
            return []
        }
        
        let searchTarget = caseSensitive ? target : target.lowercased()
        var filesScanned = 0
        var textFilesScanned = 0
        
        for case let fileURL as URL in enumerator {
            // Skip directories
            guard !fileURL.hasDirectoryPath else { continue }
            
            filesScanned += 1
            
            // Check if file is text-based
            guard isTextFile(fileURL) else { continue }
            
            textFilesScanned += 1
            
            // Read file content
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            
            // Count matches (case-insensitive by default)
            let searchContent = caseSensitive ? content : content.lowercased()
            let matchCount = countOccurrences(of: searchTarget, in: searchContent)
            
            if matchCount > 0 {
                matches.append(FileMatch(
                    fileURL: fileURL,
                    matchCount: matchCount,
                    isTextFile: true
                ))
            }
        }
        
        // Log scan results
        print("📁 WORKSPACE SCAN:")
        print("   Target: '\(target)'")
        print("   Workspace: \(workspaceURL.path)")
        print("   Files scanned: \(filesScanned)")
        print("   Text files scanned: \(textFilesScanned)")
        print("   Files matched: \(matches.count)")
        if !matches.isEmpty {
            print("   Matched files:")
            for match in matches.prefix(10) {
                let relativePath = match.fileURL.path.replacingOccurrences(of: workspaceURL.path + "/", with: "")
                print("     - \(relativePath) (\(match.matchCount) matches)")
            }
            if matches.count > 10 {
                print("     ... and \(matches.count - 10) more")
            }
        }
        
        return matches
    }
    
    // MARK: - Private Implementation
    
    /// Check if file is text-based (not binary)
    private func isTextFile(_ fileURL: URL) -> Bool {
        // Check file extension for known text types
        let textExtensions: Set<String> = [
            "swift", "js", "jsx", "ts", "tsx", "py", "java", "go", "rs", "cpp", "c", "h", "hpp",
            "html", "css", "json", "xml", "yaml", "yml", "md", "txt", "sh", "bash", "zsh",
            "rb", "php", "kt", "scala", "clj", "hs", "ml", "fs", "vb", "cs", "dart", "lua",
            "sql", "r", "m", "mm", "pl", "pm", "tcl", "vim", "el", "lisp", "cl", "scm",
            "rkt", "jl", "ex", "exs", "erl", "hrl", "elm", "purs", "purescript"
        ]
        
        let ext = fileURL.pathExtension.lowercased()
        if textExtensions.contains(ext) {
            return true
        }
        
        // Check content type if available
        if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            // Check if content type indicates text
            if contentType.conforms(to: .text) {
                return true
            }
            // Some text types might not conform to .text, check common ones
            if contentType.identifier.contains("text") || contentType.identifier.contains("source") {
                return true
            }
        }
        
        // Fallback: Try to read as UTF-8 and check if it's valid
        // This is expensive, so we do it last
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            // If we can read it as UTF-8 and it's not too large, consider it text
            if content.count < 10_000_000 { // 10MB limit
                return true
            }
        }
        
        return false
    }
    
    /// Count occurrences of substring in string
    private func countOccurrences(of substring: String, in string: String) -> Int {
        var count = 0
        var searchRange = string.startIndex..<string.endIndex
        
        while let range = string.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<string.endIndex
        }
        
        return count
    }
}
