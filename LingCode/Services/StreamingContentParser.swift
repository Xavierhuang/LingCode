//
//  StreamingContentParser.swift
//  LingCode
//
//  Service for parsing streaming content and extracting file information
//

import Foundation

class StreamingContentParser {
    static let shared = StreamingContentParser()
    
    private init() {}
    
    func parseContent(
        _ content: String,
        isLoading: Bool,
        projectURL: URL?,
        actions: [AIAction]
    ) -> [StreamingFileInfo] {
        var newFiles: [StreamingFileInfo] = []
        var processedPaths = Set<String>()
        
        // Multiple patterns to catch different formats (including incomplete blocks during streaming)
        let patterns = [
            // Pattern 1: `filename.ext`:\n```lang\ncode\n``` (complete)
            #"`([^`\n]+\.[a-zA-Z0-9]+)`[:\s]*\n```(\w+)?\n([\s\S]*?)```"#,
            // Pattern 2: **filename.ext**:\n```lang\ncode\n``` (complete)
            #"\*\*([^*\n]+\.[a-zA-Z0-9]+)\*\*[:\s]*\n```(\w+)?\n([\s\S]*?)```"#,
            // Pattern 3: ### filename.ext\n```lang\ncode\n``` (complete)
            #"###\s+([^\n]+\.[a-zA-Z0-9]+)\s*\n```(\w+)?\n([\s\S]*?)```"#
        ]
        
        // Patterns for incomplete blocks (streaming)
        let streamingPatterns = [
            // Pattern 1: `filename.ext`:\n```lang\ncode (incomplete - no closing ```)
            #"`([^`\n]+\.[a-zA-Z0-9]+)`[:\s]*\n```(\w+)?\n([\s\S]*?)(?=\n```|$)"#,
            // Pattern 2: **filename.ext**:\n```lang\ncode (incomplete)
            #"\*\*([^*\n]+\.[a-zA-Z0-9]+)\*\*[:\s]*\n```(\w+)?\n([\s\S]*?)(?=\n```|$)"#,
            // Pattern 3: ### filename.ext\n```lang\ncode (incomplete)
            #"###\s+([^\n]+\.[a-zA-Z0-9]+)\s*\n```(\w+)?\n([\s\S]*?)(?=\n```|$)"#
        ]
        
        // First, process complete blocks
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                let matches = regex.matches(in: content, options: [], range: range)
                
                for match in matches where match.numberOfRanges >= 4 {
                    processMatch(
                        match,
                        in: content,
                        isStreaming: false,
                        isLoading: isLoading,
                        projectURL: projectURL,
                        newFiles: &newFiles,
                        processedPaths: &processedPaths
                    )
                }
            }
        }
        
        // Then, process incomplete blocks (for streaming)
        if isLoading {
            for pattern in streamingPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(content.startIndex..<content.endIndex, in: content)
                    let matches = regex.matches(in: content, options: [], range: range)
                    
                    for match in matches where match.numberOfRanges >= 4 {
                        // Only process if not already processed as complete
                        let pathRange = match.range(at: 1)
                        if pathRange.location != NSNotFound,
                           let swiftRange = Range(pathRange, in: content) {
                            let filePath = String(content[swiftRange]).trimmingCharacters(in: .whitespaces)
                            if !processedPaths.contains(filePath) {
                                processMatch(
                                    match,
                                    in: content,
                                    isStreaming: true,
                                    isLoading: isLoading,
                                    projectURL: projectURL,
                                    newFiles: &newFiles,
                                    processedPaths: &processedPaths
                                )
                            }
                        }
                    }
                }
            }
        }
        
        // Also check actions for files
        for action in actions {
            if let path = action.filePath,
               !processedPaths.contains(path),
               let content = action.fileContent ?? action.result {
                processedPaths.insert(path)
                
                // Calculate change summary
                let (summary, added, removed) = calculateChangeSummary(
                    filePath: path,
                    newContent: content,
                    projectURL: projectURL
                )
                
                newFiles.append(StreamingFileInfo(
                    id: path,
                    path: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    language: detectLanguage(from: path),
                    content: content,
                    isStreaming: isLoading && action.status == .executing,
                    changeSummary: summary,
                    addedLines: added,
                    removedLines: removed
                ))
            }
        }
        
        return newFiles
    }
    
    private func processMatch(
        _ match: NSTextCheckingResult,
        in content: String,
        isStreaming: Bool,
        isLoading: Bool,
        projectURL: URL?,
        newFiles: inout [StreamingFileInfo],
        processedPaths: inout Set<String>
    ) {
        // File path
        var filePath: String? = nil
        if match.numberOfRanges > 1 {
            let pathRange = match.range(at: 1)
            if pathRange.location != NSNotFound,
               let swiftRange = Range(pathRange, in: content) {
                filePath = String(content[swiftRange]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Language
        var language = "text"
        if match.numberOfRanges > 2 {
            let langRange = match.range(at: 2)
            if langRange.location != NSNotFound,
               let swiftRange = Range(langRange, in: content) {
                let lang = String(content[swiftRange]).trimmingCharacters(in: .whitespaces)
                if !lang.isEmpty {
                    language = lang
                }
            }
        }
        
        // Code content
        var code = ""
        if match.numberOfRanges > 3 {
            let codeRange = match.range(at: 3)
            if codeRange.location != NSNotFound,
               let swiftRange = Range(codeRange, in: content) {
                code = String(content[swiftRange])
            }
        }
        
        if let path = filePath, !processedPaths.contains(path) {
            processedPaths.insert(path)
            let fileId = path
            
            // Calculate change summary
            let (summary, added, removed) = calculateChangeSummary(
                filePath: path,
                newContent: code,
                projectURL: projectURL
            )
            
            // Update existing or create new
            if let existingIndex = newFiles.firstIndex(where: { $0.id == fileId }) {
                newFiles[existingIndex] = StreamingFileInfo(
                    id: fileId,
                    path: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    language: language,
                    content: code,
                    isStreaming: isStreaming || isLoading,
                    changeSummary: summary,
                    addedLines: added,
                    removedLines: removed
                )
            } else {
                newFiles.append(StreamingFileInfo(
                    id: fileId,
                    path: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    language: language,
                    content: code,
                    isStreaming: isStreaming || isLoading,
                    changeSummary: summary,
                    addedLines: added,
                    removedLines: removed
                ))
            }
        }
    }
    
    func detectLanguage(from path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        default: return "text"
        }
    }
    
    func calculateChangeSummary(filePath: String, newContent: String, projectURL: URL?) -> (summary: String?, added: Int, removed: Int) {
        guard let projectURL = projectURL else {
            return ("New file", newContent.components(separatedBy: .newlines).count, 0)
        }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let newLines = newContent.components(separatedBy: .newlines)
        
        // Check if file exists
        if FileManager.default.fileExists(atPath: fileURL.path),
           let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            // File exists - calculate diff
            let existingLines = existingContent.components(separatedBy: .newlines)
            let added = max(0, newLines.count - existingLines.count)
            let removed = max(0, existingLines.count - newLines.count)
            
            if added > 0 && removed > 0 {
                return ("Modified: +\(added) -\(removed) lines", added, removed)
            } else if added > 0 {
                return ("Added \(added) line\(added == 1 ? "" : "s")", added, removed)
            } else if removed > 0 {
                return ("Removed \(removed) line\(removed == 1 ? "" : "s")", added, removed)
            } else {
                return ("No changes", 0, 0)
            }
        } else {
            // New file
            return ("New file: \(newLines.count) line\(newLines.count == 1 ? "" : "s")", newLines.count, 0)
        }
    }
}

