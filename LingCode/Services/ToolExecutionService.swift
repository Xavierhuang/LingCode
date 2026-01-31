//
//  ToolExecutionService.swift
//  LingCode
//
//  Executes tool calls from AI agent
//  Enables "Composer" mode and multi-file editing
//

import Foundation

/// Represents a tool call from the AI
struct ToolCall: Codable {
    let id: String
    let name: String
    let input: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case input
    }
}

/// Result of executing a tool
struct ToolResult: Codable {
    let toolUseId: String
    let content: String
    let isError: Bool
    
    enum CodingKeys: String, CodingKey {
        case toolUseId = "tool_use_id"
        case content
        case isError
    }
}

/// Service that executes tool calls from AI
@MainActor
class ToolExecutionService {
    static let shared = ToolExecutionService()
    
    private let fileService = FileService.shared
    private let semanticSearch = SemanticSearchService.shared
    private let terminalService = TerminalExecutionService.shared
    private let webSearchService = WebSearchService.shared
    private var projectURL: URL?
    
    private init() {}
    
    /// Set the current project URL for relative path resolution
    func setProjectURL(_ url: URL?) {
        projectURL = url
    }
    
    /// Execute a tool call and return the result
    func executeToolCall(_ toolCall: ToolCall) async throws -> ToolResult {
        switch toolCall.name {
        case "read_file":
            return try await executeReadFile(toolCall)
        case "write_file":
            return try await executeWriteFile(toolCall)
        case "codebase_search":
            return try await executeCodebaseSearch(toolCall)
        case "run_terminal_command":
            return try await executeTerminalCommand(toolCall)
        case "search_web":
            return try await executeWebSearch(toolCall)
        case "read_directory":
            return try await executeReadDirectory(toolCall)
        case "done":
            return try await executeDone(toolCall)
        default:
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Unknown tool: \(toolCall.name)",
                isError: true
            )
        }
    }
    
    // MARK: - Tool Implementations
    
    /// Execute read_file tool
    /// Execute read_file tool with smart directory detection
    private func executeReadFile(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let filePathValue = toolCall.input["file_path"],
              let filePath = filePathValue.value as? String else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'file_path' parameter",
                isError: true
            )
        }
        
        let fileURL = resolveFilePath(filePath)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        // 1. Check if path exists
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: File or directory not found at \(filePath)",
                isError: true
            )
        }
        
        // 2. SMART FIX: If it's a directory, delegate to read_directory logic automatically
        if isDirectory.boolValue {
            // Create a fake tool call to reuse the directory logic
            let dirToolCall = ToolCall(
                id: toolCall.id,
                name: "read_directory",
                input: ["directory_path": AnyCodable(filePath), "recursive": AnyCodable(false)]
            )
            return try await executeReadDirectory(dirToolCall)
        }
        
        // 3. Normal File Reading
        do {
            let content = try fileService.readFile(at: fileURL)
            return ToolResult(
                toolUseId: toolCall.id,
                content: "File content for '\(filePath)':\n```\n\(content)\n```",
                isError: false
            )
        } catch {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error reading file: \(error.localizedDescription)",
                isError: true
            )
        }
    }
    
    /// Execute write_file tool
    private func executeWriteFile(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let filePathValue = toolCall.input["file_path"],
              let filePath = filePathValue.value as? String,
              let contentValue = toolCall.input["content"],
              let content = contentValue.value as? String else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'file_path' or 'content' parameter",
                isError: true
            )
        }
        
        let fileURL = resolveFilePath(filePath)
        
        do {
            // Create directory if needed
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            // FIX: Read original content for change highlighting (if file exists)
            let fileExisted = FileManager.default.fileExists(atPath: fileURL.path)
            let originalContent: String?
            if fileExisted {
                originalContent = try? fileService.readFile(at: fileURL)
            } else {
                originalContent = nil
            }
            
            // Write file
            try fileService.saveFile(content: content, to: fileURL)
            
            // FIX: Notify ComposerView of file write (for multi-file editing UI)
            // Also include original content for change highlighting
            NotificationCenter.default.post(
                name: NSNotification.Name("ToolFileWritten"),
                object: nil,
                userInfo: [
                    "filePath": filePath,
                    "content": content,
                    "fileURL": fileURL,
                    "originalContent": originalContent ?? ""
                ]
            )
            
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Successfully wrote file: \(filePath)",
                isError: false
            )
        } catch {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error writing file: \(error.localizedDescription)",
                isError: true
            )
        }
    }
    
    /// Execute codebase_search tool
    private func executeCodebaseSearch(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let queryValue = toolCall.input["query"],
              let query = queryValue.value as? String,
              let projectURL = projectURL else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'query' parameter or project URL not set",
                isError: true
            )
        }
        
        // Use semantic search
        let results = await semanticSearch.search(query: query, in: projectURL, maxResults: 10)
        
        if results.isEmpty {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "No results found for query: \(query)",
                isError: false
            )
        }
        
        // Format results
        var resultText = "Found \(results.count) results:\n\n"
        for (index, result) in results.enumerated() {
            resultText += "\(index + 1). \(result.filePath):\(result.line)\n"
            resultText += "   \(result.text.prefix(100))\n\n"
        }
        
        return ToolResult(
            toolUseId: toolCall.id,
            content: resultText,
            isError: false
        )
    }
    
    /// Execute run_terminal_command tool
    private func executeTerminalCommand(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let commandValue = toolCall.input["command"],
              let command = commandValue.value as? String else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'command' parameter",
                isError: true
            )
        }
        
        let workingDir: URL? = {
            if let wdValue = toolCall.input["working_directory"],
               let wd = wdValue.value as? String {
                return resolveFilePath(wd)
            }
            return projectURL
        }()
        
        // Execute command synchronously (for tool use)
        let result = terminalService.executeSync(command, workingDirectory: workingDir)
        
        if result.exitCode == 0 {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Command output:\n```\n\(result.output)\n```",
                isError: false
            )
        } else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Command failed (exit code \(result.exitCode)):\n```\n\(result.output)\n```",
                isError: true
            )
        }
    }
    
    /// Execute search_web tool
    private func executeWebSearch(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let queryValue = toolCall.input["query"],
              let query = queryValue.value as? String else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'query' parameter",
                isError: true
            )
        }
        
        let maxResults = (toolCall.input["max_results"]?.value as? Int) ?? 5
        
        return try await withCheckedThrowingContinuation { continuation in
            webSearchService.search(query: query, maxResults: maxResults) { results in
                if results.isEmpty {
                    continuation.resume(returning: ToolResult(
                        toolUseId: toolCall.id,
                        content: "No results found for query: \(query)",
                        isError: false
                    ))
                } else {
                    var resultText = "Found \(results.count) results:\n\n"
                    for (index, result) in results.enumerated() {
                        resultText += "\(index + 1). \(result.title)\n"
                        resultText += "   URL: \(result.url)\n"
                        resultText += "   \(result.snippet)\n\n"
                    }
                    
                    continuation.resume(returning: ToolResult(
                        toolUseId: toolCall.id,
                        content: resultText,
                        isError: false
                    ))
                }
            }
        }
    }
    
    /// Execute read_directory tool
    private func executeReadDirectory(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let dirPathValue = toolCall.input["directory_path"],
              let dirPath = dirPathValue.value as? String else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'directory_path' parameter",
                isError: true
            )
        }
        
        let recursive = (toolCall.input["recursive"]?.value as? Bool) ?? false
        let dirURL = resolveFilePath(dirPath)
        
        guard dirURL.hasDirectoryPath || FileManager.default.fileExists(atPath: dirURL.path) else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Directory not found: \(dirPath)",
                isError: true
            )
        }
        
        do {
            var contents: [String]
            if recursive {
                guard let enumerator = FileManager.default.enumerator(
                    at: dirURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return ToolResult(
                        toolUseId: toolCall.id,
                        content: "Error: Failed to enumerate directory",
                        isError: true
                    )
                }
                
                let maxEntries = 2000
                var count = 0
                var list: [String] = []
                while let url = enumerator.nextObject() as? URL, count < maxEntries {
                    let relativePath = url.path.replacingOccurrences(of: dirURL.path + "/", with: "")
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    list.append(isDir ? "\(relativePath)/" : relativePath)
                    count += 1
                }
                let truncated = count >= maxEntries
                contents = list
                if truncated {
                    // Return partial result so the step completes instead of spinning forever
                    let contentsText = contents.isEmpty
                        ? "Directory is empty"
                        : contents.joined(separator: "\n") + "\n\n(Truncated to first \(maxEntries) entries. Use a subdirectory or non-recursive read for smaller scope.)"
                    return ToolResult(
                        toolUseId: toolCall.id,
                        content: "Directory contents (\(contents.count) items, truncated):\n```\n\(contentsText)\n```",
                        isError: false
                    )
                }
            } else {
                contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
            }
            
            let contentsText = contents.isEmpty
                ? "Directory is empty"
                : contents.joined(separator: "\n")
            
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Directory contents (\(contents.count) items):\n```\n\(contentsText)\n```",
                isError: false
            )
        } catch {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error reading directory: \(error.localizedDescription)",
                isError: true
            )
        }
    }
    
    /// Execute done tool - marks task as complete
    private func executeDone(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let summaryValue = toolCall.input["summary"],
              let summary = summaryValue.value as? String else {
            return ToolResult(
                toolUseId: toolCall.id,
                content: "Error: Missing 'summary' parameter",
                isError: true
            )
        }
        
        return ToolResult(
            toolUseId: toolCall.id,
            content: summary,
            isError: false
        )
    }
    
    // MARK: - Helper Methods
    
    /// Resolve file path (relative or absolute)
    private func resolveFilePath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            // Absolute path
            return URL(fileURLWithPath: path)
        } else if let projectURL = projectURL {
            // Relative path - append to project root
            return projectURL.appendingPathComponent(path)
        } else {
            // Fallback to absolute
            return URL(fileURLWithPath: path)
        }
    }
}
