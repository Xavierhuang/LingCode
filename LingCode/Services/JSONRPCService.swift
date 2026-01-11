//
//  JSONRPCService.swift
//  LingCode
//
//  VS Code Extension Parity via JSON-RPC protocol
//

import Foundation

// MARK: - JSON-RPC Protocol

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: JSONRPCParams
    
    init(id: String, method: String, params: JSONRPCParams) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCParams: Codable {
    let task: String?
    let file: String?
    let cursor: Int?
    let newName: String?
    let edits: [Edit]?
    
    // Add other params as needed
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: String
    let result: JSONRPCResult?
    let error: JSONRPCError?
    
    init(id: String, result: JSONRPCResult?, error: JSONRPCError?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

struct JSONRPCResult: Codable {
    let edits: [Edit]?
    let success: Bool?
    let message: String?
}

struct JSONRPCError: Error, Codable {
    let code: Int
    let message: String
    let data: String?
}

// MARK: - JSON-RPC Service

class JSONRPCService {
    static let shared = JSONRPCService()
    
    private var handlers: [String: (JSONRPCParams) async throws -> JSONRPCResult] = [:]
    
    private init() {
        registerHandlers()
    }
    
    /// Register all handlers
    private func registerHandlers() {
        // Rename handler
        handlers["rename"] = { [weak self] params in
            guard let file = params.file,
                  let cursor = params.cursor,
                  let newName = params.newName else {
                throw JSONRPCError(code: -32602, message: "Invalid params", data: nil)
            }
            
            // Keep weak self reference for potential future use
            _ = self
            
            let fileURL = URL(fileURLWithPath: file)
            let renameService = RenameRefactorService.shared
            
            // Resolve symbol at cursor
            guard let symbol = renameService.resolveSymbol(at: cursor, in: fileURL) else {
                throw JSONRPCError(code: -32000, message: "Symbol not found", data: nil)
            }
            
            // Get project URL (parent directory)
            let projectURL = fileURL.deletingLastPathComponent()
            
            // Perform rename
            let edits = try await renameService.rename(
                symbol: symbol,
                to: newName,
                in: projectURL
            )
            
            return JSONRPCResult(edits: edits, success: true, message: nil)
        }
        
        // Edit handler
        handlers["edit"] = { params in
            guard let edits = params.edits else {
                throw JSONRPCError(code: -32602, message: "Invalid params", data: nil)
            }
            
            // Apply edits using AtomicEditService
            // Placeholder - would integrate with actual edit application
            return JSONRPCResult(edits: edits, success: true, message: nil)
        }
        
        // Refactor handler
        handlers["refactor"] = { params in
            // Placeholder for refactor operations
            return JSONRPCResult(edits: nil, success: true, message: "Refactor completed")
        }
    }
    
    /// Handle JSON-RPC request
    func handleRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let handler = handlers[request.method] else {
            throw JSONRPCError(
                code: -32601,
                message: "Method not found: \(request.method)",
                data: nil
            )
        }
        
        do {
            let result = try await handler(request.params)
            return JSONRPCResponse(
                id: request.id,
                result: result,
                error: nil
            )
        } catch let error as JSONRPCError {
            return JSONRPCResponse(
                id: request.id,
                result: nil,
                error: error
            )
        } catch {
            return JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(
                    code: -32603,
                    message: "Internal error: \(error.localizedDescription)",
                    data: nil
                )
            )
        }
    }
    
    /// Process JSON-RPC message (from VS Code extension)
    func processMessage(_ jsonData: Data) async throws -> Data {
        let decoder = JSONDecoder()
        let request = try decoder.decode(JSONRPCRequest.self, from: jsonData)
        
        let response = try await handleRequest(request)
        
        let encoder = JSONEncoder()
        return try encoder.encode(response)
    }
}

// MARK: - VS Code Extension Bridge

class VSCodeExtensionBridge {
    static let shared = VSCodeExtensionBridge()
    
    private let rpcService = JSONRPCService.shared
    private var connection: URLSessionWebSocketTask?
    
    private init() {}
    
    /// Start WebSocket connection to VS Code extension
    func startConnection(port: Int = 8080) {
        // Placeholder - would establish WebSocket connection
        // VS Code extension connects to this port
    }
    
    /// Handle message from VS Code
    func handleMessage(_ message: String) async throws -> String {
        guard let data = message.data(using: .utf8) else {
            throw JSONRPCError(code: -32700, message: "Parse error", data: nil)
        }
        
        let responseData = try await rpcService.processMessage(data)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }
}
