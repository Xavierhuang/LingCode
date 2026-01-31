//
//  ToolExecutionService.swift
//  LingCode
//
//  Router for tool execution: routes ToolCall to FileService or TerminalExecutionService.
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

/// Routes tool calls to FileService or TerminalExecutionService.
@MainActor
class ToolExecutionService {
    static let shared = ToolExecutionService()
    
    private let fileService = FileService.shared
    private let terminalService = TerminalExecutionService.shared
    private let semanticSearch = SemanticSearchService.shared
    private let webSearchService = WebSearchService.shared
    private var projectURL: URL?
    
    private init() {}
    
    func setProjectURL(_ url: URL?) {
        projectURL = url
    }
    
    /// Route a tool call to FileService or TerminalExecutionService (or minimal other handlers).
    func executeToolCall(_ toolCall: ToolCall) async throws -> ToolResult {
        switch toolCall.name {
        case "read_file", "write_file", "read_directory":
            return try await routeToFile(toolCall)
        case "run_terminal_command":
            return try await routeToTerminal(toolCall)
        case "codebase_search":
            return try await executeCodebaseSearch(toolCall)
        case "search_web":
            return try await executeWebSearch(toolCall)
        case "done":
            return try await executeDone(toolCall)
        default:
            return ToolResult(toolUseId: toolCall.id, content: "Unknown tool: \(toolCall.name)", isError: true)
        }
    }
    
    // MARK: - Route to FileService
    
    private func routeToFile(_ toolCall: ToolCall) async throws -> ToolResult {
        switch toolCall.name {
        case "read_file":
            return try await executeReadFile(toolCall)
        case "write_file":
            return try await executeWriteFile(toolCall)
        case "read_directory":
            return try await executeReadDirectory(toolCall)
        default:
            return ToolResult(toolUseId: toolCall.id, content: "Unknown file tool: \(toolCall.name)", isError: true)
        }
    }
    
    private func executeReadFile(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let filePathValue = toolCall.input["file_path"],
              let filePath = filePathValue.value as? String else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Missing 'file_path' parameter", isError: true)
        }
        let fileURL = resolveFilePath(filePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: File or directory not found at \(filePath)", isError: true)
        }
        if isDirectory.boolValue {
            let dirToolCall = ToolCall(id: toolCall.id, name: "read_directory", input: ["directory_path": AnyCodable(filePath), "recursive": AnyCodable(false)])
            return try await executeReadDirectory(dirToolCall)
        }
        do {
            let content = try fileService.readFile(at: fileURL)
            return ToolResult(toolUseId: toolCall.id, content: "File content for '\(filePath)':\n```\n\(content)\n```", isError: false)
        } catch {
            return ToolResult(toolUseId: toolCall.id, content: "Error reading file: \(error.localizedDescription)", isError: true)
        }
    }
    
    private func executeWriteFile(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let filePathValue = toolCall.input["file_path"],
              let filePath = filePathValue.value as? String,
              let contentValue = toolCall.input["content"],
              let content = contentValue.value as? String else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Missing 'file_path' or 'content' parameter", isError: true)
        }
        let fileURL = resolveFilePath(filePath)
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let originalContent: String? = FileManager.default.fileExists(atPath: fileURL.path) ? (try? fileService.readFile(at: fileURL)) : nil
            try fileService.saveFile(content: content, to: fileURL)
            NotificationCenter.default.post(
                name: NSNotification.Name("ToolFileWritten"),
                object: nil,
                userInfo: ["filePath": filePath, "content": content, "fileURL": fileURL, "originalContent": originalContent ?? ""]
            )
            return ToolResult(toolUseId: toolCall.id, content: "Successfully wrote file: \(filePath)", isError: false)
        } catch {
            return ToolResult(toolUseId: toolCall.id, content: "Error writing file: \(error.localizedDescription)", isError: true)
        }
    }
    
    private func executeReadDirectory(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let dirPathValue = toolCall.input["directory_path"],
              let dirPath = dirPathValue.value as? String else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Missing 'directory_path' parameter", isError: true)
        }
        let dirURL = resolveFilePath(dirPath)
        let recursive = (toolCall.input["recursive"]?.value as? Bool) ?? false
        guard dirURL.hasDirectoryPath || FileManager.default.fileExists(atPath: dirURL.path) else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Directory not found: \(dirPath)", isError: true)
        }
        do {
            var contents: [String]
            if recursive {
                guard let enumerator = FileManager.default.enumerator(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .nameKey], options: [.skipsHiddenFiles]) else {
                    return ToolResult(toolUseId: toolCall.id, content: "Error: Failed to enumerate directory", isError: true)
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
                contents = list
                if count >= maxEntries {
                    let contentsText = contents.isEmpty ? "Directory is empty" : contents.joined(separator: "\n") + "\n\n(Truncated to first \(maxEntries) entries.)"
                    return ToolResult(toolUseId: toolCall.id, content: "Directory contents (\(contents.count) items, truncated):\n```\n\(contentsText)\n```", isError: false)
                }
            } else {
                contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
            }
            let contentsText = contents.isEmpty ? "Directory is empty" : contents.joined(separator: "\n")
            return ToolResult(toolUseId: toolCall.id, content: "Directory contents (\(contents.count) items):\n```\n\(contentsText)\n```", isError: false)
        } catch {
            return ToolResult(toolUseId: toolCall.id, content: "Error reading directory: \(error.localizedDescription)", isError: true)
        }
    }
    
    // MARK: - Route to TerminalExecutionService
    
    private func routeToTerminal(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let commandValue = toolCall.input["command"],
              let command = commandValue.value as? String else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Missing 'command' parameter", isError: true)
        }
        let workingDir: URL? = {
            if let wdValue = toolCall.input["working_directory"], let wd = wdValue.value as? String {
                return resolveFilePath(wd)
            }
            return projectURL
        }()
        let result = terminalService.executeSync(command, workingDirectory: workingDir)
        if result.exitCode == 0 {
            return ToolResult(toolUseId: toolCall.id, content: "Command output:\n```\n\(result.output)\n```", isError: false)
        }
        return ToolResult(toolUseId: toolCall.id, content: "Command failed (exit code \(result.exitCode)):\n```\n\(result.output)\n```", isError: true)
    }
    
    // MARK: - Other (minimal delegation)
    
    private func executeCodebaseSearch(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let queryValue = toolCall.input["query"],
              let query = queryValue.value as? String,
              let projectURL = projectURL else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Missing 'query' parameter or project URL not set", isError: true)
        }
        let results = await semanticSearch.search(query: query, in: projectURL, maxResults: 10)
        if results.isEmpty {
            return ToolResult(toolUseId: toolCall.id, content: "No results found for query: \(query)", isError: false)
        }
        var resultText = "Found \(results.count) results:\n\n"
        for (index, result) in results.enumerated() {
            resultText += "\(index + 1). \(result.filePath):\(result.line)\n   \(result.text.prefix(100))\n\n"
        }
        return ToolResult(toolUseId: toolCall.id, content: resultText, isError: false)
    }
    
    private func executeWebSearch(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let queryValue = toolCall.input["query"],
              let query = queryValue.value as? String else {
            return ToolResult(toolUseId: toolCall.id, content: "Error: Missing 'query' parameter", isError: true)
        }
        let maxResults = (toolCall.input["max_results"]?.value as? Int) ?? 5
        return try await withCheckedThrowingContinuation { continuation in
            webSearchService.search(query: query, maxResults: maxResults) { results in
                if results.isEmpty {
                    continuation.resume(returning: ToolResult(toolUseId: toolCall.id, content: "No results found for query: \(query)", isError: false))
                } else {
                    var resultText = "Found \(results.count) results:\n\n"
                    for (index, result) in results.enumerated() {
                        resultText += "\(index + 1). \(result.title)\n   URL: \(result.url)\n   \(result.snippet)\n\n"
                    }
                    continuation.resume(returning: ToolResult(toolUseId: toolCall.id, content: resultText, isError: false))
                }
            }
        }
    }
    
    private func executeDone(_ toolCall: ToolCall) async throws -> ToolResult {
        let summary = (toolCall.input["summary"]?.value as? String) ?? ""
        return ToolResult(toolUseId: toolCall.id, content: summary, isError: false)
    }
    
    private func resolveFilePath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if let projectURL = projectURL {
            return projectURL.appendingPathComponent(path)
        }
        return URL(fileURLWithPath: path)
    }
}
