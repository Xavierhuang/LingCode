//
//  AITool.swift
//  LingCode
//
//  Tool definitions for AI agent capabilities
//  Enables "Composer" mode and multi-file editing
//

import Foundation

/// Represents a tool that the AI can call
/// FIX: Essential for Agentic features (multi-file editing, codebase search)
public struct AITool: Codable {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
    
    public init(name: String, description: String, inputSchema: [String: AnyCodable]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Helper to encode/decode [String: Any] as JSON
public struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

/// Predefined tools for common operations
extension AITool {
    /// Tool for searching the codebase
    static func codebaseSearch() -> AITool {
        return AITool(
            name: "codebase_search",
            description: "Search the codebase for files, functions, or patterns",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "query": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("Search query (file path, function name, or pattern)")
                    ])
                ]),
                "required": AnyCodable(["query"])
            ]
        )
    }
    
    /// Tool for reading file contents
    static func readFile() -> AITool {
        return AITool(
            name: "read_file",
            description: "Read the contents of a file",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "file_path": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("Path to the file to read")
                    ])
                ]),
                "required": AnyCodable(["file_path"])
            ]
        )
    }
    
    /// Tool for writing/editing files
    static func writeFile() -> AITool {
        return AITool(
            name: "write_file",
            description: "Write or edit a file",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "file_path": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("Path to the file to write")
                    ]),
                    "content": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("File content to write")
                    ])
                ]),
                "required": AnyCodable(["file_path", "content"])
            ]
        )
    }
    
    /// Tool for running terminal commands
    static func runTerminalCommand() -> AITool {
        return AITool(
            name: "run_terminal_command",
            description: "Execute a terminal/shell command and return the output",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "command": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("The shell command to execute")
                    ]),
                    "working_directory": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("Optional: Working directory for the command (defaults to project root)")
                    ])
                ]),
                "required": AnyCodable(["command"])
            ]
        )
    }
    
    /// Tool for searching the web
    static func searchWeb() -> AITool {
        return AITool(
            name: "search_web",
            description: "Search the web for information",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "query": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("Search query")
                    ]),
                    "max_results": AnyCodable([
                        "type": AnyCodable("integer"),
                        "description": AnyCodable("Maximum number of results (default: 5)")
                    ])
                ]),
                "required": AnyCodable(["query"])
            ]
        )
    }
    
    /// Tool for reading directory contents
    static func readDirectory() -> AITool {
        return AITool(
            name: "read_directory",
            description: "List files and directories in a path",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "directory_path": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("Path to the directory to read")
                    ]),
                    "recursive": AnyCodable([
                        "type": AnyCodable("boolean"),
                        "description": AnyCodable("Whether to list recursively (default: false)")
                    ])
                ]),
                "required": AnyCodable(["directory_path"])
            ]
        )
    }
    
    /// Tool for marking task as complete and generating a summary
    static func done() -> AITool {
        return AITool(
            name: "done",
            description: "Mark the task as complete and generate a summary of what was accomplished",
            inputSchema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "summary": AnyCodable([
                        "type": AnyCodable("string"),
                        "description": AnyCodable("A summary of what was accomplished, including files created/modified, key changes, and any important notes")
                    ])
                ]),
                "required": AnyCodable(["summary"])
            ]
        )
    }
}
