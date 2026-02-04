//
//  MCPService.swift
//  LingCode
//
//  Model Context Protocol (MCP) implementation for connecting external tools
//  https://modelcontextprotocol.io/
//

import Foundation
import Combine

// MARK: - MCP Protocol Types

/// MCP Server configuration
struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]?
    var isEnabled: Bool
    
    init(name: String, command: String, args: [String] = [], env: [String: String]? = nil, isEnabled: Bool = true) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.isEnabled = isEnabled
    }
}

/// MCP Tool definition from server
struct MCPTool: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String
    let inputSchema: MCPToolSchema
    let serverName: String
}

/// JSON Schema for tool input
struct MCPToolSchema: Codable, Equatable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}

struct MCPPropertySchema: Codable, Equatable {
    let type: String
    let description: String?
    let enumValues: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

/// MCP Resource definition
struct MCPResource: Codable, Identifiable, Equatable {
    var id: String { uri }
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?
    let serverName: String
}

/// MCP Prompt template
struct MCPPrompt: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String?
    let arguments: [MCPPromptArgument]?
    let serverName: String
}

struct MCPPromptArgument: Codable, Equatable {
    let name: String
    let description: String?
    let required: Bool?
}

/// MCP JSON-RPC message types
struct MCPRequest: Codable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [String: MCPAnyCodable]?
    
    init(id: Int, method: String, params: [String: MCPAnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct MCPResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: MCPAnyCodable?
    let error: MCPError?
}

struct MCPError: Codable, Error {
    let code: Int
    let message: String
    let data: MCPAnyCodable?
}

/// Type-erased Codable wrapper for MCP
struct MCPAnyCodable: Codable, Equatable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([MCPAnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: MCPAnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { MCPAnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { MCPAnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unable to encode value"))
        }
    }
    
    static func == (lhs: MCPAnyCodable, rhs: MCPAnyCodable) -> Bool {
        // Simple equality check for common types
        switch (lhs.value, rhs.value) {
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        case (is NSNull, is NSNull): return true
        default: return false
        }
    }
}

// MARK: - MCP Server Connection

/// Manages a single MCP server connection
class MCPServerConnection: ObservableObject {
    let config: MCPServerConfig
    
    @Published var isConnected: Bool = false
    @Published var tools: [MCPTool] = []
    @Published var resources: [MCPResource] = []
    @Published var prompts: [MCPPrompt] = []
    @Published var lastError: String?
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var requestId: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var outputBuffer = Data()
    
    init(config: MCPServerConfig) {
        self.config = config
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard !isConnected else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.args
        
        // Set environment
        var env = ProcessInfo.processInfo.environment
        if let customEnv = config.env {
            for (key, value) in customEnv {
                env[key] = value
            }
        }
        process.environment = env
        
        // Setup pipes for JSON-RPC communication
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        
        // Handle output asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutput(data)
        }
        
        do {
            try process.run()
            
            // Initialize connection
            let initResponse = try await sendRequest(method: "initialize", params: [
                "protocolVersion": MCPAnyCodable("2024-11-05"),
                "capabilities": MCPAnyCodable([
                    "roots": ["listChanged": true],
                    "sampling": [:]
                ] as [String: Any]),
                "clientInfo": MCPAnyCodable([
                    "name": "LingCode",
                    "version": "1.0.0"
                ] as [String: Any])
            ])
            
            guard initResponse.error == nil else {
                throw MCPError(code: -1, message: initResponse.error?.message ?? "Init failed", data: nil)
            }
            
            // Send initialized notification
            try await sendNotification(method: "notifications/initialized")
            
            await MainActor.run {
                self.isConnected = true
            }
            
            // Fetch available tools, resources, prompts
            await refreshCapabilities()
            
        } catch {
            disconnect()
            throw error
        }
    }
    
    func disconnect() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        
        Task { @MainActor in
            isConnected = false
            tools = []
            resources = []
            prompts = []
        }
    }
    
    // MARK: - Capabilities
    
    func refreshCapabilities() async {
        // Fetch tools
        if let response = try? await sendRequest(method: "tools/list"),
           let result = response.result?.value as? [String: Any],
           let toolsArray = result["tools"] as? [[String: Any]] {
            let parsedTools = toolsArray.compactMap { dict -> MCPTool? in
                guard let name = dict["name"] as? String,
                      let description = dict["description"] as? String,
                      let schema = dict["inputSchema"] as? [String: Any] else { return nil }
                
                let inputSchema = parseSchema(schema)
                return MCPTool(name: name, description: description, inputSchema: inputSchema, serverName: config.name)
            }
            await MainActor.run {
                self.tools = parsedTools
            }
        }
        
        // Fetch resources
        if let response = try? await sendRequest(method: "resources/list"),
           let result = response.result?.value as? [String: Any],
           let resourcesArray = result["resources"] as? [[String: Any]] {
            let parsedResources = resourcesArray.compactMap { dict -> MCPResource? in
                guard let uri = dict["uri"] as? String,
                      let name = dict["name"] as? String else { return nil }
                return MCPResource(
                    uri: uri,
                    name: name,
                    description: dict["description"] as? String,
                    mimeType: dict["mimeType"] as? String,
                    serverName: config.name
                )
            }
            await MainActor.run {
                self.resources = parsedResources
            }
        }
        
        // Fetch prompts
        if let response = try? await sendRequest(method: "prompts/list"),
           let result = response.result?.value as? [String: Any],
           let promptsArray = result["prompts"] as? [[String: Any]] {
            let parsedPrompts = promptsArray.compactMap { dict -> MCPPrompt? in
                guard let name = dict["name"] as? String else { return nil }
                return MCPPrompt(
                    name: name,
                    description: dict["description"] as? String,
                    arguments: nil,
                    serverName: config.name
                )
            }
            await MainActor.run {
                self.prompts = parsedPrompts
            }
        }
    }
    
    private func parseSchema(_ dict: [String: Any]) -> MCPToolSchema {
        let type = dict["type"] as? String ?? "object"
        var properties: [String: MCPPropertySchema]?
        
        if let props = dict["properties"] as? [String: [String: Any]] {
            properties = props.mapValues { propDict in
                MCPPropertySchema(
                    type: propDict["type"] as? String ?? "string",
                    description: propDict["description"] as? String,
                    enumValues: propDict["enum"] as? [String]
                )
            }
        }
        
        return MCPToolSchema(
            type: type,
            properties: properties,
            required: dict["required"] as? [String]
        )
    }
    
    // MARK: - Tool Execution
    
    func callTool(name: String, arguments: [String: Any]) async throws -> Any {
        let response = try await sendRequest(method: "tools/call", params: [
            "name": MCPAnyCodable(name),
            "arguments": MCPAnyCodable(arguments)
        ])
        
        if let error = response.error {
            throw error
        }
        
        return response.result?.value ?? [:]
    }
    
    // MARK: - Resource Access
    
    func readResource(uri: String) async throws -> String {
        let response = try await sendRequest(method: "resources/read", params: [
            "uri": MCPAnyCodable(uri)
        ])
        
        if let error = response.error {
            throw error
        }
        
        if let result = response.result?.value as? [String: Any],
           let contents = result["contents"] as? [[String: Any]],
           let first = contents.first,
           let text = first["text"] as? String {
            return text
        }
        
        return ""
    }
    
    // MARK: - Prompt Execution
    
    func getPrompt(name: String, arguments: [String: String]? = nil) async throws -> String {
        var params: [String: MCPAnyCodable] = ["name": MCPAnyCodable(name)]
        if let args = arguments {
            params["arguments"] = MCPAnyCodable(args)
        }
        
        let response = try await sendRequest(method: "prompts/get", params: params)
        
        if let error = response.error {
            throw error
        }
        
        if let result = response.result?.value as? [String: Any],
           let messages = result["messages"] as? [[String: Any]] {
            return messages.compactMap { msg -> String? in
                if let content = msg["content"] as? [String: Any],
                   let text = content["text"] as? String {
                    return text
                }
                return nil
            }.joined(separator: "\n")
        }
        
        return ""
    }
    
    // MARK: - JSON-RPC Communication
    
    private func sendRequest(method: String, params: [String: MCPAnyCodable]? = nil) async throws -> MCPResponse {
        requestId += 1
        let id = requestId
        
        let request = MCPRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        
        guard let inputPipe = inputPipe else {
            throw MCPError(code: -1, message: "Not connected", data: nil)
        }
        
        // Write request
        var message = data
        message.append(contentsOf: "\n".utf8)
        inputPipe.fileHandleForWriting.write(message)
        
        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            
            // Timeout after 30 seconds
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = pendingRequests.removeValue(forKey: id) {
                    cont.resume(throwing: MCPError(code: -1, message: "Request timeout", data: nil))
                }
            }
        }
    }
    
    private func sendNotification(method: String, params: [String: MCPAnyCodable]? = nil) async throws {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params?.mapValues { $0.value } ?? [:]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: notification)
        
        guard let inputPipe = inputPipe else {
            throw MCPError(code: -1, message: "Not connected", data: nil)
        }
        
        var message = data
        message.append(contentsOf: "\n".utf8)
        inputPipe.fileHandleForWriting.write(message)
    }
    
    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)
        
        // Process complete messages (newline-delimited JSON)
        while let newlineIndex = outputBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let messageData = outputBuffer[..<newlineIndex]
            outputBuffer = Data(outputBuffer[outputBuffer.index(after: newlineIndex)...])
            
            guard !messageData.isEmpty else { continue }
            
            do {
                let response = try JSONDecoder().decode(MCPResponse.self, from: messageData)
                if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                    continuation.resume(returning: response)
                }
            } catch {
                print("MCP: Failed to parse response: \(error)")
            }
        }
    }
}

// MARK: - MCP Service (Main Manager)

/// Main MCP service that manages all server connections
class MCPService: ObservableObject {
    static let shared = MCPService()
    
    @Published var servers: [MCPServerConfig] = []
    @Published var connections: [String: MCPServerConnection] = [:]
    @Published var allTools: [MCPTool] = []
    @Published var allResources: [MCPResource] = []
    @Published var allPrompts: [MCPPrompt] = []
    
    private let configURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Store config in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        configURL = lingcodeDir.appendingPathComponent("mcp_servers.json")
        
        loadServers()
    }
    
    // MARK: - Server Management
    
    func addServer(_ config: MCPServerConfig) {
        servers.append(config)
        saveServers()
        
        if config.isEnabled {
            Task {
                await connectServer(config.name)
            }
        }
    }
    
    func removeServer(_ name: String) {
        disconnectServer(name)
        servers.removeAll { $0.name == name }
        saveServers()
    }
    
    func updateServer(_ config: MCPServerConfig) {
        if let index = servers.firstIndex(where: { $0.name == config.name }) {
            let wasEnabled = servers[index].isEnabled
            servers[index] = config
            saveServers()
            
            if wasEnabled && !config.isEnabled {
                disconnectServer(config.name)
            } else if !wasEnabled && config.isEnabled {
                Task {
                    await connectServer(config.name)
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    func connectServer(_ name: String) async {
        guard let config = servers.first(where: { $0.name == name && $0.isEnabled }) else { return }
        
        let connection = MCPServerConnection(config: config)
        connections[name] = connection
        
        // Observe connection changes
        connection.$tools
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAllCapabilities() }
            .store(in: &cancellables)
        
        connection.$resources
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAllCapabilities() }
            .store(in: &cancellables)
        
        connection.$prompts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAllCapabilities() }
            .store(in: &cancellables)
        
        do {
            try await connection.connect()
            print("MCP: Connected to \(name)")
        } catch {
            print("MCP: Failed to connect to \(name): \(error)")
            await MainActor.run {
                connection.lastError = error.localizedDescription
            }
        }
    }
    
    func disconnectServer(_ name: String) {
        connections[name]?.disconnect()
        connections.removeValue(forKey: name)
        updateAllCapabilities()
    }
    
    func connectAllEnabled() async {
        for server in servers where server.isEnabled {
            await connectServer(server.name)
        }
    }
    
    func disconnectAll() {
        for (name, _) in connections {
            disconnectServer(name)
        }
    }
    
    // MARK: - Tool Execution
    
    func callTool(serverName: String, toolName: String, arguments: [String: Any]) async throws -> Any {
        guard let connection = connections[serverName], connection.isConnected else {
            throw MCPError(code: -1, message: "Server \(serverName) not connected", data: nil)
        }
        
        return try await connection.callTool(name: toolName, arguments: arguments)
    }
    
    func callTool(_ tool: MCPTool, arguments: [String: Any]) async throws -> Any {
        return try await callTool(serverName: tool.serverName, toolName: tool.name, arguments: arguments)
    }
    
    // MARK: - Resource Access
    
    func readResource(_ resource: MCPResource) async throws -> String {
        guard let connection = connections[resource.serverName], connection.isConnected else {
            throw MCPError(code: -1, message: "Server \(resource.serverName) not connected", data: nil)
        }
        
        return try await connection.readResource(uri: resource.uri)
    }
    
    // MARK: - Prompt Execution
    
    func getPrompt(_ prompt: MCPPrompt, arguments: [String: String]? = nil) async throws -> String {
        guard let connection = connections[prompt.serverName], connection.isConnected else {
            throw MCPError(code: -1, message: "Server \(prompt.serverName) not connected", data: nil)
        }
        
        return try await connection.getPrompt(name: prompt.name, arguments: arguments)
    }
    
    // MARK: - Persistence
    
    private func loadServers() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            // Load default servers
            loadDefaultServers()
            return
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            servers = try JSONDecoder().decode([MCPServerConfig].self, from: data)
        } catch {
            print("MCP: Failed to load servers: \(error)")
            loadDefaultServers()
        }
    }
    
    private func saveServers() {
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: configURL)
        } catch {
            print("MCP: Failed to save servers: \(error)")
        }
    }
    
    private func loadDefaultServers() {
        // Add some common MCP servers as examples (disabled by default)
        servers = [
            MCPServerConfig(
                name: "filesystem",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", NSHomeDirectory()],
                isEnabled: false
            ),
            MCPServerConfig(
                name: "github",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                env: ["GITHUB_PERSONAL_ACCESS_TOKEN": ""],
                isEnabled: false
            ),
            MCPServerConfig(
                name: "postgres",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-postgres"],
                env: ["DATABASE_URL": ""],
                isEnabled: false
            ),
            MCPServerConfig(
                name: "sqlite",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", ""],
                isEnabled: false
            )
        ]
        saveServers()
    }
    
    private func updateAllCapabilities() {
        allTools = connections.values.flatMap { $0.tools }
        allResources = connections.values.flatMap { $0.resources }
        allPrompts = connections.values.flatMap { $0.prompts }
    }
    
    // MARK: - Tool Schema for AI
    
    /// Generate tool definitions for AI system prompt
    func generateToolDefinitions() -> String {
        guard !allTools.isEmpty else { return "" }
        
        var result = "## Available MCP Tools\n\n"
        
        for tool in allTools {
            result += "### \(tool.name) (from \(tool.serverName))\n"
            result += "\(tool.description)\n"
            
            if let properties = tool.inputSchema.properties {
                result += "Parameters:\n"
                for (name, schema) in properties {
                    let required = tool.inputSchema.required?.contains(name) == true ? " (required)" : ""
                    result += "- `\(name)`: \(schema.type)\(required)"
                    if let desc = schema.description {
                        result += " - \(desc)"
                    }
                    result += "\n"
                }
            }
            result += "\n"
        }
        
        return result
    }
}
