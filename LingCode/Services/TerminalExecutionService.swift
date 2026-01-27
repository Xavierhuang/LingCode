//
//  TerminalExecutionService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

/// Service for executing terminal commands from AI responses
class TerminalExecutionService: ObservableObject {
    static let shared = TerminalExecutionService()
    
    @Published var isExecuting: Bool = false
    @Published var currentCommand: String?
    @Published var output: String = ""
    @Published var commandHistory: [CommandExecution] = []
    @Published var isLongRunning: Bool = false // Track if command is a long-running process
    
    private var currentProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var longRunningTimer: Timer?
    
    private init() {}
    
    /// Check if command is likely a long-running server process
    private func isLongRunningCommand(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        let longRunningPatterns = [
            "http.server",
            "npm start",
            "npm run dev",
            "npm run serve",
            "yarn start",
            "yarn dev",
            "python.*server",
            "flask run",
            "rails server",
            "rails s",
            "node.*server",
            "serve",
            "dev",
            "watch"
        ]
        return longRunningPatterns.contains { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    // MARK: - Command Execution
    
    /// Execute a shell command
    func execute(
        _ command: String,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        onOutput: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onComplete: @escaping (Int32) -> Void
    ) {
        guard !isExecuting else {
            onError("Another command is already executing")
            return
        }
        
        DispatchQueue.main.async {
            self.isExecuting = true
            self.currentCommand = command
            self.output = ""
        }
        
        let execution = CommandExecution(
            command: command,
            workingDirectory: workingDirectory?.path,
            startTime: Date()
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            self.currentProcess = process
            
            // Normalize command (python -> python3 on macOS)
            let normalizedCommand = self.normalizeCommand(command)
            
            // Use login shell to get full environment (loads .zshrc, etc.)
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", normalizedCommand]
            
            // Set working directory
            if let workDir = workingDirectory {
                process.currentDirectoryURL = workDir
            }
            
            // Set environment with proper PATH
            var env = ProcessInfo.processInfo.environment
            if let customEnv = environment {
                for (key, value) in customEnv {
                    env[key] = value
                }
            }
            
            // Build comprehensive PATH
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let commonPaths = [
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "/usr/local/sbin",
                "/usr/bin",
                "/usr/sbin",
                "/bin",
                "/sbin",
                "\(homeDir)/.local/bin",
                "\(homeDir)/.cargo/bin",
                "\(homeDir)/.go/bin",
                "\(homeDir)/.yarn/bin",
                "\(homeDir)/.config/yarn/global/node_modules/.bin"
            ]
            
            let existingPath = env["PATH"] ?? ""
            let pathSet = Set(commonPaths + existingPath.split(separator: ":").map(String.init))
            env["PATH"] = Array(pathSet).joined(separator: ":")
            
            process.environment = env
            
            // Setup output pipe
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Handle output
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                    DispatchQueue.main.async {
                        self.output += string
                        onOutput(string)
                    }
                }
            }
            
            // Handle errors
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                    DispatchQueue.main.async {
                        self.output += string
                        onError(string)
                    }
                }
            }
            
            do {
                try process.run()
                
                // Check if this is a long-running command
                let isLongRunningCmd = self.isLongRunningCommand(command)
                
                if isLongRunningCmd {
                    // For long-running processes, mark as background after 2 seconds
                    // Don't wait for exit - let it run in background
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if self.currentProcess == process {
                            self.isLongRunning = true
                            // Process continues running - don't call onComplete
                            // User can stop it manually via cancel()
                        }
                    }
                    
                    // Monitor process termination in background
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        
                        // Process exited - cleanup
                        DispatchQueue.main.async {
                            if self.currentProcess == process {
                                outputPipe.fileHandleForReading.readabilityHandler = nil
                                errorPipe.fileHandleForReading.readabilityHandler = nil
                                
                                var finalExecution = execution
                                finalExecution.exitCode = process.terminationStatus
                                finalExecution.output = self.output
                                finalExecution.endTime = Date()
                                self.commandHistory.insert(finalExecution, at: 0)
                                
                                self.isExecuting = false
                                self.isLongRunning = false
                                self.currentProcess = nil
                                self.currentCommand = nil
                                
                                onComplete(process.terminationStatus)
                            }
                        }
                    }
                } else {
                    // For normal commands, wait until exit
                    process.waitUntilExit()
                    
                    // Cleanup
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    
                    let exitCode = process.terminationStatus
                    
                    DispatchQueue.main.async {
                        var finalExecution = execution
                        finalExecution.exitCode = exitCode
                        finalExecution.output = self.output
                        finalExecution.endTime = Date()
                        self.commandHistory.insert(finalExecution, at: 0)
                        
                        self.isExecuting = false
                        self.isLongRunning = false
                        self.currentProcess = nil
                        self.currentCommand = nil
                        
                        onComplete(exitCode)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExecuting = false
                    self.isLongRunning = false
                    self.currentProcess = nil
                    self.currentCommand = nil
                    onError("Failed to execute command: \(error.localizedDescription)")
                    onComplete(-1)
                }
            }
        }
    }
    
    /// Execute command and return result synchronously (for simpler use cases)
    func executeSync(_ command: String, workingDirectory: URL? = nil) -> (output: String, exitCode: Int32) {
        let process = Process()
        
        // Normalize command
        let normalizedCommand = normalizeCommand(command)
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", normalizedCommand]
        
        if let workDir = workingDirectory {
            process.currentDirectoryURL = workDir
        }
        
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/usr/sbin",
            "/bin",
            "/sbin",
            "\(homeDir)/.local/bin",
            "\(homeDir)/.cargo/bin",
            "\(homeDir)/.go/bin",
            "\(homeDir)/.yarn/bin",
            "\(homeDir)/.config/yarn/global/node_modules/.bin"
        ]
        
        let existingPath = env["PATH"] ?? ""
        let pathSet = Set(commonPaths + existingPath.split(separator: ":").map(String.init))
        env["PATH"] = Array(pathSet).joined(separator: ":")
        
        process.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            return (output + error, process.terminationStatus)
        } catch {
            return ("Error: \(error.localizedDescription)", -1)
        }
    }
    
    /// Cancel current execution
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        
        DispatchQueue.main.async {
            self.isExecuting = false
            self.currentCommand = nil
            self.output += "\n[Cancelled by user]"
        }
    }
    
    // MARK: - Command Parsing from AI Response
    
    /// Extract terminal commands from AI response
    func extractCommands(from response: String) -> [ParsedCommand] {
        var commands: [ParsedCommand] = []
        
        // Pattern 1: ```bash or ```shell or ```sh code blocks
        let shellPatterns = [
            #"```(?:bash|shell|sh|zsh|terminal)\n([\s\S]*?)```"#,
            #"```\n((?:cd |npm |yarn |pip |python |cargo |swift |go |git |mkdir |touch |rm |mv |cp |ls |cat |echo |export |source |chmod |curl |wget )[\s\S]*?)```"#
        ]
        
        for pattern in shellPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(response.startIndex..<response.endIndex, in: response)
                let matches = regex.matches(in: response, options: [], range: range)
                
                for match in matches {
                    if match.numberOfRanges > 1,
                       let contentRange = Range(match.range(at: 1), in: response) {
                        let content = String(response[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Split into individual commands
                        let lines = content.components(separatedBy: .newlines)
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                                commands.append(ParsedCommand(
                                    command: trimmed,
                                    description: extractCommandDescription(for: trimmed, in: response),
                                    isDestructive: isDestructiveCommand(trimmed)
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        // Pattern 2: Inline commands with $ prefix
        let inlinePattern = #"\$\s+([^\n]+)"#
        if let regex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches {
                if match.numberOfRanges > 1,
                   let commandRange = Range(match.range(at: 1), in: response) {
                    let command = String(response[commandRange]).trimmingCharacters(in: .whitespaces)
                    if !commands.contains(where: { $0.command == command }) {
                        commands.append(ParsedCommand(
                            command: command,
                            description: nil,
                            isDestructive: isDestructiveCommand(command)
                        ))
                    }
                }
            }
        }
        
        return commands
    }
    
    /// Execute all commands from AI response
    func executeFromAIResponse(
        _ response: String,
        workingDirectory: URL?,
        requireConfirmation: Bool = true,
        onCommand: @escaping (ParsedCommand) -> Void,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool) -> Void
    ) {
        let commands = extractCommands(from: response)
        
        guard !commands.isEmpty else {
            onComplete(true)
            return
        }
        
        // Execute commands sequentially
        executeCommandSequence(
            commands,
            index: 0,
            workingDirectory: workingDirectory,
            onCommand: onCommand,
            onOutput: onOutput,
            onComplete: onComplete
        )
    }
    
    private func executeCommandSequence(
        _ commands: [ParsedCommand],
        index: Int,
        workingDirectory: URL?,
        onCommand: @escaping (ParsedCommand) -> Void,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool) -> Void
    ) {
        guard index < commands.count else {
            onComplete(true)
            return
        }
        
        let command = commands[index]
        onCommand(command)
        
        execute(
            command.command,
            workingDirectory: workingDirectory,
            environment: nil,
            onOutput: onOutput,
            onError: onOutput,
            onComplete: { exitCode in
                if exitCode == 0 || !command.isDestructive {
                    // Continue with next command
                    self.executeCommandSequence(
                        commands,
                        index: index + 1,
                        workingDirectory: workingDirectory,
                        onCommand: onCommand,
                        onOutput: onOutput,
                        onComplete: onComplete
                    )
                } else {
                    // Stop on error for destructive commands
                    onComplete(false)
                }
            }
        )
    }
    
    // MARK: - Helpers
    
    /// Normalize command for macOS (python -> python3, etc.)
    private func normalizeCommand(_ command: String) -> String {
        var normalized = command
        
        // Replace python with python3 on macOS (unless it's already python3)
        if normalized.contains("python ") && !normalized.contains("python3 ") {
            normalized = normalized.replacingOccurrences(of: "python ", with: "python3 ")
            normalized = normalized.replacingOccurrences(of: "python\n", with: "python3\n")
            normalized = normalized.replacingOccurrences(of: "python\t", with: "python3\t")
        }
        
        // Try to find npm/node in common locations and use full path if needed
        // This helps avoid PATH issues
        if normalized.hasPrefix("npm ") || normalized.hasPrefix("npm\n") || normalized.hasPrefix("npm\t") {
            // Check if we can find npm in common locations
            let npmPaths = [
                "/opt/homebrew/bin/npm",
                "/usr/local/bin/npm",
                "/usr/bin/npm"
            ]
            
            for npmPath in npmPaths {
                if FileManager.default.fileExists(atPath: npmPath) {
                    normalized = normalized.replacingOccurrences(of: "npm ", with: "\(npmPath) ")
                    normalized = normalized.replacingOccurrences(of: "npm\n", with: "\(npmPath)\n")
                    normalized = normalized.replacingOccurrences(of: "npm\t", with: "\(npmPath)\t")
                    break
                }
            }
        }
        
        return normalized
    }
    
    private func extractCommandDescription(for command: String, in response: String) -> String? {
        // Simple heuristic: look for text before the command
        if let range = response.range(of: command) {
            let beforeCommand = response[response.startIndex..<range.lowerBound]
            let lines = beforeCommand.components(separatedBy: .newlines)
            if let lastLine = lines.filter({ !$0.isEmpty }).last {
                let trimmed = lastLine.trimmingCharacters(in: CharacterSet(charactersIn: ":-*#`"))
                    .trimmingCharacters(in: .whitespaces)
                if trimmed.count > 5 && trimmed.count < 200 {
                    return trimmed
                }
            }
        }
        
        return nil
    }
    
    private func isDestructiveCommand(_ command: String) -> Bool {
        let destructivePatterns = [
            "rm ", "rm\t", "rmdir",
            "delete", "remove",
            "drop ", "truncate",
            "format",
            "> /", ">> /",
            "sudo rm",
            "git reset --hard",
            "git clean -fd"
        ]
        
        let lowercased = command.lowercased()
        return destructivePatterns.contains { lowercased.contains($0) }
    }
    
    // MARK: - Common Commands
    
    /// Install dependencies for a project
    func installDependencies(at projectURL: URL, onOutput: @escaping (String) -> Void, onComplete: @escaping (Bool) -> Void) {
        // Detect project type and run appropriate install command
        let fileManager = FileManager.default
        
        var command: String?
        
        if fileManager.fileExists(atPath: projectURL.appendingPathComponent("package.json").path) {
            command = "npm install"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("yarn.lock").path) {
            command = "yarn install"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("requirements.txt").path) {
            command = "pip install -r requirements.txt"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) {
            command = "cargo build"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) {
            command = "swift build"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("go.mod").path) {
            command = "go mod download"
        }
        
        guard let installCommand = command else {
            onOutput("No recognized project type found")
            onComplete(false)
            return
        }
        
        execute(
            installCommand,
            workingDirectory: projectURL,
            environment: nil,
            onOutput: onOutput,
            onError: onOutput,
            onComplete: { exitCode in
                onComplete(exitCode == 0)
            }
        )
    }
    
    /// Run a project
    func runProject(at projectURL: URL, onOutput: @escaping (String) -> Void, onComplete: @escaping (Bool) -> Void) {
        let fileManager = FileManager.default
        
        var command: String?
        
        if fileManager.fileExists(atPath: projectURL.appendingPathComponent("package.json").path) {
            command = "npm start"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("main.py").path) {
            command = "python3 main.py"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) {
            command = "cargo run"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) {
            command = "swift run"
        } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("main.go").path) {
            command = "go run main.go"
        }
        
        guard let runCommand = command else {
            onOutput("No recognized project type found")
            onComplete(false)
            return
        }
        
        execute(
            runCommand,
            workingDirectory: projectURL,
            environment: nil,
            onOutput: onOutput,
            onError: onOutput,
            onComplete: { exitCode in
                onComplete(exitCode == 0)
            }
        )
    }
}

// MARK: - Supporting Types

struct CommandExecution: Identifiable {
    let id = UUID()
    let command: String
    let workingDirectory: String?
    let startTime: Date
    var endTime: Date?
    var exitCode: Int32?
    var output: String?
    
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    var isSuccess: Bool {
        exitCode == 0
    }
}

struct ParsedCommand: Identifiable {
    let id = UUID()
    let command: String
    let description: String?
    let isDestructive: Bool
}

