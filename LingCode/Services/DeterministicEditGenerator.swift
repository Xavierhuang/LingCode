//
//  DeterministicEditGenerator.swift
//  LingCode
//
//  Generates deterministic edits for simple string replacements
//  Used for workspace-aware edit expansion
//

import Foundation

/// Generates deterministic edits for simple string replacements
///
/// WHY DETERMINISTIC:
/// - For simple replacements, we don't need AI to enumerate files
/// - IDE generates edits directly from workspace scan results
/// - Ensures all matching files are modified
@MainActor
final class DeterministicEditGenerator {
    static let shared = DeterministicEditGenerator()
    
    private init() {}
    
    /// Generated edit for a file
    struct GeneratedEdit: Equatable {
        let filePath: String // Relative to workspace
        let originalContent: String
        let newContent: String
        let matchCount: Int
    }
    
    /// Generate edits for simple string replacement
    ///
    /// - Parameters:
    ///   - from: String to replace
    ///   - to: Replacement string
    ///   - matchedFiles: Files that contain the target string (from WorkspaceScanner)
    ///   - workspaceURL: Root workspace directory
    ///   - caseSensitive: Whether replacement is case-sensitive (default: false)
    /// - Returns: Array of generated edits
    func generateReplacementEdits(
        from: String,
        to: String,
        matchedFiles: [WorkspaceScanner.FileMatch],
        workspaceURL: URL,
        caseSensitive: Bool = false
    ) -> [GeneratedEdit] {
        var edits: [GeneratedEdit] = []
        
        for match in matchedFiles {
            // Read file content
            guard let originalContent = try? String(contentsOf: match.fileURL, encoding: .utf8) else {
                print("⚠️ DETERMINISTIC EDIT: Failed to read file \(match.fileURL.path)")
                continue
            }
            
            // Perform replacement
            let newContent: String
            if caseSensitive {
                newContent = originalContent.replacingOccurrences(of: from, with: to)
            } else {
                // Case-insensitive replacement (preserve original case in file)
                newContent = performCaseInsensitiveReplacement(
                    in: originalContent,
                    from: from,
                    to: to
                )
            }
            
            // Only create edit if content actually changed
            if newContent != originalContent {
                // Get relative path
                let relativePath = match.fileURL.path.replacingOccurrences(
                    of: workspaceURL.path + "/",
                    with: ""
                )
                
                edits.append(GeneratedEdit(
                    filePath: relativePath,
                    originalContent: originalContent,
                    newContent: newContent,
                    matchCount: match.matchCount
                ))
            }
        }
        
        // Log generation results
        print("🔧 DETERMINISTIC EDIT GENERATION:")
        print("   Replacement: '\(from)' → '\(to)'")
        print("   Files matched: \(matchedFiles.count)")
        print("   Edits generated: \(edits.count)")
        if !edits.isEmpty {
            print("   Generated edits:")
            for edit in edits.prefix(10) {
                print("     - \(edit.filePath) (\(edit.matchCount) replacements)")
            }
            if edits.count > 10 {
                print("     ... and \(edits.count - 10) more")
            }
        }
        
        return edits
    }
    
    // MARK: - Private Implementation
    
    /// Perform case-insensitive replacement while preserving original case
    private func performCaseInsensitiveReplacement(
        in content: String,
        from: String,
        to: String
    ) -> String {
        // Use regex for case-insensitive replacement
        let pattern = NSRegularExpression.escapedPattern(for: from)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            // Fallback to simple replacement if regex fails
            return content.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        
        let range = NSRange(location: 0, length: content.utf16.count)
        let mutableString = NSMutableString(string: content)
        
        // Replace all occurrences
        regex.replaceMatches(in: mutableString, options: [], range: range, withTemplate: to)
        
        return mutableString as String
    }
}
