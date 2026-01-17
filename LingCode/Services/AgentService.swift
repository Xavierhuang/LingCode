//
//  AgentService.swift
//  LingCode
//
//  Created for Phase 6: Autonomous "ReAct" Agent
//  Beats Cursor by self-correcting errors dynamically.
//

import Foundation
import Combine

// MARK: - Models

struct AgentTask: Identifiable {
    let id = UUID()
    let description: String
    let projectURL: URL?
    let startTime: Date
}

struct AgentStep: Identifiable {
    let id = UUID()
    let type: AgentStepType
    var description: String
    var status: AgentStepStatus
    var output: String?
    var result: String?
    var error: String?
    var timestamp: Date = Date()
}

enum AgentStepType {
    case thinking
    case terminal
    case codeGeneration
    case webSearch
    case fileOperation
    
    var icon: String {
        switch self {
        case .thinking: return "brain"
        case .terminal: return "terminal"
        case .codeGeneration: return "doc.text"
        case .webSearch: return "magnifyingglass"
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
}

struct AgentTaskResult {
    let success: Bool
    let error: String?
    let steps: [AgentStep]
}

struct AgentDecision: Codable, Equatable {
    let action: String
    let description: String
    let command: String?
    let query: String?
    let filePath: String?
    let code: String?
    let thought: String?
}

// MARK: - AgentService

class AgentService: ObservableObject {
    static let shared = AgentService()
    
    @Published var isRunning: Bool = false
    @Published var currentTask: AgentTask?
    @Published var steps: [AgentStep] = []
    
    // 🛑 Safety Brake State
    @Published var pendingApproval: AgentDecision?
    @Published var pendingApprovalReason: String?
    
    // Internal services - use ModernAIService via ServiceContainer
    private let aiService: AIProviderProtocol = ServiceContainer.shared.ai
    private let terminalService = TerminalExecutionService.shared
    private let webSearch = WebSearchService.shared
    
    private var isCancelled = false
    private var iterationCount = 0
    private let MAX_ITERATIONS = 20
    
    // Store context for resuming after approval
    private class PendingExecutionContext {
        let decision: AgentDecision
        let task: AgentTask
        let projectURL: URL?
        let originalContext: String?
        let images: [AttachedImage]
        let onStepUpdate: (AgentStep) -> Void
        let onComplete: (AgentTaskResult) -> Void
        let stepId: UUID
        
        init(decision: AgentDecision, task: AgentTask, projectURL: URL?, originalContext: String?, images: [AttachedImage], onStepUpdate: @escaping (AgentStep) -> Void, onComplete: @escaping (AgentTaskResult) -> Void, stepId: UUID) {
            self.decision = decision
            self.task = task
            self.projectURL = projectURL
            self.originalContext = originalContext
            self.images = images
            self.onStepUpdate = onStepUpdate
            self.onComplete = onComplete
            self.stepId = stepId
        }
    }
    private var pendingExecutionContext: PendingExecutionContext?
    
    private init() {}
    
    // MARK: - Public API
    
    func cancel() {
        isCancelled = true
        if let lastStep = steps.last, lastStep.status == .running {
            updateStep(lastStep.id, status: .cancelled)
        }
        pendingApproval = nil // Clear any pending approvals
        pendingApprovalReason = nil // Clear approval reason
        pendingExecutionContext = nil
    }
    
    func runTask(
        _ taskDescription: String,
        projectURL: URL?,
        context: String?,
        images: [AttachedImage] = [],
        onStepUpdate: @escaping (AgentStep) -> Void,
        onComplete: @escaping (AgentTaskResult) -> Void
    ) {
        guard !isRunning else { return }
        
        isCancelled = false
        isRunning = true
        steps = []
        iterationCount = 0
        pendingApproval = nil
        pendingApprovalReason = nil
        pendingExecutionContext = nil
        
        let task = AgentTask(description: taskDescription, projectURL: projectURL, startTime: Date())
        currentTask = task
        
        // Start the ReAct Loop
        runNextIteration(
            task: task,
            projectURL: projectURL,
            originalContext: context,
            images: images,
            onStepUpdate: onStepUpdate,
            onComplete: onComplete
        )
    }
    
    // MARK: - The "Brain" Loop
    
    private func runNextIteration(
        task: AgentTask,
        projectURL: URL?,
        originalContext: String?,
        images: [AttachedImage] = [],
        onStepUpdate: @escaping (AgentStep) -> Void,
        onComplete: @escaping (AgentTaskResult) -> Void
    ) {
        // 1. Safety Checks
        guard !isCancelled else {
            finalize(success: false, error: "Cancelled by user", onComplete: onComplete)
            return
        }
        
        if iterationCount >= MAX_ITERATIONS {
            finalize(success: false, error: "Max iterations reached", onComplete: onComplete)
            return
        }
        iterationCount += 1
        
        // 2. Build History (The "Memory")
        let history = steps.map { step in
            var historyLine = "Step: \(step.description)\nStatus: \(step.status)"
            if let output = step.output, !output.isEmpty {
                historyLine += "\nOutput: \(output.prefix(500))"
            }
            if let error = step.error {
                historyLine += "\nError: \(error)"
            }
            return historyLine
        }.joined(separator: "\n---\n")
        
        // 3. Prompt the LLM ("What should I do next?")
        let prompt = """
        You are an autonomous coding agent.
        Goal: \(task.description)
        
        History:
        \(history.isEmpty ? "No previous steps." : history)
        
        Analyze the history. If previous step failed, fix it.
        If task is done, return "DONE".
        Otherwise, determine the SINGLE next step.
        
        Respond ONLY with JSON:
        {
            "action": "code|terminal|search|done",
            "description": "Short description",
            "command": "shell command (if terminal)",
            "query": "search query (if search)",
            "filePath": "path (if code)",
            "code": "code content (if code)",
            "thought": "Why I am choosing this"
        }
        """
        
        // Add "Thinking" Step (Visual Feedback)
        let thinkingStep = AgentStep(
            type: .thinking,
            description: "Analyzing next step...",
            status: .running
        )
        addStep(thinkingStep, onUpdate: onStepUpdate)
        
        // Use ModernAIService with async/await
        Task { @MainActor in
            do {
                var accumulatedResponse = ""
                let stream = aiService.streamMessage(
                    prompt,
                    context: originalContext,
                    images: images,
                    maxTokens: nil,
                    systemPrompt: "You are an autonomous coding agent. Always respond with valid JSON only.",
                    tools: nil
                )
                
                // Process stream chunks
                for try await chunk in stream {
                    accumulatedResponse += chunk
                    // Update thinking step with partial response
                    self.updateStep(thinkingStep.id, output: accumulatedResponse)
                }
                
                // Remove "Thinking" placeholder
                self.removeStep(thinkingStep.id)
                
                // Parse Decision
                guard let decision = self.parseDecision(from: accumulatedResponse) else {
                    // Retry if JSON failed
                    let errorStep = AgentStep(
                        type: .thinking,
                        description: "Failed to parse decision, retrying...",
                        status: .failed,
                        error: "Invalid JSON response"
                    )
                    self.addStep(errorStep, onUpdate: onStepUpdate)
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    return
                }
                
                if decision.action.lowercased() == "done" {
                    self.finalize(success: true, onComplete: onComplete)
                    return
                }
                
                // 4. Create Actual Step
                let nextStep = AgentStep(
                    type: self.mapType(decision.action),
                    description: decision.description,
                    status: .running,
                    output: decision.thought // Show thought process initially
                )
                self.addStep(nextStep, onUpdate: onStepUpdate)
                
                // 🛑 SAFETY INTERCEPTION
                let safetyCheck = AgentSafetyGuard.shared.check(decision)
                
                switch safetyCheck {
                case .blocked(let reason):
                    // Blocked - mark as failed and continue loop
                    self.updateStep(nextStep.id, status: .failed, error: "Blocked: \(reason)")
                    onStepUpdate(nextStep)
                    // Continue loop - agent will see failure and try something else
                    self.runNextIteration(
                        task: task,
                        projectURL: projectURL,
                        originalContext: originalContext,
                        images: images,
                        onStepUpdate: onStepUpdate,
                        onComplete: onComplete
                    )
                    
                case .needsApproval(let reason):
                    // PAUSE and show approval UI
                    self.pendingApproval = decision
                    self.pendingApprovalReason = reason
                    // Store context for resuming after approval
                    self.pendingExecutionContext = PendingExecutionContext(
                        decision: decision,
                        task: task,
                        projectURL: projectURL,
                        originalContext: originalContext,
                        images: images,
                        onStepUpdate: onStepUpdate,
                        onComplete: onComplete,
                        stepId: nextStep.id
                    )
                    
                case .safe:
                    // Safe - execute immediately
                    self.executeDecision(
                        decision,
                        projectURL: projectURL,
                        onOutput: { output in
                            self.updateStep(nextStep.id, output: output)
                            onStepUpdate(nextStep)
                        },
                        onComplete: { success, output in
                            self.updateStep(
                                nextStep.id,
                                status: success ? .completed : .failed,
                                result: success ? "Success" : nil,
                                error: success ? nil : output
                            )
                            onStepUpdate(nextStep)
                            
                            // 6. LOOP (Recursive)
                            self.runNextIteration(
                                task: task,
                                projectURL: projectURL,
                                originalContext: originalContext,
                                images: images,
                                onStepUpdate: onStepUpdate,
                                onComplete: onComplete
                            )
                        }
                    )
                }
            } catch {
                self.finalize(success: false, error: error.localizedDescription, onComplete: onComplete)
            }
        }
    }
    
    // MARK: - Action Execution
    
    private func executeDecision(
        _ decision: AgentDecision,
        projectURL: URL?,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, String) -> Void
    ) {
        switch decision.action.lowercased() {
        case "terminal":
            guard let cmd = decision.command, !cmd.isEmpty else {
                onComplete(false, "No command provided")
                return
            }
            terminalService.execute(
                cmd,
                workingDirectory: projectURL,
                onOutput: { output in
                    onOutput(output)
                },
                onError: { error in
                    onOutput("Error: \(error)")
                },
                onComplete: { exitCode in
                    onComplete(exitCode == 0, "Exit code: \(exitCode)")
                }
            )
            
        case "code":
            guard let filePath = decision.filePath, let code = decision.code else {
                onComplete(false, "Missing filePath or code")
                return
            }
            
            // Write code to file
            let fullPath: URL
            if let projectURL = projectURL {
                fullPath = projectURL.appendingPathComponent(filePath)
            } else {
                fullPath = URL(fileURLWithPath: filePath)
            }
            
            do {
                // Create directory if needed
                let directory = fullPath.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                
                // Write file
                try code.write(to: fullPath, atomically: true, encoding: .utf8)
                onOutput("File written: \(filePath)")
                
                // IMPROVEMENT: Shadow Workspace - Validate compilation/lint before marking as success
                // This matches Cursor's approach of validating code before showing it to the user
                if let projectURL = projectURL {
                    validateCodeAfterWrite(fileURL: fullPath, projectURL: projectURL) { validationResult in
                        switch validationResult {
                        case .success:
                            onOutput("✅ Code validated successfully")
                            onComplete(true, "File written and validated successfully")
                        case .warnings(let messages):
                            onOutput("⚠️ Code written with warnings:\n\(messages.joined(separator: "\n"))")
                            onComplete(true, "File written with warnings")
                        case .errors(let messages):
                            onOutput("❌ Code written but has errors:\n\(messages.joined(separator: "\n"))")
                            // Still mark as completed (file was written) but report errors
                            onComplete(true, "File written but contains errors")
                        case .skipped:
                            // Validation not available or not applicable
                            onComplete(true, "File written successfully")
                        }
                    }
                } else {
                    onComplete(true, "File written successfully")
                }
            } catch {
                onComplete(false, "Failed to write file: \(error.localizedDescription)")
            }
            
        case "search":
            guard let query = decision.query, !query.isEmpty else {
                onComplete(false, "No search query provided")
                return
            }
            
            webSearch.search(query: query) { results in
                let summary = results.prefix(5).map { "• \($0.title): \($0.snippet.prefix(100))" }.joined(separator: "\n")
                onOutput("Search results:\n\(summary)")
                onComplete(true, "Found \(results.count) results")
            }
            
        default:
            onComplete(false, "Unknown action: \(decision.action)")
        }
    }
    
    // MARK: - Shadow Workspace Validation
    
    /// IMPROVEMENT: Validate code after writing (Shadow Workspace pattern)
    /// Matches Cursor's approach of validating code before marking as success
    private enum ValidationResult {
        case success
        case warnings([String])
        case errors([String])
        case skipped
    }
    
    private func validateCodeAfterWrite(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        // Use LinterService for validation
        let linterService = LinterService.shared
        
        linterService.validate(files: [fileURL], in: projectURL) { lintError in
            if let lintError = lintError {
                // Linter found issues
                switch lintError {
                case .issues(let messages):
                    // Check if any are errors vs warnings
                    let errors = messages.filter { $0.lowercased().contains("error") }
                    let warnings = messages.filter { !$0.lowercased().contains("error") }
                    
                    if !errors.isEmpty {
                        completion(.errors(errors))
                    } else if !warnings.isEmpty {
                        completion(.warnings(warnings))
                    } else {
                        completion(.success)
                    }
                }
            } else {
                // No lint errors (or linter not available) - check if it's a Swift file and try compilation
                if fileURL.pathExtension.lowercased() == "swift" {
                    self.validateSwiftCompilation(fileURL: fileURL, projectURL: projectURL, completion: completion)
                } else {
                    // For non-Swift files, if no linter errors, consider it successful
                    completion(.success)
                }
            }
        }
    }
    
    /// Validate Swift file compilation using swift build
    private func validateSwiftCompilation(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        // Check if it's a Swift Package or Xcode project
        let hasPackageSwift = FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path)
        let hasXcodeProject = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil)?.contains { url in
            (url as? URL)?.pathExtension == "xcodeproj"
        } ?? false
        
        guard hasPackageSwift || hasXcodeProject else {
            // Not a Swift project - skip validation
            completion(.skipped)
            return
        }
        
        // Run swift build to check for compilation errors
        let terminalService = TerminalExecutionService.shared
        terminalService.execute(
            "swift build 2>&1",
            workingDirectory: projectURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                if exitCode == 0 {
                    completion(.success)
                } else {
                    // Try to extract error messages from build output
                    // For now, just report that there are compilation errors
                    completion(.errors(["Compilation failed. Check build output for details."]))
                }
            }
        )
    }
    
    // MARK: - Helpers
    
    private func finalize(success: Bool, error: String? = nil, onComplete: @escaping (AgentTaskResult) -> Void) {
        DispatchQueue.main.async {
            self.isRunning = false
            let result = AgentTaskResult(success: success, error: error, steps: self.steps)
            self.currentTask = nil
            onComplete(result)
        }
    }
    
    private func addStep(_ step: AgentStep, onUpdate: @escaping (AgentStep) -> Void) {
        DispatchQueue.main.async {
            self.steps.append(step)
            onUpdate(step)
        }
    }
    
    private func updateStep(_ id: UUID, status: AgentStepStatus? = nil, result: String? = nil, error: String? = nil, output: String? = nil) {
        DispatchQueue.main.async {
            if let index = self.steps.firstIndex(where: { $0.id == id }) {
                var s = self.steps[index]
                if let st = status { s.status = st }
                if let r = result { s.result = r }
                if let e = error { s.error = e }
                if let o = output {
                    s.output = (s.output ?? "") + o
                }
                self.steps[index] = s
            }
        }
    }
    
    private func removeStep(_ id: UUID) {
        DispatchQueue.main.async {
            self.steps.removeAll { $0.id == id }
        }
    }
    
    private func parseDecision(from response: String) -> AgentDecision? {
        // Extract JSON from response (might be wrapped in markdown code blocks)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        
        // Try to find JSON object
        if let jsonStart = jsonString.range(of: "{"),
           let jsonEnd = jsonString.range(of: "}", options: .backwards, range: jsonStart.upperBound..<jsonString.endIndex) {
            jsonString = String(jsonString[jsonStart.lowerBound...jsonEnd.upperBound])
        }
        
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AgentDecision.self, from: data)
        } catch {
            print("Failed to parse AgentDecision: \(error)")
            return nil
        }
    }
    
    private func mapType(_ action: String) -> AgentStepType {
        switch action.lowercased() {
        case "terminal": return .terminal
        case "code": return .codeGeneration
        case "search": return .webSearch
        case "file": return .fileOperation
        default: return .thinking
        }
    }
    
    // 🛑 Resume after user approval
    func resumeWithApproval(_ approved: Bool) {
        guard let context = pendingExecutionContext else {
            return
        }
        
        let decision = context.decision
        let stepId = context.stepId
        
        // Clear pending state
        DispatchQueue.main.async {
            self.pendingApproval = nil
            self.pendingApprovalReason = nil
            self.pendingExecutionContext = nil
        }
        
        if approved {
            print("✅ Action Approved: \(decision.action) - \(decision.description)")
            // Execute the stored decision
            executeDecision(
                decision,
                projectURL: context.projectURL,
                onOutput: { output in
                    self.updateStep(stepId, output: output)
                    context.onStepUpdate(self.steps.first(where: { $0.id == stepId }) ?? AgentStep(
                        type: .thinking,
                        description: "",
                        status: .running
                    ))
                },
                onComplete: { success, output in
                    self.updateStep(
                        stepId,
                        status: success ? .completed : .failed,
                        result: success ? "Success" : nil,
                        error: success ? nil : output
                    )
                    if let step = self.steps.first(where: { $0.id == stepId }) {
                        context.onStepUpdate(step)
                    }
                    // Continue loop
                    self.runNextIteration(
                        task: context.task,
                        projectURL: context.projectURL,
                        originalContext: context.originalContext,
                        images: context.images,
                        onStepUpdate: context.onStepUpdate,
                        onComplete: context.onComplete
                    )
                }
            )
        } else {
            print("❌ Action Denied by user")
            // Mark step as failed
            updateStep(stepId, status: .failed, error: "Action denied by user")
            if let step = self.steps.first(where: { $0.id == stepId }) {
                context.onStepUpdate(step)
            }
            // Continue loop - agent will see the failure and try something else
            runNextIteration(
                task: context.task,
                projectURL: context.projectURL,
                originalContext: context.originalContext,
                images: context.images,
                onStepUpdate: context.onStepUpdate,
                onComplete: context.onComplete
            )
        }
    }
}

// MARK: - Safety Guard

enum SafetyCheckResult {
    case safe
    case needsApproval(reason: String)
    case blocked(reason: String)
}

class AgentSafetyGuard {
    static let shared = AgentSafetyGuard()
    
    private let dangerousCommands = [
        "rm", "del", "mkfs", "dd", "git push", "git reset", "sudo", "chmod", "format"
    ]
    
    private let blockedCommands = [
        "rm -rf /", "rm -rf /*", "mkfs", "dd if=/dev/zero", "format c:"
    ]
    
    func check(_ decision: AgentDecision) -> SafetyCheckResult {
        // 1. Check Terminal Commands
        if decision.action == "terminal", let cmd = decision.command?.lowercased() {
            // Check for completely blocked commands
            for blocked in blockedCommands {
                if cmd.contains(blocked.lowercased()) {
                    return .blocked(reason: "Catastrophic command detected: \(blocked)")
                }
            }
            
            // Check for commands that need approval
            for risk in dangerousCommands {
                if cmd.contains(risk.lowercased()) {
                    return .needsApproval(reason: "Risky command detected: \(risk)")
                }
            }
            
            // Check for destructive git operations
            if cmd.contains("git") {
                if cmd.contains("reset --hard") || cmd.contains("push --force") || cmd.contains("clean -fd") {
                    return .needsApproval(reason: "Destructive git operation")
                }
            }
        }
        
        // 2. Check File Edits (Protect sensitive config)
        if decision.action == "code", let path = decision.filePath?.lowercased() {
            let sensitivePatterns = [".env", "credentials", "secrets", "config.json", "package-lock.json", ".git/config"]
            for pattern in sensitivePatterns {
                if path.contains(pattern) {
                    return .needsApproval(reason: "Editing sensitive file: \(pattern)")
                }
            }
        }
        
        return .safe
    }
}
