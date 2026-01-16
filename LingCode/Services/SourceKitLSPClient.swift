//
//  SourceKitLSPClient.swift
//  LingCode
//
//  Level 3 Semantic Refactoring: SourceKit-LSP integration for type-aware rename
//  Beats Cursor by using compiler's type information instead of name matching
//

import Foundation

// MARK: - LSP Protocol Types

public struct LSPPosition: Codable {
    public let line: Int
    public let character: Int
    
    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct LSPRange: Codable {
    public let start: LSPPosition
    public let end: LSPPosition
    
    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

struct LSPLocation: Codable {
    let uri: String
    let range: LSPRange
}

struct LSPTextDocumentIdentifier: Codable {
    let uri: String
}

struct LSPTextDocumentPositionParams: Codable {
    let textDocument: LSPTextDocumentIdentifier
    let position: LSPPosition
}

struct LSPRenameParams: Codable {
    let textDocument: LSPTextDocumentIdentifier
    let position: LSPPosition
    let newName: String
}

/// LSP WorkspaceEdit - returned from textDocument/rename
/// Contains all file edits with type-aware references
public struct LSPWorkspaceEdit: Codable {
    public var changes: [String: [LSPTextEdit]]
    
    public init(changes: [String: [LSPTextEdit]]) {
        self.changes = changes
    }
}

public struct LSPTextEdit: Codable {
    public let range: LSPRange
    public let newText: String
    
    public init(range: LSPRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}

// LSPRequest is not used - we manually create JSON instead
// Removed to fix Codable conformance issues

struct LSPResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: LSPWorkspaceEdit?
    let error: LSPError?
}

struct LSPError: Codable {
    let code: Int
    let message: String
}

// MARK: - SourceKit-LSP Client

class SourceKitLSPClient {
    static let shared = SourceKitLSPClient()
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var requestIdCounter = 0
    private let requestQueue = DispatchQueue(label: "com.lingcode.lsp", attributes: .concurrent)
    private var pendingRequests: [Int: (Result<LSPWorkspaceEdit, Error>) -> Void] = [:]
    
    // CRITICAL FIX: Stateful buffer for fragmented messages
    private var messageBuffer = Data()
    private let bufferQueue = DispatchQueue(label: "com.lingcode.lsp.buffer", attributes: .concurrent)
    
    // Track open files for didOpen/didChange notifications
    private var openFiles: Set<URL> = []
    private let openFilesQueue = DispatchQueue(label: "com.lingcode.lsp.files", attributes: .concurrent)
    
    private init() {}
    
    /// Check if SourceKit-LSP is available
    var isAvailable: Bool {
        // Check if sourcekit-lsp is in PATH
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync("which sourcekit-lsp", workingDirectory: nil)
        return result.exitCode == 0
    }
    
    /// Start SourceKit-LSP server (if not already running)
    /// 
    /// NOTE: For Swift Packages (Package.swift), this works out of the box.
    /// For Xcode projects (.xcodeproj), you may need:
    /// - Build Server Protocol (BSP) integration
    /// - compile_commands.json generation
    /// - Or use BuildServer (open source) to bridge Xcode to LSP
    /// 
    /// TODO: Add BSP support for Xcode projects in future release
    func startServer(for workspaceURL: URL) throws {
        guard process == nil else { return }
        
        // Find sourcekit-lsp executable
        let terminalService = TerminalExecutionService.shared
        let whichResult = terminalService.executeSync("which sourcekit-lsp", workingDirectory: nil)
        guard whichResult.exitCode == 0 else {
            throw SourceKitLSPError.notFound
        }
        
        let executablePath = whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []
        process.currentDirectoryURL = workspaceURL
        
        // TODO: For Xcode projects, may need to pass build settings or use BSP
        
        // Setup pipes
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        
        // Setup output handler with proper buffering
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutput(data)
        }
        
        try process.run()
        
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        
        // Send initialize request
        try sendInitialize(workspaceURL: workspaceURL)
    }
    
    /// Send initialize request
    private func sendInitialize(workspaceURL: URL) throws {
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": workspaceURL.absoluteString,
            "capabilities": [:]
        ]
        
        let requestId = getNextRequestId()
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": "initialize",
            "params": params
        ]
        
        let requestData = try JSONSerialization.data(withJSONObject: requestDict)
        sendLSPMessage(requestData)
        
        // Note: Initialize response handling would go here in full implementation
        // For now, we assume initialization succeeds
    }
    
    /// Perform semantic rename using LSP
    /// This is Level 3: Type-aware refactoring that distinguishes User.name from Product.name
    /// CRITICAL: Sends didOpen notification if file is not already open
    func rename(
        at position: LSPPosition,
        in fileURL: URL,
        newName: String,
        fileContent: String? = nil // Optional: current in-memory content (for unsaved changes)
    ) async throws -> LSPWorkspaceEdit {
        guard isAvailable else {
            throw SourceKitLSPError.notAvailable
        }
        
        // Ensure server is running
        if process == nil {
            try startServer(for: fileURL.deletingLastPathComponent())
        }
        
        // CRITICAL FIX: Notify LSP about file state (didOpen/didChange)
        // This ensures LSP uses in-memory content, not stale disk content
        try await ensureFileOpen(fileURL: fileURL, content: fileContent)
        
        let fileURI = fileURL.absoluteString
        let params = LSPRenameParams(
            textDocument: LSPTextDocumentIdentifier(uri: fileURI),
            position: position,
            newName: newName
        )
        
        // Send textDocument/rename request
        return try await withCheckedThrowingContinuation { continuation in
            requestQueue.async {
                do {
                    let edit = try self.sendRenameRequest(params: params)
                    continuation.resume(returning: edit)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Ensure file is open in LSP (sends didOpen if needed)
    /// CRITICAL: Prevents LSP from using stale disk content
    private func ensureFileOpen(fileURL: URL, content: String?) async throws {
        let isOpen = openFilesQueue.sync {
            return openFiles.contains(fileURL)
        }
        
        if !isOpen {
            // Send didOpen notification
            let fileContent = content ?? (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            try sendDidOpen(fileURL: fileURL, content: fileContent)
            
            openFilesQueue.async(flags: .barrier) {
                self.openFiles.insert(fileURL)
            }
        } else if let content = content {
            // File is open but content changed, send didChange
            try sendDidChange(fileURL: fileURL, content: content)
        }
    }
    
    /// Send textDocument/didOpen notification
    private func sendDidOpen(fileURL: URL, content: String) throws {
        let fileURI = fileURL.absoluteString
        let params: [String: Any] = [
            "textDocument": [
                "uri": fileURI,
                "languageId": "swift",
                "version": 1,
                "text": content
            ]
        ]
        
        let requestId = getNextRequestId()
        let requestData = try createNotificationJSON(method: "textDocument/didOpen", params: params)
        sendLSPMessage(requestData)
    }
    
    /// Send textDocument/didChange notification
    private func sendDidChange(fileURL: URL, content: String) throws {
        let fileURI = fileURL.absoluteString
        let params: [String: Any] = [
            "textDocument": [
                "uri": fileURI,
                "version": 2 // Increment version
            ],
            "contentChanges": [
                [
                    "text": content
                ]
            ]
        ]
        
        let requestData = try createNotificationJSON(method: "textDocument/didChange", params: params)
        sendLSPMessage(requestData)
    }
    
    /// Create notification JSON (no response expected)
    private func createNotificationJSON(method: String, params: [String: Any]) throws -> Data {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        return try JSONSerialization.data(withJSONObject: request)
    }
    
    /// Send LSP message (request or notification)
    private func sendLSPMessage(_ data: Data) {
        guard let inputPipe = inputPipe else { return }
        
        // LSP uses Content-Length header format
        let header = "Content-Length: \(data.count)\r\n\r\n"
        let headerData = header.data(using: .utf8)!
        
        inputPipe.fileHandleForWriting.write(headerData)
        inputPipe.fileHandleForWriting.write(data)
    }
    
    /// Send rename request and wait for response
    private func sendRenameRequest(params: LSPRenameParams) throws -> LSPWorkspaceEdit {
        let requestId = getNextRequestId()
        
        // Create request JSON manually
        let paramsDict: [String: Any] = [
            "textDocument": ["uri": params.textDocument.uri],
            "position": ["line": params.position.line, "character": params.position.character],
            "newName": params.newName
        ]
        
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": "textDocument/rename",
            "params": paramsDict
        ]
        
        let requestData = try JSONSerialization.data(withJSONObject: requestDict)
        
        // Send request using helper method
        sendLSPMessage(requestData)
        
        // Wait for response with timeout
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<LSPWorkspaceEdit, Error>?
        
        pendingRequests[requestId] = { response in
            result = response
            semaphore.signal()
        }
        
        // Wait up to 5 seconds
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            pendingRequests.removeValue(forKey: requestId)
            throw SourceKitLSPError.timeout
        }
        
        pendingRequests.removeValue(forKey: requestId)
        
        switch result! {
        case .success(let edit):
            return edit
        case .failure(let error):
            throw error
        }
    }
    
    /// Handle LSP output with proper buffering for fragmented messages
    /// CRITICAL FIX: Handles messages split across multiple pipe reads
    private func handleOutput(_ data: Data) {
        bufferQueue.async(flags: .barrier) {
            self.messageBuffer.append(data)
            self.processBufferedMessages()
        }
    }
    
    /// Process complete messages from buffer (handles fragmentation)
    private func processBufferedMessages() {
        while true {
            // Find header separator (\r\n\r\n)
            guard let headerSeparator = messageBuffer.range(of: Data("\r\n\r\n".utf8)) else {
                return // Wait for more data
            }
            
            // Parse header to get Content-Length
            let headerData = messageBuffer[..<headerSeparator.lowerBound]
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                // Invalid header, skip this message
                messageBuffer.removeSubrange(..<headerSeparator.upperBound)
                continue
            }
            
            // Extract Content-Length
            var contentLength: Int?
            for line in headerString.components(separatedBy: "\r\n") {
                if line.lowercased().hasPrefix("content-length:") {
                    let lengthString = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                    contentLength = Int(lengthString)
                    break
                }
            }
            
            guard let length = contentLength else {
                // No Content-Length found, skip this message
                messageBuffer.removeSubrange(..<headerSeparator.upperBound)
                continue
            }
            
            // Check if we have the complete message body
            let bodyStart = headerSeparator.upperBound
            let totalMessageLength = bodyStart + length
            
            if messageBuffer.count < totalMessageLength {
                return // Wait for more data
            }
            
            // Extract complete message body
            let bodyData = messageBuffer[bodyStart..<totalMessageLength]
            
            // Process the JSON message
            processJSONMessage(bodyData)
            
            // Remove processed message from buffer
            messageBuffer.removeSubrange(..<totalMessageLength)
        }
    }
    
    /// Process a complete JSON message
    private func processJSONMessage(_ jsonData: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let id = json["id"] as? Int else {
            return
        }
        
        if let result = json["result"] as? [String: Any] {
            // Parse WorkspaceEdit
            if let changes = result["changes"] as? [String: [[String: Any]]] {
                var workspaceEdit = LSPWorkspaceEdit(changes: [:])
                
                for (uri, edits) in changes {
                    var textEdits: [LSPTextEdit] = []
                    for edit in edits {
                        if let range = edit["range"] as? [String: Any],
                           let newText = edit["newText"] as? String,
                           let start = range["start"] as? [String: Any],
                           let end = range["end"] as? [String: Any],
                           let startLine = start["line"] as? Int,
                           let startChar = start["character"] as? Int,
                           let endLine = end["line"] as? Int,
                           let endChar = end["character"] as? Int {
                            
                            let textEdit = LSPTextEdit(
                                range: LSPRange(
                                    start: LSPPosition(line: startLine, character: startChar),
                                    end: LSPPosition(line: endLine, character: endChar)
                                ),
                                newText: newText
                            )
                            textEdits.append(textEdit)
                        }
                    }
                    workspaceEdit.changes[uri] = textEdits
                }
                
                requestQueue.async {
                    self.pendingRequests[id]?(.success(workspaceEdit))
                }
            }
        } else if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            requestQueue.async {
                self.pendingRequests[id]?(.failure(SourceKitLSPError.serverError(message)))
            }
        }
    }
    
    
    /// Get next request ID
    private func getNextRequestId() -> Int {
        requestIdCounter += 1
        return requestIdCounter
    }
    
    /// Stop server
    func stopServer() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        
        // Clear buffer and open files
        bufferQueue.async(flags: .barrier) {
            self.messageBuffer.removeAll()
        }
        openFilesQueue.async(flags: .barrier) {
            self.openFiles.removeAll()
        }
    }
    
    /// Notify LSP that file was closed (cleanup)
    func notifyFileClosed(fileURL: URL) {
        let fileURI = fileURL.absoluteString
        let params: [String: Any] = [
            "textDocument": ["uri": fileURI]
        ]
        
        if let requestData = try? createNotificationJSON(method: "textDocument/didClose", params: params) {
            sendLSPMessage(requestData)
        }
        
        openFilesQueue.async(flags: .barrier) {
            self.openFiles.remove(fileURL)
        }
    }
}

// MARK: - Errors

enum SourceKitLSPError: Error, LocalizedError {
    case notFound
    case notAvailable
    case notInitialized
    case timeout
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "SourceKit-LSP not found. Please install Xcode Command Line Tools."
        case .notAvailable:
            return "SourceKit-LSP is not available"
        case .notInitialized:
            return "SourceKit-LSP server not initialized"
        case .timeout:
            return "SourceKit-LSP request timed out"
        case .serverError(let message):
            return "SourceKit-LSP error: \(message)"
        }
    }
}
