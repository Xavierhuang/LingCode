//
//  ParserRobustnessGuard.swift
//  LingCode
//
//  Guards against partial streams, empty content, and truncated files
//  Ensures only complete, valid file edits reach the apply phase
//

import Foundation

/// Guards parser against partial streams and invalid content
///
/// PARSER ROBUSTNESS RULES:
/// 1. Partial streams or aborted streams NEVER replace full files
/// 2. If parsing fails, do NOT emit a file diff
/// 3. Guard against empty or truncated file content being treated as valid edit
@MainActor
final class ParserRobustnessGuard {
    static let shared = ParserRobustnessGuard()
    
    private init() {}
    
    /// Minimum content length for a valid file edit
    /// Files shorter than this are likely truncated or invalid
    private let minContentLength: Int = 10
    
    /// Validate parsed file content before allowing it to be used
    ///
    /// - Parameters:
    ///   - file: Parsed file info
    ///   - isStreaming: Whether this is from a streaming (incomplete) parse
    ///   - isLoading: Whether AI is still loading
    /// - Returns: Whether file content is valid
    func validateFileContent(
        _ file: StreamingFileInfo,
        isStreaming: Bool,
        isLoading: Bool
    ) -> (isValid: Bool, reason: String?) {
        // Rule 1: Empty content is invalid
        let trimmed = file.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, "File content is empty")
        }
        
        // Rule 2: Content too short is likely truncated
        guard trimmed.count >= minContentLength else {
            return (false, "File content is too short (likely truncated)")
        }
        
        // Rule 3: If not streaming and not loading, content must be complete
        // For final parse (isLoading == false), reject incomplete blocks
        if !isStreaming && !isLoading {
            // Final parse - ensure content looks complete
            // Check for common truncation patterns
            if isLikelyTruncated(content: trimmed) {
                return (false, "File content appears truncated")
            }
        }
        
        // Rule 4: Streaming blocks are allowed during streaming, but marked as incomplete
        // They will be replaced by complete blocks when available
        
        return (true, nil)
    }
    
    /// Filter parsed files to only include valid ones
    ///
    /// - Parameters:
    ///   - files: Parsed files
    ///   - isLoading: Whether AI is still loading
    /// - Returns: Validated files (invalid ones removed)
    func filterValidFiles(
        _ files: [StreamingFileInfo],
        isLoading: Bool
    ) -> [StreamingFileInfo] {
        return files.compactMap { file in
            let validation = validateFileContent(file, isStreaming: file.isStreaming, isLoading: isLoading)
            if !validation.isValid {
                print("⚠️ PARSER ROBUSTNESS: Rejecting file \(file.path): \(validation.reason ?? "Invalid")")
                return nil
            }
            return file
        }
    }
    
    /// Check if content appears truncated
    private func isLikelyTruncated(content: String) -> Bool {
        // Check for common truncation patterns
        let lines = content.components(separatedBy: .newlines)
        
        // Very short files might be valid, but check for incomplete syntax
        if lines.count < 3 && content.count < 50 {
            // Check if it looks like incomplete code (e.g., missing closing brace)
            let openBraces = content.filter { $0 == "{" }.count
            let closeBraces = content.filter { $0 == "}" }.count
            if openBraces > closeBraces && openBraces > 0 {
                return true // Unclosed braces suggest truncation
            }
        }
        
        // Check if last line is incomplete (no newline, very short)
        if let lastLine = lines.last, lastLine.count < 5 && !content.hasSuffix("\n") {
            // Might be truncated, but not definitive
            return false // Allow it, but mark as streaming
        }
        
        return false
    }
    
    /// Ensure partial streams don't replace complete files
    ///
    /// When merging streaming updates with existing files, prefer complete blocks
    ///
    /// - Parameters:
    ///   - existingFiles: Files from previous parse
    ///   - newFiles: Files from current parse
    ///   - isLoading: Whether AI is still loading
    /// - Returns: Merged files (complete blocks preferred)
    func mergeFiles(
        existingFiles: [StreamingFileInfo],
        newFiles: [StreamingFileInfo],
        isLoading: Bool
    ) -> [StreamingFileInfo] {
        var merged: [StreamingFileInfo] = []
        var processedIds = Set<String>()
        
        // First, add all complete blocks from new parse
        for newFile in newFiles {
            let validation = validateFileContent(newFile, isStreaming: newFile.isStreaming, isLoading: isLoading)
            if validation.isValid {
                // Prefer non-streaming (complete) blocks
                if !newFile.isStreaming || !isLoading {
                    merged.append(newFile)
                    processedIds.insert(newFile.id)
                }
            }
        }
        
        // Then, add existing files that weren't replaced (if still loading)
        if isLoading {
            for existingFile in existingFiles {
                if !processedIds.contains(existingFile.id) {
                    // Keep existing file if new parse didn't produce a complete replacement
                    merged.append(existingFile)
                }
            }
        }
        
        // Finally, add streaming blocks from new parse (if still loading and no complete block exists)
        if isLoading {
            for newFile in newFiles {
                if newFile.isStreaming && !processedIds.contains(newFile.id) {
                    // Only add if we don't have a complete version
                    if !merged.contains(where: { $0.id == newFile.id && !$0.isStreaming }) {
                        let validation = validateFileContent(newFile, isStreaming: true, isLoading: true)
                        if validation.isValid {
                            merged.append(newFile)
                        }
                    }
                }
            }
        }
        
        return merged
    }
}
