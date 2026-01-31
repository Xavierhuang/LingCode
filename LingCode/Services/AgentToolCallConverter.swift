//
//  AgentToolCallConverter.swift
//  LingCode
//
//  Converts ToolCall from the AI stream into AgentDecision (extracted from AgentService).
//

import Foundation

enum AgentToolCallConverter {
    static func convert(_ toolCall: ToolCall) -> AgentDecision? {
        let input = toolCall.input

        switch toolCall.name {
        case "done":
            let summary = input["summary"]?.value as? String
            return AgentDecision(action: "done", description: "Task Complete", command: nil, query: nil, filePath: nil, code: nil, thought: summary)

        case "run_terminal_command":
            guard let cmd = input["command"]?.value as? String else { return nil }
            return AgentDecision(action: "terminal", description: "Exec: \(cmd)", command: cmd, query: nil, filePath: nil, code: nil, thought: nil)

        case "write_file":
            let filePath: String? = input["file_path"]?.value as? String ?? input["path"]?.value as? String
            let content = input["content"]?.value as? String
            guard let path = filePath, let fileContent = content else { return nil }
            return AgentDecision(action: "code", description: "Write: \(path)", command: nil, query: nil, filePath: path, code: fileContent, thought: nil)

        case "codebase_search", "search_web":
            guard let q = input["query"]?.value as? String else { return nil }
            return AgentDecision(action: "search", description: "Search: \(q)", command: nil, query: q, filePath: nil, code: nil, thought: nil)

        case "read_file":
            let filePath: String? = input["file_path"]?.value as? String ?? input["path"]?.value as? String
            guard let path = filePath else { return nil }
            return AgentDecision(action: "file", description: "Read: \(path)", command: nil, query: nil, filePath: path, code: nil, thought: nil)

        case "read_directory":
            let path: String? = input["directory_path"]?.value as? String ?? input["path"]?.value as? String ?? input["folder"]?.value as? String
            guard let directoryPath = path else { return nil }
            let recursive = (input["recursive"]?.value as? Bool) ?? false
            return AgentDecision(action: "directory", description: "Read: \(directoryPath)", command: nil, query: nil, filePath: directoryPath, code: nil, thought: recursive ? "recursive" : nil)

        default:
            return nil
        }
    }
}
