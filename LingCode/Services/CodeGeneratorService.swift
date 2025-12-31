//
//  CodeGeneratorService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct CodeBlock: Identifiable {
    let id = UUID()
    let language: String?
    let content: String
    let filePath: String?
    let operation: FileOperation.OperationType
}

struct FileOperation: Identifiable {
    let id = UUID()
    let type: OperationType
    let filePath: String
    let content: String?
    let lineRange: (start: Int, end: Int)?
    
    enum OperationType: String {
        case create = "create"
        case update = "update"
        case append = "append"
        case delete = "delete"
    }
}

struct ProjectStructure {
    let name: String
    let description: String
    let files: [ProjectFile]
    let directories: [String]
    
    struct ProjectFile {
        let path: String
        let content: String
        let language: String?
    }
}

class CodeGeneratorService {
    static let shared = CodeGeneratorService()
    
    private init() {}
    
    // MARK: - Multi-file Project Parsing
    
    /// Parse entire project structure from AI response
    func parseProjectStructure(from text: String) -> ProjectStructure? {
        // Look for project structure markers
        let files = parseMultipleFiles(from: text)
        
        guard !files.isEmpty else { return nil }
        
        // Extract project name from context or first file path
        let projectName = extractProjectName(from: text, files: files)
        
        // Extract directories from file paths
        var directories = Set<String>()
        for file in files {
            let pathComponents = file.path.components(separatedBy: "/")
            var currentPath = ""
            for i in 0..<(pathComponents.count - 1) {
                if !pathComponents[i].isEmpty {
                    currentPath += (currentPath.isEmpty ? "" : "/") + pathComponents[i]
                    directories.insert(currentPath)
                }
            }
        }
        
        return ProjectStructure(
            name: projectName,
            description: extractProjectDescription(from: text),
            files: files,
            directories: Array(directories).sorted()
        )
    }
    
    /// Parse multiple files from AI response
    func parseMultipleFiles(from text: String) -> [ProjectStructure.ProjectFile] {
        var files: [ProjectStructure.ProjectFile] = []
        
        // Pattern 1: ```language:path/to/file.ext
        // Pattern 2: ```language file: path/to/file.ext
        // Pattern 3: <!-- file: path/to/file.ext --> ```language
        // Pattern 4: // path/to/file.ext ```language
        // Pattern 5: File: `path/to/file.ext` ```language
        
        let patterns = [
            // Pattern: ```swift:path/to/file.swift or ```python:path/to/file.py
            #"```(\w+):([^\n]+)\n([\s\S]*?)```"#,
            // Pattern: ```swift file: path/to/file.swift
            #"```(\w+)\s+file:\s*([^\n]+)\n([\s\S]*?)```"#,
            // Pattern: <!-- file: path --> ```language
            #"<!--\s*file:\s*([^\n>]+)\s*-->\s*```(\w+)?\n([\s\S]*?)```"#,
            // Pattern: // path/file.ext ```language
            #"//\s*([^\n]+\.\w+)\s*\n```(\w+)?\n([\s\S]*?)```"#,
            // Pattern: **`path/file.ext`** or `path/file.ext`:
            #"`([^`]+\.\w+)`[:\s]*\n*```(\w+)?\n([\s\S]*?)```"#,
            // Pattern: File: path/file.ext
            #"(?:File|Create|Update):\s*`?([^\n`]+\.\w+)`?\s*\n*```(\w+)?\n([\s\S]*?)```"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                
                for match in matches {
                    var filePath: String?
                    var language: String?
                    var content: String = ""
                    
                    // Different patterns have different group orders
                    if pattern.contains("<!--") {
                        // Pattern 3: Group 1 is path, Group 2 is language, Group 3 is content
                        if match.numberOfRanges > 1, let pathRange = Range(match.range(at: 1), in: text) {
                            filePath = String(text[pathRange]).trimmingCharacters(in: .whitespaces)
                        }
                        if match.numberOfRanges > 2, let langRange = Range(match.range(at: 2), in: text) {
                            language = String(text[langRange])
                        }
                        if match.numberOfRanges > 3, let contentRange = Range(match.range(at: 3), in: text) {
                            content = String(text[contentRange])
                        }
                    } else if pattern.hasPrefix("#\"//") || pattern.contains("`([^`]+") || pattern.contains("(?:File") {
                        // Pattern 4, 5, 6: Group 1 is path, Group 2 is language, Group 3 is content
                        if match.numberOfRanges > 1, let pathRange = Range(match.range(at: 1), in: text) {
                            filePath = String(text[pathRange]).trimmingCharacters(in: .whitespaces)
                        }
                        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                           let langRange = Range(match.range(at: 2), in: text) {
                            language = String(text[langRange])
                        }
                        if match.numberOfRanges > 3, let contentRange = Range(match.range(at: 3), in: text) {
                            content = String(text[contentRange])
                        }
                    } else {
                        // Pattern 1, 2: Group 1 is language, Group 2 is path, Group 3 is content
                        if match.numberOfRanges > 1, let langRange = Range(match.range(at: 1), in: text) {
                            language = String(text[langRange])
                        }
                        if match.numberOfRanges > 2, let pathRange = Range(match.range(at: 2), in: text) {
                            filePath = String(text[pathRange]).trimmingCharacters(in: .whitespaces)
                        }
                        if match.numberOfRanges > 3, let contentRange = Range(match.range(at: 3), in: text) {
                            content = String(text[contentRange])
                        }
                    }
                    
                    // Clean up file path
                    if var path = filePath {
                        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "`*"))
                        path = path.replacingOccurrences(of: "\\", with: "/")
                        
                        // Skip if already added
                        if !files.contains(where: { $0.path == path }) {
                            files.append(ProjectStructure.ProjectFile(
                                path: path,
                                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                                language: language
                            ))
                        }
                    }
                }
            }
        }
        
        // Fallback: Try traditional code block parsing with context
        if files.isEmpty {
            files = parseCodeBlocksWithContext(from: text)
        }
        
        return files
    }
    
    /// Parse code blocks with surrounding context for file paths
    private func parseCodeBlocksWithContext(from text: String) -> [ProjectStructure.ProjectFile] {
        var files: [ProjectStructure.ProjectFile] = []
        
        // Standard code block pattern
        let pattern = #"```(\w+)?\n([\s\S]*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return files
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            var language: String?
            var content: String = ""
            
            if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                let languageRange = Range(match.range(at: 1), in: text)!
                language = String(text[languageRange])
            }
            
            if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                let contentRange = Range(match.range(at: 2), in: text)!
                content = String(text[contentRange])
                
                // Check if first line contains file path
                let lines = content.components(separatedBy: .newlines)
                if let firstLine = lines.first {
                    if firstLine.lowercased().hasPrefix("file:") {
                        let filePath = String(firstLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        content = lines.dropFirst().joined(separator: "\n")
                        
                        files.append(ProjectStructure.ProjectFile(
                            path: filePath,
                            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                            language: language
                        ))
                        continue
                    }
                }
            }
            
            // Try to extract file path from surrounding text
            if let filePath = extractFilePath(around: match.range, in: text) {
                files.append(ProjectStructure.ProjectFile(
                    path: filePath,
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    language: language
                ))
            } else if let language = language, !content.isEmpty {
                // Generate a reasonable file name from language
                let inferredPath = inferFileName(from: content, language: language)
                files.append(ProjectStructure.ProjectFile(
                    path: inferredPath,
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    language: language
                ))
            }
        }
        
        return files
    }
    
    // MARK: - Legacy Support
    
    func parseCodeBlocks(from text: String) -> [CodeBlock] {
        let files = parseMultipleFiles(from: text)
        return files.map { file in
            CodeBlock(
                language: file.language,
                content: file.content,
                filePath: file.path,
                operation: .create
            )
        }
    }
    
    func extractFileOperations(from text: String, projectURL: URL?) -> [FileOperation] {
        var operations: [FileOperation] = []
        let files = parseMultipleFiles(from: text)
        
        for file in files {
            let fullPath = resolveFilePath(file.path, projectURL: projectURL)
            let fileExists = FileManager.default.fileExists(atPath: fullPath.path)
            
            operations.append(FileOperation(
                type: fileExists ? .update : .create,
                filePath: fullPath.path,
                content: file.content,
                lineRange: nil
            ))
        }
        
        // Also look for explicit delete operations
        let deleteOps = extractDeleteOperations(from: text, projectURL: projectURL)
        operations.append(contentsOf: deleteOps)
        
        return operations
    }
    
    // MARK: - Helper Methods
    
    private func extractProjectName(from text: String, files: [ProjectStructure.ProjectFile]) -> String {
        // Try to find project name in text
        let patterns = [
            #"project[:\s]+([^\n]+)"#,
            #"create[:\s]+([^\n]+)\s+project"#,
            #"building[:\s]+([^\n]+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   match.numberOfRanges > 1,
                   let nameRange = Range(match.range(at: 1), in: text) {
                    return String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Infer from first file path
        if let firstFile = files.first {
            let components = firstFile.path.components(separatedBy: "/")
            if components.count > 1 {
                return components.first ?? "NewProject"
            }
        }
        
        return "NewProject"
    }
    
    private func extractProjectDescription(from text: String) -> String {
        // Extract first paragraph as description
        let paragraphs = text.components(separatedBy: "\n\n")
        if let first = paragraphs.first {
            let cleaned = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > 10 && cleaned.count < 500 {
                return cleaned
            }
        }
        return ""
    }
    
    private func extractFilePath(around range: NSRange, in text: String) -> String? {
        let searchStart = max(0, range.location - 300)
        let searchEnd = min(text.count, range.location + range.length + 100)
        
        guard searchStart < text.count && searchEnd <= text.count else { return nil }
        
        let startIndex = text.index(text.startIndex, offsetBy: searchStart)
        let endIndex = text.index(text.startIndex, offsetBy: searchEnd)
        let searchText = String(text[startIndex..<endIndex])
        
        // Patterns to match file paths - ordered by specificity
        let patterns = [
            #"`([a-zA-Z0-9_/\\.-]+\.\w{1,5})`"#,  // `path/to/file.ext`
            #"\*\*([a-zA-Z0-9_/\\.-]+\.\w{1,5})\*\*"#,  // **path/to/file.ext**
            #"File:\s*([^\s\n]+\.\w{1,5})"#,
            #"file:\s*([^\s\n]+)"#,
            #"path:\s*([^\s\n]+)"#,
            #"create\s+([^\s\n]+\.\w+)"#,
            #"Create:\s*([^\s\n]+)"#,
            #"([a-zA-Z0-9_][a-zA-Z0-9_/\\.-]*\.(swift|py|js|ts|jsx|tsx|html|css|json|md|yaml|yml|toml|rs|go|java|kt|c|cpp|h|hpp))"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsSearchText = searchText as NSString
                let matches = regex.matches(in: searchText, options: [], range: NSRange(location: 0, length: nsSearchText.length))
                if let match = matches.first, match.numberOfRanges > 1 {
                    let pathRange = Range(match.range(at: 1), in: searchText)!
                    let path = String(searchText[pathRange]).trimmingCharacters(in: CharacterSet(charactersIn: "`*\"'"))
                    if !path.isEmpty && path.contains(".") {
                        return path
                    }
                }
            }
        }
        
        return nil
    }
    
    private func resolveFilePath(_ path: String, projectURL: URL?) -> URL {
        var cleanPath = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "`*\"'"))
            .replacingOccurrences(of: "\\", with: "/")
        
        // Remove leading ./ if present
        if cleanPath.hasPrefix("./") {
            cleanPath = String(cleanPath.dropFirst(2))
        }
        
        // If absolute path
        if cleanPath.hasPrefix("/") {
            return URL(fileURLWithPath: cleanPath)
        }
        
        // If relative path, resolve against project URL
        if let projectURL = projectURL {
            return projectURL.appendingPathComponent(cleanPath)
        }
        
        // Fallback to home directory
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return homeURL.appendingPathComponent("Desktop").appendingPathComponent(cleanPath)
    }
    
    private func inferFileName(from content: String, language: String) -> String {
        let extensions: [String: String] = [
            "swift": "swift",
            "python": "py",
            "javascript": "js",
            "typescript": "ts",
            "jsx": "jsx",
            "tsx": "tsx",
            "html": "html",
            "css": "css",
            "json": "json",
            "markdown": "md",
            "bash": "sh",
            "shell": "sh",
            "go": "go",
            "rust": "rs",
            "java": "java",
            "kotlin": "kt",
            "c": "c",
            "cpp": "cpp",
            "yaml": "yaml",
            "toml": "toml"
        ]
        
        let ext = extensions[language.lowercased()] ?? "txt"
        
        // Try to infer name from content
        let patterns = [
            #"class\s+(\w+)"#,
            #"struct\s+(\w+)"#,
            #"func\s+(\w+)"#,
            #"function\s+(\w+)"#,
            #"def\s+(\w+)"#,
            #"const\s+(\w+)"#,
            #"export\s+(?:default\s+)?(?:class|function|const)\s+(\w+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                if let match = regex.firstMatch(in: content, options: [], range: range),
                   match.numberOfRanges > 1,
                   let nameRange = Range(match.range(at: 1), in: content) {
                    let name = String(content[nameRange])
                    return "\(name).\(ext)"
                }
            }
        }
        
        return "main.\(ext)"
    }
    
    private func extractDeleteOperations(from text: String, projectURL: URL?) -> [FileOperation] {
        var operations: [FileOperation] = []
        
        let patterns = [
            #"delete\s+(?:file\s+)?`?([^\s\n`]+)`?"#,
            #"remove\s+(?:file\s+)?`?([^\s\n`]+)`?"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                
                for match in matches where match.numberOfRanges > 1 {
                    if let pathRange = Range(match.range(at: 1), in: text) {
                        let path = String(text[pathRange])
                        let fullPath = resolveFilePath(path, projectURL: projectURL)
                        
                        operations.append(FileOperation(
                            type: .delete,
                            filePath: fullPath.path,
                            content: nil,
                            lineRange: nil
                        ))
                    }
                }
            }
        }
        
        return operations
    }
}
