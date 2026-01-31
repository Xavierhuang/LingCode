//  TerminalExecutionService.swift
//  LingCode
//
//  Governed Execution: Manages shell processes with environment awareness and long-running detection.

import Foundation
import Combine

class TerminalExecutionService: ObservableObject {
    static let shared = TerminalExecutionService()
    
    @Published var isExecuting: Bool = false
    @Published var currentCommand: String?
    @Published var output: String = ""
    @Published var commandHistory: [CommandExecution] = []
    @Published var isLongRunning: Bool = false
    
    private var currentProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    private init() {}
    
    // MARK: - Core Execution
    
    func execute(
        _ command: String,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        onOutput: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onComplete: @escaping (Int32) -> Void
    ) {
        guard !isExecuting else {
            onError("Blocked: Another process is already running.")
            return
        }
        
        // Reset State on Main Thread
        DispatchQueue.main.async {
            self.isExecuting = true
            self.currentCommand = command
            self.output = ""
            self.isLongRunning = false
        }
        
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        self.currentProcess = process
        self.outputPipe = pipe
        self.errorPipe = errorPipe
        
        // 🟢 Character-by-character streaming via readabilityHandler
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self.output += str
                    onOutput(str)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self.output += str
                    onError(str)
                }
            }
        }
        
        // 🟢 Environment Awareness: Inherits local PATHs and uses login shell
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", normalizeCommand(command)]
        process.currentDirectoryURL = workingDirectory
        
        var env = ProcessInfo.processInfo.environment
        if let customEnv = environment { customEnv.forEach { env[$0] = $1 } }
        
        // Ensure standard dev paths are available
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "\(home)/.cargo/bin"]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (commonPaths + [existingPath]).joined(separator: ":")
        
        process.environment = env
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        process.terminationHandler = { proc in
            // Clean up handlers to prevent memory leaks
            pipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            
            DispatchQueue.main.async {
                self.isExecuting = false
                self.isLongRunning = false
                self.currentProcess = nil
                onComplete(proc.terminationStatus)
                
                let historyItem = CommandExecution(
                    command: command,
                    workingDirectory: workingDirectory?.path,
                    startTime: Date(),
                    exitCode: proc.terminationStatus
                )
                self.commandHistory.insert(historyItem, at: 0)
            }
        }
        
        do {
            try process.run()
            
            // Check for long-running processes (Servers, Watchers)
            if isLongRunningCommand(command) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.currentProcess == process { self.isLongRunning = true }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isExecuting = false
                onError("Launch Failed: \(error.localizedDescription)")
                onComplete(-1)
            }
        }
    }

    // MARK: - Synchronous execution (for quick checks: which, git status, swift build, etc.)

    struct SyncResult {
        var output: String
        var exitCode: Int32
    }

    /// Runs a command synchronously and returns combined stdout+stderr and exit code. Use for short-lived checks only.
    func executeSync(_ command: String, workingDirectory: URL? = nil) -> SyncResult {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", normalizeCommand(command)]
        process.currentDirectoryURL = workingDirectory
        
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "\(home)/.cargo/bin"]
        env["PATH"] = (commonPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return SyncResult(output: "Launch failed: \(error.localizedDescription)", exitCode: -1)
        }
        
        let dataOut = outPipe.fileHandleForReading.readDataToEndOfFile()
        let dataErr = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: dataOut, encoding: .utf8) ?? ""
        let errStr = String(data: dataErr, encoding: .utf8) ?? ""
        let output = outStr + (errStr.isEmpty ? "" : "\n\(errStr)")
        
        return SyncResult(output: output, exitCode: process.terminationStatus)
    }

    // MARK: - Helpers
    
    private func isLongRunningCommand(_ command: String) -> Bool {
        let patterns = ["http.server", "npm start", "npm run dev", "serve", "watch", "flask run"]
        return patterns.contains { command.lowercased().range(of: $0, options: .regularExpression) != nil }
    }
    
    private func normalizeCommand(_ command: String) -> String {
        var cmd = command
        if cmd.contains("python ") && !cmd.contains("python3 ") {
            cmd = cmd.replacingOccurrences(of: "python ", with: "python3 ")
        }
        return cmd
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        isExecuting = false
    }
    
    func extractCommands(from response: String) -> [ParsedCommand] {
        var commands: [ParsedCommand] = []
        let pattern = #"```(?:bash|shell|sh|zsh|terminal)\n([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: response) {
                    let content = String(response[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    content.components(separatedBy: .newlines).forEach { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                            commands.append(ParsedCommand(command: trimmed, description: nil, isDestructive: trimmed.contains("rm ")))
                        }
                    }
                }
            }
        }
        return commands
    }
}

// MARK: - Support Structures (Restored to fix build errors)

struct CommandExecution: Identifiable {
    let id = UUID()
    let command: String
    let workingDirectory: String?
    let startTime: Date
    var exitCode: Int32?
}

struct ParsedCommand: Identifiable {
    let id = UUID()
    let command: String
    let description: String?
    let isDestructive: Bool
}
