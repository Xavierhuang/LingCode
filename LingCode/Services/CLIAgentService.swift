//
//  CLIAgentService.swift
//  LingCode
//
//  CLI Agent service for running LingCode agent from terminal
//  Usage: lingcode "fix all lint errors" or lingcode --help
//

import Foundation

// MARK: - CLI Command

struct CLICommand {
    let action: CLIAction
    let prompt: String?
    let options: CLIOptions
}

enum CLIAction {
    case run           // Run agent with prompt
    case ask           // Ask question (no file changes)
    case review        // Review current changes
    case commit        // Create commit
    case status        // Show agent status
    case list          // List recent agents
    case resume(UUID)  // Resume agent
    case cancel(UUID)  // Cancel agent
    case help          // Show help
    case version       // Show version
}

struct CLIOptions {
    var files: [String] = []
    var model: String?
    var maxSteps: Int = 50
    var autoApply: Bool = false
    var quiet: Bool = false
    var json: Bool = false
    var projectPath: String?
}

// MARK: - CLI Output

struct CLIOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

// MARK: - CLI Agent Service

class CLIAgentService {
    static let shared = CLIAgentService()
    
    private init() {}
    
    // MARK: - Command Parsing
    
    func parseArguments(_ args: [String]) -> CLICommand {
        var options = CLIOptions()
        var action: CLIAction = .help
        var prompt: String?
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            
            switch arg {
            case "-h", "--help":
                return CLICommand(action: .help, prompt: nil, options: options)
                
            case "-v", "--version":
                return CLICommand(action: .version, prompt: nil, options: options)
                
            case "ask", "--ask":
                action = .ask
                i += 1
                if i < args.count && !args[i].hasPrefix("-") {
                    prompt = args[i]
                }
                
            case "review", "--review":
                action = .review
                
            case "commit", "--commit":
                action = .commit
                
            case "status", "--status":
                action = .status
                
            case "list", "--list":
                action = .list
                
            case "resume":
                i += 1
                if i < args.count, let uuid = UUID(uuidString: args[i]) {
                    action = .resume(uuid)
                }
                
            case "cancel":
                i += 1
                if i < args.count, let uuid = UUID(uuidString: args[i]) {
                    action = .cancel(uuid)
                }
                
            case "-f", "--file":
                i += 1
                if i < args.count {
                    options.files.append(args[i])
                }
                
            case "-m", "--model":
                i += 1
                if i < args.count {
                    options.model = args[i]
                }
                
            case "--max-steps":
                i += 1
                if i < args.count, let steps = Int(args[i]) {
                    options.maxSteps = steps
                }
                
            case "-y", "--yes", "--auto-apply":
                options.autoApply = true
                
            case "-q", "--quiet":
                options.quiet = true
                
            case "--json":
                options.json = true
                
            case "-p", "--project":
                i += 1
                if i < args.count {
                    options.projectPath = args[i]
                }
                
            default:
                // If no action set and doesn't start with -, treat as prompt
                if !arg.hasPrefix("-") && prompt == nil {
                    action = .run
                    prompt = arg
                }
            }
            
            i += 1
        }
        
        return CLICommand(action: action, prompt: prompt, options: options)
    }
    
    // MARK: - Command Execution
    
    func execute(_ command: CLICommand) async -> CLIOutput {
        switch command.action {
        case .help:
            return helpOutput()
            
        case .version:
            return versionOutput()
            
        case .run:
            guard let prompt = command.prompt else {
                return CLIOutput(exitCode: 1, stdout: "", stderr: "Error: No prompt provided\n")
            }
            return await runAgent(prompt: prompt, options: command.options)
            
        case .ask:
            guard let prompt = command.prompt else {
                return CLIOutput(exitCode: 1, stdout: "", stderr: "Error: No question provided\n")
            }
            return await askQuestion(prompt: prompt, options: command.options)
            
        case .review:
            return await reviewChanges(options: command.options)
            
        case .commit:
            return await createCommit(options: command.options)
            
        case .status:
            return await getStatus(options: command.options)
            
        case .list:
            return await listAgents(options: command.options)
            
        case .resume(let id):
            return await resumeAgent(id: id, options: command.options)
            
        case .cancel(let id):
            return await cancelAgent(id: id, options: command.options)
        }
    }
    
    // MARK: - Actions
    
    private func runAgent(prompt: String, options: CLIOptions) async -> CLIOutput {
        let projectURL = options.projectPath.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        var output = ""
        var hasError = false
        
        if !options.quiet {
            output += "Starting agent...\n"
            output += "Project: \(projectURL.path)\n"
            output += "Prompt: \(prompt)\n\n"
        }
        
        // Build context
        var context = ""
        for file in options.files {
            let fileURL = URL(fileURLWithPath: file, relativeTo: projectURL)
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                context += "File: \(file)\n```\n\(content)\n```\n\n"
            }
        }
        
        // Run agent
        do {
            let result = try await executeAgentTask(
                prompt: prompt,
                context: context,
                projectURL: projectURL,
                options: options
            )
            
            if options.json {
                output = formatJSON(result)
            } else {
                output += result.output
                
                if !result.changes.isEmpty {
                    output += "\n\nChanges:\n"
                    for change in result.changes {
                        output += "  - \(change.file): \(change.description)\n"
                    }
                }
                
                if result.success {
                    output += "\nAgent completed successfully.\n"
                } else {
                    output += "\nAgent completed with errors.\n"
                    hasError = true
                }
            }
        } catch {
            hasError = true
            if options.json {
                output = "{\"error\": \"\(error.localizedDescription)\"}"
            } else {
                return CLIOutput(exitCode: 1, stdout: output, stderr: "Error: \(error.localizedDescription)\n")
            }
        }
        
        return CLIOutput(exitCode: hasError ? 1 : 0, stdout: output, stderr: "")
    }
    
    private func askQuestion(prompt: String, options: CLIOptions) async -> CLIOutput {
        var output = ""
        
        do {
            let response = try await askAI(prompt: prompt, options: options)
            
            if options.json {
                output = "{\"response\": \"\(response.replacingOccurrences(of: "\"", with: "\\\""))\"}"
            } else {
                output = response + "\n"
            }
            
            return CLIOutput(exitCode: 0, stdout: output, stderr: "")
        } catch {
            if options.json {
                return CLIOutput(exitCode: 1, stdout: "{\"error\": \"\(error.localizedDescription)\"}", stderr: "")
            }
            return CLIOutput(exitCode: 1, stdout: "", stderr: "Error: \(error.localizedDescription)\n")
        }
    }
    
    private func reviewChanges(options: CLIOptions) async -> CLIOutput {
        let projectURL = options.projectPath.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        // Get git diff
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["diff", "--stat"]
        task.currentDirectoryURL = projectURL
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let diff = String(data: data, encoding: .utf8) ?? ""
            
            if diff.isEmpty {
                return CLIOutput(exitCode: 0, stdout: "No changes to review.\n", stderr: "")
            }
            
            // Ask AI to review
            let reviewPrompt = "Review these git changes:\n\n\(diff)"
            let response = try await askAI(prompt: reviewPrompt, options: options)
            
            return CLIOutput(exitCode: 0, stdout: response + "\n", stderr: "")
        } catch {
            return CLIOutput(exitCode: 1, stdout: "", stderr: "Error: \(error.localizedDescription)\n")
        }
    }
    
    private func createCommit(options: CLIOptions) async -> CLIOutput {
        let skill = SkillsService.shared.findSkill("commit")
        let context = SkillContext(
            currentFile: nil,
            selectedText: nil,
            projectURL: options.projectPath.map { URL(fileURLWithPath: $0) },
            additionalArgs: []
        )
        
        if let skill = skill {
            let result = SkillsService.shared.executeSkill(skill, context: context)
            
            // Execute the commit skill
            do {
                let response = try await askAI(prompt: result.output, options: options)
                return CLIOutput(exitCode: 0, stdout: response + "\n", stderr: "")
            } catch {
                return CLIOutput(exitCode: 1, stdout: "", stderr: "Error: \(error.localizedDescription)\n")
            }
        }
        
        return CLIOutput(exitCode: 1, stdout: "", stderr: "Commit skill not found\n")
    }
    
    private func getStatus(options: CLIOptions) async -> CLIOutput {
        let activeTasks = SubagentService.shared.activeTasks
        
        if options.json {
            let tasksJSON = activeTasks.map { task -> [String: Any] in
                return [
                    "id": task.id.uuidString,
                    "type": task.type.rawValue,
                    "status": task.status.rawValue,
                    "description": task.description
                ]
            }
            
            if let data = try? JSONSerialization.data(withJSONObject: ["tasks": tasksJSON], options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return CLIOutput(exitCode: 0, stdout: json + "\n", stderr: "")
            }
        }
        
        var output = "Active Tasks: \(activeTasks.count)\n\n"
        
        for task in activeTasks {
            output += "[\(task.status.rawValue.uppercased())] \(task.type.displayName)\n"
            output += "  ID: \(task.id.uuidString)\n"
            output += "  Description: \(task.description)\n\n"
        }
        
        if activeTasks.isEmpty {
            output += "No active tasks.\n"
        }
        
        return CLIOutput(exitCode: 0, stdout: output, stderr: "")
    }
    
    private func listAgents(options: CLIOptions) async -> CLIOutput {
        let history = AgentHistoryService.shared.historyItems
        
        if options.json {
            let sessionsJSON = history.prefix(10).map { item -> [String: Any] in
                return [
                    "id": item.id.uuidString,
                    "name": item.customName ?? item.description,
                    "status": item.status.rawValue,
                    "createdAt": ISO8601DateFormatter().string(from: item.startTime)
                ]
            }
            
            if let data = try? JSONSerialization.data(withJSONObject: ["sessions": sessionsJSON], options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return CLIOutput(exitCode: 0, stdout: json + "\n", stderr: "")
            }
        }
        
        var output = "Recent Agent Sessions:\n\n"
        
        for item in history.prefix(10) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            
            output += "[\(item.status.rawValue.uppercased())] \(item.customName ?? item.description)\n"
            output += "  ID: \(item.id.uuidString)\n"
            output += "  Created: \(dateFormatter.string(from: item.startTime))\n\n"
        }
        
        if history.isEmpty {
            output += "No agent sessions found.\n"
        }
        
        return CLIOutput(exitCode: 0, stdout: output, stderr: "")
    }
    
    private func resumeAgent(id: UUID, options: CLIOptions) async -> CLIOutput {
        // Find session in history
        guard let session = AgentHistoryService.shared.historyItems.first(where: { $0.id == id }) else {
            return CLIOutput(exitCode: 1, stdout: "", stderr: "Agent session not found: \(id.uuidString)\n")
        }
        
        var output = "Resuming agent: \(session.customName ?? session.description)\n"
        output += "ID: \(id.uuidString)\n\n"
        
        // TODO: Implement actual resume logic
        output += "Resume not fully implemented yet.\n"
        
        return CLIOutput(exitCode: 0, stdout: output, stderr: "")
    }
    
    private func cancelAgent(id: UUID, options: CLIOptions) async -> CLIOutput {
        SubagentService.shared.cancelTask(id)
        
        return CLIOutput(exitCode: 0, stdout: "Agent cancelled: \(id.uuidString)\n", stderr: "")
    }
    
    // MARK: - Helpers
    
    private func executeAgentTask(prompt: String, context: String, projectURL: URL, options: CLIOptions) async throws -> SubagentResult {
        // Create a subagent task
        let task = SubagentService.shared.createTask(
            type: .coder,
            description: prompt,
            context: SubagentContext(
                projectURL: projectURL,
                files: options.files.map { URL(fileURLWithPath: $0, relativeTo: projectURL) },
                selectedText: nil,
                additionalContext: context
            )
        )
        
        // Wait for completion
        while true {
            if let completedTask = SubagentService.shared.completedTasks.first(where: { $0.id == task.id }) {
                if let result = completedTask.result {
                    return result
                }
                throw NSError(domain: "CLIAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task completed without result"])
            }
            
            if SubagentService.shared.activeTasks.first(where: { $0.id == task.id })?.status == .failed {
                throw NSError(domain: "CLIAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task failed"])
            }
            
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
    
    private func askAI(prompt: String, options: CLIOptions) async throws -> String {
        var fullResponse = ""
        
        let stream = AIService.shared.streamMessage(
            prompt,
            context: nil,
            images: [],
            maxTokens: nil,
            systemPrompt: "You are a helpful coding assistant. Be concise and direct."
        )
        
        for try await chunk in stream {
            fullResponse += chunk
        }
        
        return fullResponse
    }
    
    private func formatJSON(_ result: SubagentResult) -> String {
        let dict: [String: Any] = [
            "success": result.success,
            "output": result.output,
            "changes": result.changes.map { change in
                [
                    "file": change.file.path,
                    "description": change.description
                ]
            },
            "errors": result.errors
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "{}"
    }
    
    // MARK: - Help Output
    
    private func helpOutput() -> CLIOutput {
        let help = """
        LingCode CLI - AI Coding Assistant
        
        USAGE:
            lingcode [OPTIONS] <PROMPT>
            lingcode <COMMAND> [OPTIONS]
        
        COMMANDS:
            ask <question>      Ask a question (no file changes)
            review              Review current git changes
            commit              Create commit with AI message
            status              Show active agent status
            list                List recent agent sessions
            resume <id>         Resume an agent session
            cancel <id>         Cancel an agent task
        
        OPTIONS:
            -f, --file <path>   Include file in context (can repeat)
            -m, --model <name>  Specify AI model
            -p, --project <dir> Set project directory
            -y, --yes           Auto-apply changes without confirmation
            -q, --quiet         Minimal output
            --json              Output as JSON
            --max-steps <n>     Maximum agent steps (default: 50)
            -h, --help          Show this help
            -v, --version       Show version
        
        EXAMPLES:
            lingcode "fix all lint errors"
            lingcode -f src/main.swift "add error handling"
            lingcode ask "what does this function do?"
            lingcode commit
            lingcode --json status
        
        """
        
        return CLIOutput(exitCode: 0, stdout: help, stderr: "")
    }
    
    private func versionOutput() -> CLIOutput {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        
        return CLIOutput(exitCode: 0, stdout: "LingCode CLI v\(version) (build \(build))\n", stderr: "")
    }
}

// MARK: - CLI Entry Point (for separate command line tool target)
// Note: This struct is for a separate CLI target, not the main app
// To use: Create a separate target "LingCodeCLI" and add @main there

struct LingCodeCLI {
    static func runCLI() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = CLIAgentService.shared.parseArguments(args)
        let output = await CLIAgentService.shared.execute(command)
        
        if !output.stdout.isEmpty {
            print(output.stdout, terminator: "")
        }
        
        if !output.stderr.isEmpty {
            FileHandle.standardError.write(output.stderr.data(using: .utf8)!)
        }
        
        exit(output.exitCode)
    }
}
