//
//  LanguageServerManager.swift
//  LingCode
//
//  Multi-Language LSP Support: Manages different language servers
//  Supports Swift (sourcekit-lsp), TypeScript/JavaScript (tsserver), Python (pyright)
//

import Foundation

/// Manages multiple language servers for different file types
class LanguageServerManager {
    static let shared = LanguageServerManager()
    
    private var servers: [String: LSPClientProtocol] = [:]
    private let serverQueue = DispatchQueue(label: "com.lingcode.lspmanager", attributes: .concurrent)
    
    private init() {}
    
    /// Get or create language server for a file
    func getServer(for fileURL: URL, workspaceURL: URL) throws -> LSPClientProtocol {
        let language = detectLanguage(from: fileURL)
        
        return try serverQueue.sync {
            if let existing = servers[language] {
                return existing
            }
            
            let server: LSPClientProtocol
            switch language {
            case "swift":
                server = SourceKitLSPClient.shared
            case "typescript", "javascript":
                server = try TypeScriptLSPClient(workspaceURL: workspaceURL)
            case "python":
                server = try PythonLSPClient(workspaceURL: workspaceURL)
            default:
                // Fallback to SourceKit-LSP for unknown languages
                server = SourceKitLSPClient.shared
            }
            
            servers[language] = server
            return server
        }
    }
    
    /// Detect language from file extension
    private func detectLanguage(from fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return "swift"
        case "ts", "tsx":
            return "typescript"
        case "js", "jsx", "mjs", "cjs":
            return "javascript"
        case "py", "pyi":
            return "python"
        default:
            return "swift" // Default fallback
        }
    }
    
    /// Stop all language servers
    func stopAllServers() {
        serverQueue.async(flags: .barrier) {
            for server in self.servers.values {
                if let stoppable = server as? StoppableLSPClient {
                    stoppable.stop()
                }
            }
            self.servers.removeAll()
        }
    }
}

/// Protocol for LSP clients
protocol LSPClientProtocol {
    var isAvailable: Bool { get }
    func rename(at position: LSPPosition, in fileURL: URL, newName: String, fileContent: String?) async throws -> LSPWorkspaceEdit
    func getCompletions(at position: LSPPosition, in fileURL: URL, fileContent: String?) async throws -> [LSPCompletionItem]
    func getDiagnostics(for fileURL: URL, fileContent: String?) async throws -> [LSPDiagnostic]
}

/// Protocol for servers that can be stopped
protocol StoppableLSPClient {
    func stop()
}

// MARK: - TypeScript/JavaScript LSP Client

class TypeScriptLSPClient: LSPClientProtocol, StoppableLSPClient {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var requestIdCounter = 0
    private let requestQueue = DispatchQueue(label: "com.lingcode.tsserver", attributes: .concurrent)
    private var pendingRequests: [Int: (Result<Any, Error>) -> Void] = [:]
    private var messageBuffer = Data()
    private let bufferQueue = DispatchQueue(label: "com.lingcode.tsserver.buffer", attributes: .concurrent)
    private let workspaceURL: URL
    
    var isAvailable: Bool {
        // Check if tsserver is available (usually via npm/node)
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync("which tsserver", workingDirectory: nil)
        return result.exitCode == 0
    }
    
    init(workspaceURL: URL) throws {
        self.workspaceURL = workspaceURL
        try startServer()
    }
    
    private func startServer() throws {
        // Try to find tsserver (usually in node_modules/.bin or globally)
        let terminalService = TerminalExecutionService.shared
        let whichResult = terminalService.executeSync("which tsserver", workingDirectory: workspaceURL)
        
        let executablePath: String
        if whichResult.exitCode == 0 {
            executablePath = whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Try npm path
            let npmResult = terminalService.executeSync("npm list -g typescript 2>/dev/null | head -1", workingDirectory: workspaceURL)
            guard npmResult.exitCode == 0 else {
                throw LanguageServerError.notFound("tsserver")
            }
            // If npm found typescript, try to construct tsserver path
            // Common locations: /usr/local/lib/node_modules/typescript/bin/tsserver or ~/.npm-global/lib/node_modules/typescript/bin/tsserver
            let npmPathResult = terminalService.executeSync("npm root -g", workingDirectory: workspaceURL)
            if npmPathResult.exitCode == 0 {
                let npmRoot = npmPathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                executablePath = "\(npmRoot)/typescript/bin/tsserver"
            } else {
                // Fallback to common location
                executablePath = "/usr/local/lib/node_modules/typescript/bin/tsserver"
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []
        process.currentDirectoryURL = workspaceURL
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        
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
        try sendInitialize()
    }
    
    private func sendInitialize() throws {
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
    }
    
    func rename(at position: LSPPosition, in fileURL: URL, newName: String, fileContent: String?) async throws -> LSPWorkspaceEdit {
        // Implementation similar to SourceKitLSPClient
        // For now, throw not implemented
        throw LanguageServerError.notImplemented("TypeScript rename")
    }
    
    func getCompletions(at position: LSPPosition, in fileURL: URL, fileContent: String?) async throws -> [LSPCompletionItem] {
        // Implementation for TypeScript completions
        throw LanguageServerError.notImplemented("TypeScript completions")
    }
    
    func getDiagnostics(for fileURL: URL, fileContent: String?) async throws -> [LSPDiagnostic] {
        // Implementation for TypeScript diagnostics
        throw LanguageServerError.notImplemented("TypeScript diagnostics")
    }
    
    func stop() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }
    
    private func handleOutput(_ data: Data) {
        bufferQueue.async(flags: .barrier) {
            self.messageBuffer.append(data)
            self.processBufferedMessages()
        }
    }
    
    private func processBufferedMessages() {
        // Similar to SourceKitLSPClient implementation
    }
    
    private func sendLSPMessage(_ data: Data) {
        guard let inputPipe = inputPipe else { return }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        let headerData = header.data(using: .utf8)!
        inputPipe.fileHandleForWriting.write(headerData)
        inputPipe.fileHandleForWriting.write(data)
    }
    
    private func getNextRequestId() -> Int {
        requestIdCounter += 1
        return requestIdCounter
    }
}

// MARK: - Python LSP Client

class PythonLSPClient: LSPClientProtocol, StoppableLSPClient {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private let workspaceURL: URL
    
    var isAvailable: Bool {
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync("which pyright-langserver", workingDirectory: nil)
        return result.exitCode == 0
    }
    
    init(workspaceURL: URL) throws {
        self.workspaceURL = workspaceURL
        try startServer()
    }
    
    private func startServer() throws {
        let terminalService = TerminalExecutionService.shared
        let whichResult = terminalService.executeSync("which pyright-langserver", workingDirectory: workspaceURL)
        
        guard whichResult.exitCode == 0 else {
            throw LanguageServerError.notFound("pyright-langserver")
        }
        
        let executablePath = whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []
        process.currentDirectoryURL = workspaceURL
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        
        try process.run()
        
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
    }
    
    func rename(at position: LSPPosition, in fileURL: URL, newName: String, fileContent: String?) async throws -> LSPWorkspaceEdit {
        throw LanguageServerError.notImplemented("Python rename")
    }
    
    func getCompletions(at position: LSPPosition, in fileURL: URL, fileContent: String?) async throws -> [LSPCompletionItem] {
        throw LanguageServerError.notImplemented("Python completions")
    }
    
    func getDiagnostics(for fileURL: URL, fileContent: String?) async throws -> [LSPDiagnostic] {
        throw LanguageServerError.notImplemented("Python diagnostics")
    }
    
    func stop() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }
}

// MARK: - Shared LSP Types (moved from SourceKitLSPClient)

public struct LSPCompletionItem: Codable {
    public let label: String
    public let kind: Int?
    public let detail: String?
    public let documentation: String?
    public let insertText: String?
    public let textEdit: LSPTextEdit?
    
    public init(label: String, kind: Int?, detail: String?, documentation: String?, insertText: String?, textEdit: LSPTextEdit?) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.documentation = documentation
        self.insertText = insertText
        self.textEdit = textEdit
    }
}

public struct LSPDiagnostic: Codable {
    public let range: LSPRange
    public let severity: Int // 1=Error, 2=Warning, 3=Info, 4=Hint
    public let code: String?
    public let source: String?
    public let message: String
    
    public init(range: LSPRange, severity: Int, code: String?, source: String?, message: String) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
    }
}

enum LanguageServerError: Error, LocalizedError {
    case notFound(String)
    case notImplemented(String)
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .notFound(let server):
            return "Language server not found: \(server)"
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .notAvailable:
            return "Language server is not available"
        }
    }
}
