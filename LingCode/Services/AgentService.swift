//
//  AgentService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

/// Agent Mode - Autonomous multi-step task completion like Cursor
class AgentService: ObservableObject {
    static let shared = AgentService()
    
    @Published var isRunning: Bool = false
    @Published var currentTask: AgentTask?
    @Published var taskHistory: [AgentTask] = []
    @Published var currentStep: AgentStep?
    @Published var steps: [AgentStep] = []
    
    private let aiService = AIService.shared
    private let terminalService = TerminalExecutionService.shared
    private let codeGenerator = CodeGeneratorService.shared
    private let webSearch = WebSearchService.shared
    
    private var isCancelled = false
    
    private init() {}
    
    // MARK: - Agent Execution
    
    /// Run an agent task
    func runTask(
        _ taskDescription: String,
        projectURL: URL?,
        context: String?,
        onStepUpdate: @escaping (AgentStep) -> Void,
        onComplete: @escaping (AgentTaskResult) -> Void
    ) {
        guard !isRunning else {
            onComplete(AgentTaskResult(success: false, error: "Agent is already running"))
            return
        }
        
        isCancelled = false
        isRunning = true
        steps = []
        
        let task = AgentTask(
            description: taskDescription,
            projectURL: projectURL,
            startTime: Date()
        )
        currentTask = task
        
        // Add planning step
        let planningStep = AgentStep(
            type: .planning,
            description: "Analyzing task and creating plan...",
            status: .running
        )
        addStep(planningStep, onUpdate: onStepUpdate)
        
        // Get AI to create a plan
        let planningPrompt = buildPlanningPrompt(taskDescription, context: context, projectURL: projectURL)
        
        aiService.sendMessage(
            planningPrompt,
            context: context,
            onResponse: { [weak self] response in
                guard let self = self, !self.isCancelled else { return }
                
                // Parse the plan
                let plan = self.parsePlan(from: response)
                
                // Update planning step
                self.updateStep(planningStep.id, status: .completed, result: "Created \(plan.count) step plan")
                onStepUpdate(self.steps.first { $0.id == planningStep.id }!)
                
                // Execute the plan
                self.executePlan(
                    plan,
                    projectURL: projectURL,
                    context: context,
                    onStepUpdate: onStepUpdate,
                    onComplete: { result in
                        self.isRunning = false
                        self.currentTask = nil
                        onComplete(result)
                    }
                )
            },
            onError: { error in
                self.updateStep(planningStep.id, status: .failed, error: error.localizedDescription)
                onStepUpdate(self.steps.first { $0.id == planningStep.id }!)
                self.isRunning = false
                onComplete(AgentTaskResult(success: false, error: error.localizedDescription))
            }
        )
    }
    
    /// Cancel the current task
    func cancel() {
        isCancelled = true
        aiService.cancelCurrentRequest()
        terminalService.cancel()
        
        if let currentStep = currentStep {
            updateStep(currentStep.id, status: .cancelled)
        }
        
        isRunning = false
        currentTask = nil
    }
    
    // MARK: - Plan Execution
    
    private func executePlan(
        _ plan: [PlanStep],
        projectURL: URL?,
        context: String?,
        onStepUpdate: @escaping (AgentStep) -> Void,
        onComplete: @escaping (AgentTaskResult) -> Void
    ) {
        executePlanStep(
            plan,
            index: 0,
            projectURL: projectURL,
            context: context,
            createdFiles: [],
            onStepUpdate: onStepUpdate,
            onComplete: onComplete
        )
    }
    
    private func executePlanStep(
        _ plan: [PlanStep],
        index: Int,
        projectURL: URL?,
        context: String?,
        createdFiles: [URL],
        onStepUpdate: @escaping (AgentStep) -> Void,
        onComplete: @escaping (AgentTaskResult) -> Void
    ) {
        guard !isCancelled else {
            onComplete(AgentTaskResult(success: false, error: "Task cancelled", createdFiles: createdFiles))
            return
        }
        
        guard index < plan.count else {
            // All steps completed
            onComplete(AgentTaskResult(success: true, createdFiles: createdFiles))
            return
        }
        
        let planStep = plan[index]
        let agentStep = AgentStep(
            type: planStep.type,
            description: planStep.description,
            status: .running
        )
        addStep(agentStep, onUpdate: onStepUpdate)
        currentStep = agentStep
        
        executeAction(
            planStep,
            projectURL: projectURL,
            context: context,
            onOutput: { output in
                self.updateStep(agentStep.id, output: output)
                onStepUpdate(self.steps.first { $0.id == agentStep.id }!)
            },
            onComplete: { success, newFiles, error in
                if success {
                    self.updateStep(agentStep.id, status: .completed, result: "Completed")
                } else {
                    self.updateStep(agentStep.id, status: .failed, error: error)
                }
                onStepUpdate(self.steps.first { $0.id == agentStep.id }!)
                
                var allCreatedFiles = createdFiles
                allCreatedFiles.append(contentsOf: newFiles)
                
                // Continue to next step (even on failure for non-critical steps)
                self.executePlanStep(
                    plan,
                    index: index + 1,
                    projectURL: projectURL,
                    context: context,
                    createdFiles: allCreatedFiles,
                    onStepUpdate: onStepUpdate,
                    onComplete: onComplete
                )
            }
        )
    }
    
    private func executeAction(
        _ step: PlanStep,
        projectURL: URL?,
        context: String?,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, [URL], String?) -> Void
    ) {
        switch step.type {
        case .codeGeneration:
            executeCodeGeneration(
                step.description,
                projectURL: projectURL,
                context: context,
                onOutput: onOutput,
                onComplete: onComplete
            )
            
        case .terminal:
            executeTerminalCommand(
                step.command ?? step.description,
                projectURL: projectURL,
                onOutput: onOutput,
                onComplete: onComplete
            )
            
        case .webSearch:
            executeWebSearch(
                step.query ?? step.description,
                onOutput: onOutput,
                onComplete: onComplete
            )
            
        case .fileOperation:
            executeFileOperation(
                step,
                projectURL: projectURL,
                onOutput: onOutput,
                onComplete: onComplete
            )
            
        case .thinking, .planning:
            // These are informational steps
            onComplete(true, [], nil)
        }
    }
    
    // MARK: - Action Implementations
    
    private func executeCodeGeneration(
        _ description: String,
        projectURL: URL?,
        context: String?,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, [URL], String?) -> Void
    ) {
        let prompt = """
        Generate code for: \(description)
        
        Requirements:
        - Provide complete, working code
        - Include file paths for each code block
        - Use the format: `path/to/file.ext`:
        ```language
        code
        ```
        """
        
        aiService.sendMessage(
            prompt,
            context: context,
            onResponse: { response in
                onOutput("AI generated code response")
                
                // Parse and create files
                let operations = self.codeGenerator.extractFileOperations(from: response, projectURL: projectURL)
                var createdFiles: [URL] = []
                
                for operation in operations {
                    let fileURL = URL(fileURLWithPath: operation.filePath)
                    do {
                        let directory = fileURL.deletingLastPathComponent()
                        if !FileManager.default.fileExists(atPath: directory.path) {
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        }
                        try (operation.content ?? "").write(to: fileURL, atomically: true, encoding: .utf8)
                        createdFiles.append(fileURL)
                        onOutput("Created: \(fileURL.lastPathComponent)")
                    } catch {
                        onOutput("Failed to create: \(fileURL.lastPathComponent)")
                    }
                }
                
                onComplete(true, createdFiles, nil)
            },
            onError: { error in
                onComplete(false, [], error.localizedDescription)
            }
        )
    }
    
    private func executeTerminalCommand(
        _ command: String,
        projectURL: URL?,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, [URL], String?) -> Void
    ) {
        onOutput("$ \(command)\n")
        
        terminalService.execute(
            command,
            workingDirectory: projectURL,
            environment: nil,
            onOutput: { output in
                onOutput(output)
            },
            onError: { error in
                onOutput(error)
            },
            onComplete: { exitCode in
                onComplete(exitCode == 0, [], exitCode != 0 ? "Exit code: \(exitCode)" : nil)
            }
        )
    }
    
    private func executeWebSearch(
        _ query: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, [URL], String?) -> Void
    ) {
        onOutput("Searching: \(query)\n")
        
        webSearch.search(query: query, maxResults: 3) { results in
            if results.isEmpty {
                onOutput("No results found\n")
            } else {
                for result in results {
                    onOutput("- \(result.title)\n  \(result.url)\n")
                }
            }
            onComplete(true, [], nil)
        }
    }
    
    private func executeFileOperation(
        _ step: PlanStep,
        projectURL: URL?,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, [URL], String?) -> Void
    ) {
        guard let filePath = step.filePath else {
            onComplete(false, [], "No file path specified")
            return
        }
        
        let fileURL: URL
        if filePath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: filePath)
        } else if let project = projectURL {
            fileURL = project.appendingPathComponent(filePath)
        } else {
            onComplete(false, [], "No project URL")
            return
        }
        
        do {
            if step.description.lowercased().contains("delete") {
                try FileManager.default.removeItem(at: fileURL)
                onOutput("Deleted: \(fileURL.lastPathComponent)")
                onComplete(true, [], nil)
            } else if step.description.lowercased().contains("create") {
                let directory = fileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
                onOutput("Created: \(fileURL.lastPathComponent)")
                onComplete(true, [fileURL], nil)
            } else {
                onComplete(true, [], nil)
            }
        } catch {
            onComplete(false, [], error.localizedDescription)
        }
    }
    
    // MARK: - Planning
    
    private func buildPlanningPrompt(_ task: String, context: String?, projectURL: URL?) -> String {
        var prompt = """
        You are an AI coding agent. Create a step-by-step plan to complete this task:
        
        TASK: \(task)
        
        """
        
        if let project = projectURL {
            prompt += "PROJECT: \(project.path)\n\n"
        }
        
        prompt += """
        Respond with a JSON plan in this format:
        ```json
        {
          "steps": [
            {
              "type": "codeGeneration|terminal|webSearch|fileOperation",
              "description": "What this step does",
              "command": "command to run (for terminal type)",
              "query": "search query (for webSearch type)",
              "filePath": "file path (for fileOperation type)"
            }
          ]
        }
        ```
        
        Available step types:
        - codeGeneration: Generate code files
        - terminal: Run shell commands (npm install, pip install, etc.)
        - webSearch: Search the web for information
        - fileOperation: Create, delete, or modify files
        
        Create a practical, executable plan.
        """
        
        return prompt
    }
    
    private func parsePlan(from response: String) -> [PlanStep] {
        // Try to extract JSON from response
        let jsonPattern = #"```json\s*([\s\S]*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
           let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
           match.numberOfRanges > 1,
           let jsonRange = Range(match.range(at: 1), in: response) {
            
            let jsonString = String(response[jsonRange])
            
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let stepsArray = json["steps"] as? [[String: Any]] {
                
                return stepsArray.compactMap { stepDict -> PlanStep? in
                    guard let typeString = stepDict["type"] as? String,
                          let description = stepDict["description"] as? String else {
                        return nil
                    }
                    
                    let type: AgentStepType
                    switch typeString.lowercased() {
                    case "codegeneration", "code": type = .codeGeneration
                    case "terminal", "command", "shell": type = .terminal
                    case "websearch", "search", "web": type = .webSearch
                    case "fileoperation", "file": type = .fileOperation
                    default: type = .thinking
                    }
                    
                    return PlanStep(
                        type: type,
                        description: description,
                        command: stepDict["command"] as? String,
                        query: stepDict["query"] as? String,
                        filePath: stepDict["filePath"] as? String
                    )
                }
            }
        }
        
        // Fallback: create a simple code generation step
        return [
            PlanStep(type: .codeGeneration, description: "Generate code for the task")
        ]
    }
    
    // MARK: - Step Management
    
    private func addStep(_ step: AgentStep, onUpdate: @escaping (AgentStep) -> Void) {
        DispatchQueue.main.async {
            self.steps.append(step)
            onUpdate(step)
        }
    }
    
    private func updateStep(
        _ id: UUID,
        status: AgentStepStatus? = nil,
        result: String? = nil,
        error: String? = nil,
        output: String? = nil
    ) {
        DispatchQueue.main.async {
            if let index = self.steps.firstIndex(where: { $0.id == id }) {
                var step = self.steps[index]
                if let status = status { step.status = status }
                if let result = result { step.result = result }
                if let error = error { step.error = error }
                if let output = output { step.output = (step.output ?? "") + output }
                self.steps[index] = step
            }
        }
    }
}

// MARK: - Supporting Types

struct AgentTask: Identifiable {
    let id = UUID()
    let description: String
    let projectURL: URL?
    let startTime: Date
    var endTime: Date?
}

struct AgentStep: Identifiable {
    let id = UUID()
    let type: AgentStepType
    let description: String
    var status: AgentStepStatus
    var result: String?
    var error: String?
    var output: String?
}

enum AgentStepType: String {
    case planning = "Planning"
    case thinking = "Thinking"
    case codeGeneration = "Code Generation"
    case terminal = "Terminal"
    case webSearch = "Web Search"
    case fileOperation = "File Operation"
    
    var icon: String {
        switch self {
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "brain.head.profile"
        case .codeGeneration: return "doc.text"
        case .terminal: return "terminal"
        case .webSearch: return "globe"
        case .fileOperation: return "folder"
        }
    }
}

enum AgentStepStatus {
    case pending
    case running
    case completed
    case failed
    case cancelled
    
    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "slash.circle"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "gray"
        case .running: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }
}

struct PlanStep {
    let type: AgentStepType
    let description: String
    var command: String?
    var query: String?
    var filePath: String?
}

struct AgentTaskResult {
    let success: Bool
    var error: String?
    var createdFiles: [URL] = []
}

