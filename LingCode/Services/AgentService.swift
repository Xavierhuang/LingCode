//
//  AgentService.swift
//  LingCode
//
//  Autonomous ReAct agent: orchestrates task loop, execution, validation, and error enrichment.
//

import Foundation
import Combine

// MARK: - AgentService

@MainActor
class AgentService: ObservableObject, Identifiable {
    let id = UUID()
    let agentName: String
    
    @Published var isRunning: Bool = false
    @Published var currentTask: AgentTask?
    @Published var steps: [AgentStep] = []
    @Published var streamingText: String = ""
    @Published var pendingApproval: AgentDecision?
    @Published var pendingApprovalReason: String?
    
    // Services
    private let aiService: AIProviderProtocol = ServiceContainer.shared.ai
    let terminalService = TerminalExecutionService.shared
    let webSearch = WebSearchService.shared
    
    // State
    private var isCancelled = false
    private var iterationCount = 0
    private let maxIterations = AgentConfiguration.maxIterations
    private var currentExecutionTask: Task<Void, Never>?
    private var currentThinkingStep: AgentStep?
    private var currentActionStep: AgentStep?
    private var lastUIUpdateTime: Date = .distantPast
    
    // Loop detection
    private var actionHistory: Set<String> = []
    private var failedActions: Set<String> = []
    private var recentActions: [String] = []
    private var recentlyWrittenFiles: Set<String> = []
    private var searchQueries: [String] = []  // Track search queries to detect loops
    private var filesReadThisTask: [String: Int] = [:]  // Track how many times each file was read
    private var lastFileContentByPath: [String: String] = [:]  // Cache last read content so blocked repeated reads still get content
    private let maxRecentActions = 5
    private let maxDoneRejectionsNoWrites = 1
    private var doneRejectedNoWritesCount = 0
    private var noToolUseCount = 0
    private let maxNoToolUseRetries = 2
    private let maxRepeatedSearches = 2  // Stop after 2 searches for same/similar query
    private let maxRepeatedFileReads = 1  // Allow only 1 read per file; serve cached content on repeat
    private var incompleteWriteRetryCount = 0  // Retry once when write_file stream ends early
    private var currentTaskStepStartIndex: Int = 0  // Index of first step of current task (for continuous conversation)

    // Approval context
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
            self.decision = decision; self.task = task; self.projectURL = projectURL; self.originalContext = originalContext
            self.images = images; self.onStepUpdate = onStepUpdate; self.onComplete = onComplete; self.stepId = stepId
        }
    }
    private var pendingExecutionContext: PendingExecutionContext?
    
    init(agentName: String = "Assistant") {
        self.agentName = agentName
    }
    
    // MARK: - Public API
    
    func cancel() {
        isCancelled = true
        isRunning = false
        streamingText = ""
        currentExecutionTask?.cancel()
        currentExecutionTask = nil
        actionHistory.removeAll()
        failedActions.removeAll()
        recentActions.removeAll()
        recentlyWrittenFiles.removeAll()
        searchQueries.removeAll()
        filesReadThisTask.removeAll()
        lastFileContentByPath.removeAll()
        incompleteWriteRetryCount = 0
        clearThinkingStep()
        for step in steps where step.status == .running {
            updateStep(step.id, status: .cancelled)
        }
        pendingApproval = nil
        pendingApprovalReason = nil
        pendingExecutionContext = nil
    }
    
    func runTask(_ taskDescription: String, projectURL: URL?, context: String?, images: [AttachedImage] = [], onStepUpdate: @escaping (AgentStep) -> Void, onComplete: @escaping (AgentTaskResult) -> Void) {
        guard !isRunning else {
            print("[AgentService] Already running, ignoring runTask call")
            return
        }
        
        print("[AgentService] Starting task: \(taskDescription.prefix(100))...")
        let task = AgentTask(description: taskDescription, projectURL: projectURL, startTime: Date())
        resetForNewTask(task)
        AgentHistoryService.shared.saveAgentTask(task, steps: [], result: nil, status: .running)

        // Set project URL for hooks
        HooksService.shared.setProjectURL(projectURL)

        var enrichedContext = context ?? ""
        if let projectURL = projectURL, isVagueTask(taskDescription) {
            let files = listProjectFiles(at: projectURL, maxDepth: 2)
            if !files.isEmpty {
                enrichedContext = "Project files:\n\(files.prefix(30).joined(separator: "\n"))\n\n\(enrichedContext)"
            }
        }

        // Fire sessionStart hook — may inject additional context
        Task { @MainActor in
            if let additionalContext = await HooksService.shared.fireSessionStart(
                task: taskDescription, mode: "agent"
            ), !additionalContext.isEmpty {
                enrichedContext += "\n\n\(additionalContext)"
            }
            self.runNextIteration(task: task, projectURL: projectURL, originalContext: enrichedContext.isEmpty ? nil : enrichedContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
        }
    }
    
    func resumeWithApproval(_ approved: Bool) {
        guard let context = pendingExecutionContext else { return }
        let decision = context.decision
        let stepId = context.stepId
        
        pendingApproval = nil
        pendingApprovalReason = nil
        pendingExecutionContext = nil
        AgentCoordinator.shared.clearApproval(agentId: self.id)
        
        if approved {
            executeDecision(decision, toolCall: nil, agentTaskId: context.task.id, projectURL: context.projectURL, onOutput: { output in
                self.updateStep(stepId, output: output, append: true)
                context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
            }, onComplete: { success, output, originalContent in
                self.updateStep(stepId, status: success ? .completed : .failed, error: success ? nil : output, originalContent: originalContent)
                context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
                self.runNextIteration(task: context.task, projectURL: context.projectURL, originalContext: context.originalContext, images: context.images, onStepUpdate: context.onStepUpdate, onComplete: context.onComplete)
            })
        } else {
            updateStep(stepId, status: .failed, error: "Action denied by user")
            context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
            runNextIteration(task: context.task, projectURL: context.projectURL, originalContext: context.originalContext, images: context.images, onStepUpdate: context.onStepUpdate, onComplete: context.onComplete)
        }
    }

    // MARK: - Core Loop

    private func runNextIteration(task: AgentTask, projectURL: URL?, originalContext: String?, images: [AttachedImage] = [], onStepUpdate: @escaping (AgentStep) -> Void, onComplete: @escaping (AgentTaskResult) -> Void, isRetry: Bool = false) {
        // Don't start new iteration if already stopped/cancelled
        guard isRunning && !isCancelled else {
            print("[AgentService] Skipping iteration - agent not running or cancelled")
            return
        }
        
        // Ensure previous action is complete before starting new iteration
        guard currentActionStep == nil else {
            // Previous step still running - this shouldn't happen, but guard against it
            print("[AgentService] Skipping iteration - action still in progress")
            return
        }
        
        if isRetry {
            print("[AgentService] Retrying iteration after incomplete write_file response")
        } else {
            iterationCount += 1
            incompleteWriteRetryCount = 0
        }
        streamingText = ""
        
        guard !shouldAbortIteration(projectURL: projectURL, onComplete: onComplete) else { return }
        
        let thinkingStep = AgentStep(type: .thinking, description: "Analyzing next step...", status: .running)
        currentThinkingStep = thinkingStep
        addStep(thinkingStep, onUpdate: onStepUpdate)
        
        currentExecutionTask = Task {
            do {
                guard !isCancelled else {
                    self.clearThinkingStep()
                    finalize(success: false, error: "Cancelled by user", projectURL: projectURL, onComplete: onComplete)
                    return
                }
                
                let history = await self.buildHistorySnapshot()
                let normalizePath: (String) -> String = { path in AgentLoopDetector.normalizeFilePath(path, projectURL: projectURL) }
                let currentSteps = self.currentTaskSteps
                let filesRead = AgentStepHelpers.filesRead(from: currentSteps, normalizePath: normalizePath)
                let filesWrittenCount = AgentStepHelpers.countFilesWritten(currentSteps)
                let agentMemory = (projectURL != nil) ? AgentMemoryService.shared.readMemory(for: projectURL!) : ""
                
                // Always gather project structure so the AI knows boundaries (not just for vague tasks)
                let projectStructure: String? = projectURL.map { url in
                    let files = self.listProjectFiles(at: url, maxDepth: 2)
                    let list = files.prefix(50).joined(separator: "\n")
                    return list.isEmpty ? nil : "Files and folders:\n\(list)"
                } ?? nil
                
                let requiresModifications = AgentTaskIntent.taskRequiresModifications(task.description)
                let loopDetectionHint = AgentLoopDetector.buildLoopDetectionHint(failedActions: self.failedActions)
                let noFilesWrittenYet = requiresModifications && filesWrittenCount == 0 && self.doneRejectedNoWritesCount > 0
                let (previousTaskDescription, lastTaskOutcome) = self.previousTaskContext
                let prompt = AgentPromptBuilder.buildPrompt(task: task, history: history, filesRead: filesRead, agentMemory: agentMemory, loopDetectionHint: loopDetectionHint, requiresModifications: requiresModifications, noFilesWrittenYet: noFilesWrittenYet, iterationCount: self.iterationCount, filesWrittenCount: filesWrittenCount, projectStructure: projectStructure, previousTaskDescription: previousTaskDescription, lastTaskOutcome: lastTaskOutcome)
                
                var agentTools: [AITool] = [.runTerminalCommand(), .searchReplace(), .writeFile(), .codebaseSearch(), .searchWeb(), .readFile(), .readDirectory(), .browsePage(), .browserClick(), .browserType(), .spawnSubagent(), .done()]
                
                // Dynamic tool filtering to prevent loops
                if self.iterationCount > 3 && !filesRead.isEmpty && filesWrittenCount == 0 && requiresModifications {
                    agentTools.removeAll { ["codebase_search", "search_web", "read_directory", "read_file"].contains($0.name) }
                }
                
                let forceToolName = (self.iterationCount >= 8 && filesWrittenCount == 0 && requiresModifications) ? "write_file" : nil
                
                print("[AgentService] Calling AI with \(agentTools.count) tools, forceToolName: \(forceToolName ?? "none")")
                // Use higher max_tokens when tools are present so the model can complete large write_file payloads (avoids stream ending before TOOL_CALL content)
                let maxTokensForRequest = agentTools.isEmpty ? nil : 32768
                let stream = aiService.streamMessage(prompt, context: originalContext, images: images, maxTokens: maxTokensForRequest, systemPrompt: nil, tools: agentTools, forceToolName: forceToolName)
                
                var accumulatedResponse = ""
                var detectedToolCalls: [ToolCall] = []
                var chunkCount = 0
                var drainingStream = false
                
                for try await chunk in stream {
                    chunkCount += 1
                    if isCancelled || Task.isCancelled {
                        print("[AgentService] Breaking due to cancellation")
                        break
                    }
                    if drainingStream {
                        accumulatedResponse += chunk
                        let (_, toolCalls) = ToolCallHandler.shared.processChunk(chunk, projectURL: projectURL)
                        if !toolCalls.isEmpty { detectedToolCalls.append(contentsOf: toolCalls) }
                        continue
                    }
                    accumulatedResponse += chunk
                    
                    // Debug: log first few chunks
                    if chunkCount <= 5 {
                        let preview = chunk.prefix(100).replacingOccurrences(of: "\n", with: "\\n")
                        print("[AgentService] Chunk \(chunkCount): \(preview)...")
                    }
                    
                    // Handle heartbeat - convert thinking step to action step
                    // Only process the FIRST tool starting marker, ignore subsequent ones
                    // This ensures one tool executes at a time
                    if chunk.contains("TOOL_STARTING:") && self.currentActionStep == nil {
                        if let range = chunk.range(of: "TOOL_STARTING:"),
                           let endRange = chunk.range(of: "\n", range: range.upperBound..<chunk.endIndex) {
                            let toolName = String(chunk[range.upperBound..<endRange.lowerBound])
                            await MainActor.run {
                                if let thinkingStep = self.currentThinkingStep,
                                   let idx = self.steps.firstIndex(where: { $0.id == thinkingStep.id }) {
                                    var updated = self.steps[idx]
                                    updated.type = AgentStepHelpers.mapType(toolName)
                                    updated.description = "Executing \(toolName)..."
                                    updated.streamingCode = (toolName == "write_file") ? "" : nil
                                    self.steps[idx] = updated
                                    self.currentActionStep = updated
                                    self.currentThinkingStep = nil
                                    if toolName == "write_file" {
                                        print("[AgentService] Waiting for write_file content from API (may take 20-60s for large files)...")
                                    }
                                }
                            }
                        }
                        continue
                    }
                    
                    // Streaming write_file preview (from AIService partial_json) - throttled so UI stays responsive
                    if chunk.contains("WRITE_FILE_PREVIEW:"), let activeStep = self.currentActionStep, activeStep.type == .codeGeneration {
                        for line in chunk.components(separatedBy: .newlines) {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("WRITE_FILE_PREVIEW:") {
                                let b64 = String(trimmed.dropFirst("WRITE_FILE_PREVIEW:".count))
                                if let data = Data(base64Encoded: b64), let preview = String(data: data, encoding: .utf8), !preview.isEmpty {
                                    let now = Date()
                                    if now.timeIntervalSince(lastUIUpdateTime) > 0.12 {
                                        let stepId = activeStep.id
                                        let previewCode = preview
                                        DispatchQueue.main.async {
                                            self.updateStepStreamingCode(stepId, code: previewCode)
                                            self.lastUIUpdateTime = now
                                        }
                                    }
                                }
                                break
                            }
                        }
                    }
                    
                    // Throttled live code updates
                    if let activeStep = self.currentActionStep, activeStep.type == .codeGeneration {
                        if let content = self.extractPartialContent(from: accumulatedResponse) {
                            let now = Date()
                            if now.timeIntervalSince(lastUIUpdateTime) > 0.05 {
                                let stepId = activeStep.id
                                let contentCode = content
                                DispatchQueue.main.async {
                                    self.updateStepStreamingCode(stepId, code: contentCode)
                                    self.lastUIUpdateTime = now
                                }
                            }
                        }
                    }
                    
                    // Standard UI update (defer to avoid publishing during view update)
                    let response = accumulatedResponse
                    let thinkingId = self.currentThinkingStep?.id
                    DispatchQueue.main.async {
                        self.streamingText = response
                        if self.currentActionStep == nil, let id = thinkingId {
                            self.updateStep(id, output: response, append: false)
                        }
                    }
                    
                    let (_, toolCalls) = ToolCallHandler.shared.processChunk(chunk, projectURL: projectURL)
                    if !toolCalls.isEmpty {
                        print("[AgentService] Detected \(toolCalls.count) tool calls: \(toolCalls.map { $0.name })")
                        detectedToolCalls.append(contentsOf: toolCalls)
                        let hasWriteFile = toolCalls.contains { $0.name == "write_file" }
                        if !hasWriteFile {
                            print("[AgentService] Have complete non-write tool call, draining stream to avoid cancellation")
                            drainingStream = true
                        }
                    }
                }
                
                print("[AgentService] Stream ended, received \(chunkCount) chunks, accumulated \(accumulatedResponse.count) chars")
                self.clearThinkingStep()
                
                // Flush any remaining tool calls - this often contains the complete content
                let flushedToolCalls = ToolCallHandler.shared.flush()
                
                // Prefer flushed tool calls as they're more complete
                // The flush() call returns fully parsed tool calls with all content
                var allToolCalls = flushedToolCalls
                if allToolCalls.isEmpty {
                    allToolCalls = detectedToolCalls
                } else {
                    // If we have flushed calls, merge with detected ones (avoid duplicates)
                    for tc in detectedToolCalls {
                        if !allToolCalls.contains(where: { $0.id == tc.id }) {
                            allToolCalls.append(tc)
                        }
                    }
                }
                
                guard !allToolCalls.isEmpty else {
                    // Stream ended without any complete tool call (e.g. cancelled or incomplete write_file). Defer to avoid "Publishing changes from within view updates".
                    let taskCopy = task
                    let projectURLCopy = projectURL
                    let originalContextCopy = originalContext
                    let imagesCopy = images
                    DispatchQueue.main.async {
                        let stuck = self.currentActionStep
                        if let stuck = stuck, let idx = self.steps.firstIndex(where: { $0.id == stuck.id }) {
                            self.steps[idx].status = .failed
                            self.steps[idx].error = "Incomplete response from AI (stream ended early)"
                            print("[AgentService] Clearing stuck action step (no tool call received)")
                        }
                        self.currentActionStep = nil
                        if stuck?.type == .codeGeneration && self.incompleteWriteRetryCount < 1 {
                            self.incompleteWriteRetryCount += 1
                            self.runNextIteration(task: taskCopy, projectURL: projectURLCopy, originalContext: originalContextCopy, images: imagesCopy, onStepUpdate: onStepUpdate, onComplete: onComplete, isRetry: true)
                        } else {
                            self.runNextIteration(task: taskCopy, projectURL: projectURLCopy, originalContext: originalContextCopy, images: imagesCopy, onStepUpdate: onStepUpdate, onComplete: onComplete)
                        }
                    }
                    return
                }

                // Process all tool calls in sequence (batch execution). Defer to avoid "Publishing changes from within view updates".
                let toolCallsCopy = allToolCalls
                Task { @MainActor in
                    await self.processToolCallBatch(
                        toolCalls: toolCallsCopy,
                        task: task,
                        projectURL: projectURL,
                        originalContext: originalContext,
                        images: images,
                        onStepUpdate: onStepUpdate,
                        onComplete: onComplete
                    )
                }

            } catch {
                print("[AgentService] Error in iteration: \(error.localizedDescription)")
                self.finalize(success: false, error: error.localizedDescription, projectURL: projectURL, onComplete: onComplete)
            }
        }
    }

    // MARK: - Decision Execution (ToolCall -> AgentDecision inlined from AgentToolCallConverter)
    
    private func convertToolCallToDecision(_ toolCall: ToolCall) -> AgentDecision? {
        let input = toolCall.input
        switch toolCall.name {
        case "done":
            let summary = input["summary"]?.value as? String
            return AgentDecision(action: "done", description: "Task Complete", command: nil, query: nil, filePath: nil, code: nil, thought: summary)
        case "run_terminal_command":
            guard let cmd = input["command"]?.value as? String else { return nil }
            return AgentDecision(action: "terminal", description: "Exec: \(cmd)", command: cmd, query: nil, filePath: nil, code: nil, thought: nil)
        case "write_file":
            let filePath: String? = input["file_path"]?.value as? String ?? input["path"]?.value as? String
            let content = input["content"]?.value as? String
            guard let path = filePath, let fileContent = content else { return nil }
            return AgentDecision(action: "code", description: "Write: \(path)", command: nil, query: nil, filePath: path, code: fileContent, thought: nil)
        case "search_replace":
            let filePath: String? = input["file_path"]?.value as? String ?? input["path"]?.value as? String
            guard let path = filePath else { return nil }
            return AgentDecision(action: "search_replace", description: "Replace in \(path)", command: nil, query: nil, filePath: path, code: nil, thought: nil)
        case "codebase_search", "search_web":
            guard let q = input["query"]?.value as? String else { return nil }
            return AgentDecision(action: "search", description: "Search: \(q)", command: nil, query: q, filePath: nil, code: nil, thought: nil)
        case "read_file":
            let filePath: String? = input["file_path"]?.value as? String ?? input["path"]?.value as? String
            guard let path = filePath else { return nil }
            return AgentDecision(action: "file", description: "Read: \(path)", command: nil, query: nil, filePath: path, code: nil, thought: nil)
        case "read_directory":
            let path: String? = input["directory_path"]?.value as? String ?? input["path"]?.value as? String ?? input["folder"]?.value as? String
            guard let directoryPath = path else { return nil }
            let recursive = (input["recursive"]?.value as? Bool) ?? false
            return AgentDecision(action: "directory", description: "Read: \(directoryPath)", command: nil, query: nil, filePath: directoryPath, code: nil, thought: recursive ? "recursive" : nil)
        case "spawn_subagent":
            let type = (input["subagent_type"]?.value as? String) ?? "coder"
            let desc = (input["description"]?.value as? String) ?? ""
            return AgentDecision(action: "spawn_subagent", description: "Delegate to \(type): \(desc.prefix(50))\(desc.count > 50 ? "..." : "")", command: nil, query: nil, filePath: nil, code: nil, thought: desc)
        default:
            return nil
        }
    }

    /// Process multiple tool calls from one API response in sequence; chains to next on each completion.
    private func processToolCallBatch(
        toolCalls: [ToolCall],
        startIndex: Int = 0,
        task: AgentTask,
        projectURL: URL?,
        originalContext: String?,
        images: [AttachedImage],
        onStepUpdate: @escaping (AgentStep) -> Void,
        onComplete: @escaping (AgentTaskResult) -> Void
    ) async {
        guard startIndex < toolCalls.count else {
            runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
            return
        }
        let tc = toolCalls[startIndex]
        guard let decision = convertToolCallToDecision(tc) else {
            await processToolCallBatch(toolCalls: toolCalls, startIndex: startIndex + 1, task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
            return
        }
        let isDone = decision.action.lowercased() == "done"
        let step: AgentStep = {
            if startIndex == 0, let existing = currentActionStep, let idx = steps.firstIndex(where: { $0.id == existing.id }) {
                steps[idx].description = decision.displayDescription
                steps[idx].output = decision.thought
                steps[idx].targetFilePath = decision.filePath
                if let code = decision.code { steps[idx].streamingCode = code }
                currentActionStep = nil
                return steps[idx]
            }
            let newStep = AgentStep(type: AgentStepHelpers.mapType(decision.action), description: decision.displayDescription, status: .running, output: decision.thought, streamingCode: decision.code, targetFilePath: decision.filePath)
            addStep(newStep, onUpdate: onStepUpdate)
            return newStep
        }()
        if isDone {
            updateStep(step.id, status: .completed, output: decision.thought)
            print("[AgentService] Done action completed - finalizing task")
            finalize(success: true, error: nil, projectURL: projectURL, summary: decision.thought, onComplete: onComplete)
            return
        }
        let replaceOld = tc.input["old_string"]?.value as? String
        let replaceNew = tc.input["new_string"]?.value as? String

        // ── Safety check ───────────────────────────────────────────────────
        let safetyResult = AgentSafetyGuard.shared.check(decision)
        switch safetyResult {
        case .blocked(let reason):
            updateStep(step.id, status: .failed, error: "Blocked: \(reason)")
            await processToolCallBatch(toolCalls: toolCalls, startIndex: startIndex + 1, task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
            return
        case .needsApproval(let reason):
            // Pause and ask the user
            pendingApproval = decision
            pendingApprovalReason = reason
            pendingExecutionContext = PendingExecutionContext(
                decision: decision,
                task: task,
                projectURL: projectURL,
                originalContext: originalContext,
                images: images,
                onStepUpdate: onStepUpdate,
                onComplete: onComplete,
                stepId: step.id
            )
            AgentCoordinator.shared.notifyNeedsApproval(agentId: self.id)
            return
        case .safe:
            break
        }

        // ── preToolUse hook ────────────────────────────────────────────────
        let hookDecision = await HooksService.shared.preToolUse(
            toolName: tc.name,
            toolInput: Dictionary(uniqueKeysWithValues: tc.input.map { ($0.key, $0.value.value) })
        )
        switch hookDecision {
        case .deny(let reason):
            updateStep(step.id, status: .failed, error: "Hook denied: \(reason)")
            await processToolCallBatch(toolCalls: toolCalls, startIndex: startIndex + 1, task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
            return
        default:
            break
        }
        executeDecision(decision, toolCall: tc, agentTaskId: task.id, projectURL: projectURL, onOutput: { output in
            DispatchQueue.main.async { self.updateStep(step.id, output: output, append: true) }
        }, onComplete: { success, output, originalContent in
            DispatchQueue.main.async {
                self.updateStep(step.id, status: success ? .completed : .failed, error: success ? nil : output, originalContent: originalContent, replaceOldString: replaceOld, replaceNewString: replaceNew)
                if !success {
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    return
                }
                Task { @MainActor in
                    await self.processToolCallBatch(toolCalls: toolCalls, startIndex: startIndex + 1, task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                }
            }
        })
    }
    
    func executeDecision(_ decision: AgentDecision, toolCall: ToolCall?, agentTaskId: UUID?, projectURL: URL?, onOutput: @escaping (String) -> Void, onComplete: @escaping (Bool, String, String?) -> Void) {
        switch decision.action.lowercased() {
        case "done":
            let summary = decision.thought ?? "Task completed successfully"
            onOutput(summary)
            onComplete(true, summary, nil)

        case "terminal":
            guard let cmd = decision.command, !cmd.isEmpty else {
                onComplete(false, "No command provided", nil)
                return
            }
            // beforeShellExecution hook
            Task { @MainActor in
                let hookResult = await HooksService.shared.beforeShellExecution(command: cmd, cwd: projectURL)
                switch hookResult {
                case .deny(let reason):
                    onOutput("Hook denied: \(reason)")
                    onComplete(false, "Denied by hook: \(reason)", nil)
                default:
                    let start = Date()
                    self.terminalService.execute(cmd, workingDirectory: projectURL,
                        onOutput: { onOutput($0) },
                        onError: { onOutput("Error: \($0)") },
                        onComplete: { code in
                            let ms = Int(Date().timeIntervalSince(start) * 1000)
                            // afterShellExecution hook (fire-and-forget)
                            // We don't have full output here so pass the exit code as output
                            HooksService.shared.afterShellExecution(
                                command: cmd, output: "Exit code: \(code)", durationMs: ms
                            )
                            onComplete(code == 0, "Exit code: \(code)", nil)
                        }
                    )
                }
            }

        case "search_replace":
            guard let call = toolCall else {
                onComplete(false, "No tool call for search_replace", nil)
                return
            }
            if let projectURL = projectURL { ToolExecutionService.shared.setProjectURL(projectURL) }
            ToolExecutionService.shared.setAgentRunContext(agentTaskId: agentTaskId)
            Task {
                do {
                    let result = try await ToolExecutionService.shared.executeToolCall(call)
                    await MainActor.run {
                        onOutput(result.content)
                        onComplete(!result.isError, result.content, nil)
                    }
                } catch {
                    await MainActor.run {
                        onOutput("Error: \(error.localizedDescription)")
                        onComplete(false, error.localizedDescription, nil)
                    }
                }
            }

        case "code":
            guard let filePath = decision.filePath, let code = decision.code else {
                onComplete(false, "Missing filePath or code", nil)
                return
            }

            let fullPath = projectURL?.appendingPathComponent(filePath) ?? URL(fileURLWithPath: filePath)

            do {
                try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

                let fileExisted = FileManager.default.fileExists(atPath: fullPath.path)

                // Idempotency check
                if fileExisted, let existingContent = try? String(contentsOf: fullPath, encoding: .utf8) {
                    if existingContent.trimmingCharacters(in: .whitespacesAndNewlines) == code.trimmingCharacters(in: .whitespacesAndNewlines) {
                        onOutput("File '\(filePath)' is already up-to-date.\n\n--- \(filePath) ---\n\(existingContent)\n--- End of \(filePath) ---")
                        onComplete(true, "Content matches existing file.", nil)
                        return
                    }
                }

                let originalContent = fileExisted ? (try? String(contentsOf: fullPath, encoding: .utf8)) : nil
                try code.write(to: fullPath, atomically: true, encoding: .utf8)
                onOutput("File written: \(filePath)\n\n--- \(filePath) ---\n\(code)\n--- End of \(filePath) ---")

                NotificationCenter.default.post(name: NSNotification.Name(fileExisted ? "FileUpdated" : "FileCreated"), object: nil, userInfo: ["fileURL": fullPath, "filePath": filePath, "content": code, "originalContent": originalContent ?? ""])

                if let projectURL = projectURL {
                    AgentValidationService.shared.validateCodeAfterWrite(fileURL: fullPath, projectURL: projectURL) { result in
                        switch result {
                        case .success: onComplete(true, "File written and validated", originalContent)
                        case .warnings(let msgs): onOutput("Warnings:\n\(msgs.joined(separator: "\n"))"); onComplete(true, "File written with warnings", originalContent)
                        case .errors(let msgs):
                            onOutput("Validation Errors:\n\(msgs.joined(separator: "\n"))")
                            Task { @MainActor in
                                let contextualError = await self.enrichErrorWithGraphRAG(errors: msgs, fileURL: fullPath, projectURL: projectURL)
                                onComplete(false, contextualError, nil)
                            }
                        case .skipped: onComplete(true, "File written successfully", originalContent)
                        }
                    }
                } else {
                    onComplete(true, "File written successfully", originalContent)
                }
            } catch {
                onComplete(false, "Failed to write file: \(error.localizedDescription)", nil)
            }
            
        case "search":
            guard let query = decision.query, !query.isEmpty else {
                onComplete(false, "No search query provided", nil)
                return
            }
            
            // Check for repeated searches - if we've searched for this before, skip
            let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let similarSearchCount = searchQueries.filter { 
                $0.lowercased().contains(normalizedQuery) || normalizedQuery.contains($0.lowercased())
            }.count
            
            if similarSearchCount >= maxRepeatedSearches {
                onOutput("Search skipped: Already searched for '\(query)' multiple times. Try a different approach.")
                failedActions.insert("search:\(normalizedQuery)")
                onComplete(false, "Repeated search detected - try writing code instead", nil)
                return
            }
            
            searchQueries.append(normalizedQuery)
            
            webSearch.search(query: query) { results in
                let summary = results.prefix(5).map { "- \($0.title): \($0.snippet.prefix(100))" }.joined(separator: "\n")
                onOutput("Search results:\n\(summary)")
                onComplete(true, "Found \(results.count) results", nil)
            }
            
        case "file":
            guard let path = decision.filePath else { onComplete(false, "No path", nil); return }
            
            // Resolve to absolute URL — relative paths are joined with projectURL.
            // Absolute paths are used directly so we never double-prepend the root.
            let resolvedURL: URL
            if path.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: path).standardizedFileURL
            } else {
                resolvedURL = (projectURL ?? URL(fileURLWithPath: ""))
                    .appendingPathComponent(path)
                    .standardizedFileURL
            }
            // Single canonical key used for ALL tracking — lowercase absolute path.
            let canonicalKey = resolvedURL.path.lowercased()
            let filename = resolvedURL.lastPathComponent.lowercased()
            
            // Count reads by canonical path only (filename alias is just a fallback lookup)
            let readCount = filesReadThisTask[canonicalKey] ?? 0
            
            print("[AgentService] File read check: '\(path)' -> canonical: '\(canonicalKey)', read count: \(readCount)")
            
            if readCount >= maxRepeatedFileReads {
                // Return cached content so the AI has what it needs and moves on
                let cached = lastFileContentByPath[canonicalKey] ?? lastFileContentByPath[filename] ?? ""
                if !cached.isEmpty {
                    print("[AgentService] Returning cached content for repeated read: \(path)")
                    onOutput("(Cached from previous read)\n\n\(cached)")
                } else {
                    print("[AgentService] BLOCKING repeated file read (no cache): \(path)")
                    onOutput("File '\(path)' was already read. Use the content from the conversation history above.")
                }
                onComplete(true, "Already read — using cached content", nil)
                return
            }
            
            filesReadThisTask[canonicalKey] = readCount + 1
            
            if let content = try? String(contentsOf: resolvedURL) {
                lastFileContentByPath[canonicalKey] = content
                lastFileContentByPath[filename] = content
                onOutput(content)
                onComplete(true, "Read file", nil)
            } else {
                onComplete(false, "Failed to read file: \(resolvedURL.path)", nil)
            }
             
        case "directory":
            guard let path = decision.filePath else { onComplete(false, "No path provided", nil); return }
            let recursive = decision.thought == "recursive"
            let dirToolCall = ToolCall(id: UUID().uuidString, name: "read_directory", input: ["directory_path": AnyCodable(path), "recursive": AnyCodable(recursive)])
            if let projectURL = projectURL { ToolExecutionService.shared.setProjectURL(projectURL) }
            Task {
                do {
                    let result = try await ToolExecutionService.shared.executeToolCall(dirToolCall)
                    if result.isError { onComplete(false, result.content, nil) }
                    else { onOutput(result.content); onComplete(true, "Read directory", nil) }
                } catch { onComplete(false, "Error: \(error.localizedDescription)", nil) }
            }
             
        case "spawn_subagent":
            guard let call = toolCall else { onComplete(false, "No tool call for spawn_subagent", nil); return }
            if let projectURL = projectURL { ToolExecutionService.shared.setProjectURL(projectURL) }
            ToolExecutionService.shared.setAgentRunContext(agentTaskId: agentTaskId)
            Task {
                do {
                    let result = try await ToolExecutionService.shared.executeToolCall(call)
                    onOutput(result.content)
                    onComplete(!result.isError, result.content, nil)
                } catch {
                    onComplete(false, "Error: \(error.localizedDescription)", nil)
                }
            }
             
        default:
            onComplete(false, "Unknown action: \(decision.action)", nil)
        }
    }

    // MARK: - Error Enrichment
    
    func enrichErrorWithGraphRAG(errors: [String], fileURL: URL, projectURL: URL) async -> String {
        let symbolNames = extractSymbolNames(from: errors)
        guard !symbolNames.isEmpty else {
            return "File written but contains errors:\n\(errors.joined(separator: "\n"))"
        }
        
        var graphRAGContext: [String] = []
        let graphRAG = GraphRAGService.shared
        
        for symbolName in symbolNames {
            let relationships = await graphRAG.findRelatedFiles(for: symbolName, in: projectURL, relationshipTypes: [.inheritance, .instantiation, .methodCall, .typeReference])
            if !relationships.isEmpty {
                let relatedFiles = Set(relationships.map { $0.sourceFile.lastPathComponent })
                graphRAGContext.append("GraphRAG Context for '\(symbolName)':\n- Related files: \(relatedFiles.joined(separator: ", "))")
            }
        }
        
        var enrichedError = "File written but contains errors:\n\(errors.joined(separator: "\n"))"
        if !graphRAGContext.isEmpty {
            enrichedError += "\n\nCONTEXTUAL INFORMATION:\n\(graphRAGContext.joined(separator: "\n\n"))"
        }
        return enrichedError
    }
    
    private func extractSymbolNames(from errors: [String]) -> [String] {
        var symbols: Set<String> = []
        let patterns = [
            #"Cannot find '([A-Za-z_][A-Za-z0-9_]*)'"#,
            #"unresolved identifier '([A-Za-z_][A-Za-z0-9_]*)'"#,
            #"Type '([A-Za-z_][A-Za-z0-9_]*)' has no member"#,
            #"Value of type '([A-Za-z_][A-Za-z0-9_]*)' has no member"#
        ]
        
        for error in errors {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: error, options: [], range: NSRange(location: 0, length: error.utf16.count)),
                   match.numberOfRanges > 1,
                   let symbolRange = Range(match.range(at: 1), in: error) {
                    symbols.insert(String(error[symbolRange]))
                }
            }
        }
        return Array(symbols)
    }

    // MARK: - Helpers
    
    private func isVagueTask(_ task: String) -> Bool {
        let lower = task.lowercased()
        let vaguePatterns = ["upgrade", "improve", "fix", "update", "refactor", "modernize", "enhance"]
        let specificPatterns = [".js", ".ts", ".swift", ".py", ".html", ".css", "function", "class", "file"]
        return vaguePatterns.contains { lower.contains($0) } && !specificPatterns.contains { lower.contains($0) } && task.count < 50
    }

    private func listProjectFiles(at url: URL, maxDepth: Int) -> [String] {
        var files: [String] = []
        func listRecursively(_ currentURL: URL, depth: Int, relativePath: String) {
            guard depth <= maxDepth, let contents = try? FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for item in contents {
                let name = item.lastPathComponent
                if name.hasPrefix(".") || ["node_modules", "build", "dist", ".git"].contains(name) { continue }
                let itemRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    files.append("\(itemRelativePath)/")
                    listRecursively(item, depth: depth + 1, relativePath: itemRelativePath)
                } else {
                    files.append(itemRelativePath)
                }
            }
        }
        listRecursively(url, depth: 0, relativePath: "")
        return files.sorted()
    }

    private func extractPartialContent(from response: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\"content\"\\s*:\\s*\"", options: []),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)) else { return nil }
        
        let contentStartIndex = response.index(response.startIndex, offsetBy: match.range.upperBound)
        var result = ""
        var chars = response[contentStartIndex...].makeIterator()
        while let char = chars.next() {
            if char == "\"" { break }
            if char == "\\" {
                if let escaped = chars.next() {
                    switch escaped {
                    case "n": result.append("\n"); case "t": result.append("\t"); case "\"": result.append("\""); case "\\": result.append("\\"); default: result.append(escaped)
                    }
                }
            } else { result.append(char) }
        }
        return result.isEmpty ? nil : result
    }

    private func updateStepStreamingCode(_ id: UUID, code: String) {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            steps[index].streamingCode = code
        }
    }

    private func finalize(success: Bool, error: String? = nil, projectURL: URL? = nil, summary: String? = nil, onComplete: @escaping (AgentTaskResult) -> Void) {
        isRunning = false
        let stepsForSummary = currentTaskSteps
        let finalSummary = success ? (summary ?? AgentSummaryGenerator.generateTaskSummary(from: stepsForSummary)) : (error ?? "Task failed")
        steps.append(AgentStep(type: .complete, description: "Task Complete", status: .completed, output: finalSummary))
        let status = success ? "completed" : (isCancelled ? "aborted" : "error")
        let result = AgentTaskResult(success: success, error: error, steps: steps)

        // Fire stop hook; it may return a follow-up message to auto-iterate.
        // sessionEnd is always fired after.
        Task { @MainActor [weak self] in
            let followUp = await HooksService.shared.fireStop(status: status)
            HooksService.shared.fireSessionEnd(status: status, durationMs: 0)
            onComplete(result)
            // If the hook wants to continue, post a notification for the UI.
            if let msg = followUp, !msg.isEmpty {
                NotificationCenter.default.post(
                    name: NSNotification.Name("AgentHookFollowUp"),
                    object: self,
                    userInfo: ["message": msg]
                )
            }
        }
    }

    private func addStep(_ step: AgentStep, onUpdate: @escaping (AgentStep) -> Void) {
        steps.append(step)
        onUpdate(step)
    }

    private func resetForNewTask(_ task: AgentTask) {
        isCancelled = false
        isRunning = true
        iterationCount = 0
        actionHistory.removeAll()
        failedActions.removeAll()
        recentActions.removeAll()
        searchQueries.removeAll()
        filesReadThisTask.removeAll()
        lastFileContentByPath.removeAll()
        currentThinkingStep = nil
        currentActionStep = nil
        currentTask = task
        incompleteWriteRetryCount = 0
        let taskHeader = AgentStep(type: .taskHeader, description: "Task: \(task.description)", status: .completed, output: nil)
        steps.append(taskHeader)
        currentTaskStepStartIndex = steps.count - 1
    }

    private var currentTaskSteps: [AgentStep] {
        guard currentTaskStepStartIndex < steps.count else { return steps }
        return Array(steps[currentTaskStepStartIndex...])
    }

    /// Previous task description and outcome for prompt context (what was prompted last).
    private var previousTaskContext: (description: String?, outcome: String?) {
        let priorSteps = steps[0..<currentTaskStepStartIndex]
        guard let prevHeaderIndex = priorSteps.lastIndex(where: { $0.type == .taskHeader }) else { return (nil, nil) }
        let prevDescription = steps[prevHeaderIndex].description
        let outcome: String? = priorSteps.last(where: { $0.type == .complete }).flatMap { $0.output }
        return (prevDescription, outcome)
    }

    private func clearThinkingStep() {
        if let thinkingStep = currentThinkingStep {
            steps.removeAll { $0.id == thinkingStep.id }
            currentThinkingStep = nil
        }
    }

    private func shouldAbortIteration(projectURL: URL?, onComplete: @escaping (AgentTaskResult) -> Void) -> Bool {
        if isCancelled { return true }
        if iterationCount >= maxIterations {
            finalize(success: false, error: "Max iterations reached", projectURL: projectURL, onComplete: onComplete)
            return true
        }
        return false
    }

    /// Builds execution history so the AI knows what has already been tried. Use larger output for read steps so file contents are usable.
    private func buildHistorySnapshot() async -> String {
        currentTaskSteps.map { step in
            let output = step.output ?? ""
            // Read steps contain file content - allow more so the agent can use it without re-reading
            let limit = (step.type == .fileOperation && step.description.hasPrefix("Read:")) ? 6000 : 1200
            let truncated = output.count <= limit ? output : String(output.prefix(limit)) + "\n...(truncated)"
            return "Step: \(step.description)\nStatus: \(step.status)\nOutput: \(truncated)"
        }.joined(separator: "\n---\n")
    }
    
    private func updateStep(_ id: UUID, status: AgentStepStatus? = nil, result: String? = nil, error: String? = nil, output: String? = nil, append: Bool = false, originalContent: String? = nil, replaceOldString: String? = nil, replaceNewString: String? = nil) {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            var updatedStep = steps[index]
            if let st = status { updatedStep.status = st }
            if let e = error { updatedStep.error = e }
            if let o = output {
                if append { updatedStep.output = (updatedStep.output ?? "") + o }
                else { updatedStep.output = o }
            }
            if originalContent != nil { updatedStep.originalContent = originalContent }
            if replaceOldString != nil { updatedStep.replaceOldString = replaceOldString }
            if replaceNewString != nil { updatedStep.replaceNewString = replaceNewString }
            steps[index] = updatedStep
        }
    }
}

// MARK: - Step / response parsing and prompt helpers (inlined from AIStepParser)

extension AgentService {
    static func parseResponse(_ response: String) -> (steps: [AIThinkingStep], plan: AIPlan?, actions: [AIAction]) {
        var steps: [AIThinkingStep] = []
        var plan: AIPlan?
        var actions: [AIAction] = []
        let lines = response.components(separatedBy: .newlines)
        var currentStep: AIThinkingStep?
        var currentSection: String?
        var planSteps: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().contains("plan:") || trimmed.lowercased().contains("planning:") || trimmed.lowercased().hasPrefix("## plan") || trimmed.lowercased().hasPrefix("### plan") {
                currentSection = "planning"
                if let step = currentStep { steps.append(step) }
                currentStep = AIThinkingStep(type: .planning, content: "")
                continue
            }
            if trimmed.lowercased().contains("thinking:") || trimmed.lowercased().contains("reasoning:") || trimmed.lowercased().hasPrefix("## thinking") || trimmed.lowercased().hasPrefix("### thinking") {
                currentSection = "thinking"
                if let step = currentStep { steps.append(step) }
                currentStep = AIThinkingStep(type: .thinking, content: "")
                continue
            }
            if trimmed.lowercased().contains("action:") || trimmed.lowercased().contains("executing:") || trimmed.lowercased().hasPrefix("## action") || trimmed.lowercased().hasPrefix("### action") || trimmed.lowercased().hasPrefix("step ") || trimmed.lowercased().hasPrefix("creating file:") || trimmed.lowercased().hasPrefix("create file:") {
                currentSection = "action"
                if let step = currentStep { steps.append(step) }
                currentStep = AIThinkingStep(type: .action, content: trimmed)
                continue
            }
            if trimmed.lowercased().contains("result:") || trimmed.lowercased().contains("completed:") || trimmed.lowercased().hasPrefix("## result") || trimmed.lowercased().hasPrefix("### result") {
                currentSection = "result"
                if let step = currentStep {
                    steps.append(AIThinkingStep(id: step.id, type: step.type, content: step.content, timestamp: step.timestamp, isComplete: true))
                }
                currentStep = AIThinkingStep(type: .result, content: "")
                continue
            }
            if currentSection == "planning" {
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil {
                    var stepText = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ? String(trimmed.dropFirst(2)) : trimmed
                    stepText = stepText.trimmingCharacters(in: .whitespaces)
                    if !stepText.isEmpty { planSteps.append(stepText) }
                }
            }
            if let step = currentStep, !trimmed.isEmpty {
                let updatedContent = step.content.isEmpty ? trimmed : step.content + "\n" + trimmed
                currentStep = AIThinkingStep(id: step.id, type: step.type, content: updatedContent, timestamp: step.timestamp, isComplete: step.isComplete)
            }
        }
        if let step = currentStep { steps.append(step) }
        if !planSteps.isEmpty { plan = AIPlan(steps: planSteps, estimatedTime: nil, complexity: nil) }
        for step in steps where step.type == .action {
            actions.append(AIAction(name: Self.extractActionName(from: step.content), description: step.content, status: step.isComplete ? .completed : .executing))
        }
        actions.append(contentsOf: Self.extractFileActions(from: response))
        if steps.isEmpty { steps.append(AIThinkingStep(type: .thinking, content: response)) }
        return (steps, plan, actions)
    }
    
    private static func extractActionName(from content: String) -> String {
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let cleaned = firstLine
            .replacingOccurrences(of: "Action:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Executing:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Creating file:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Create file:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Step", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Action" : String(cleaned.prefix(50))
    }
    
    private static func extractFileActions(from response: String) -> [AIAction] {
        var actions: [AIAction] = []
        var foundPaths = Set<String>()
        let fileBlockPattern = #"`([^`\n]+\.[a-zA-Z0-9]+)`[:\s]*\n```[a-zA-Z]*\n([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fileBlockPattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            for match in matches where match.numberOfRanges > 2 {
                if let pathRange = Range(match.range(at: 1), in: response), let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: CharacterSet(charactersIn: "`*\"'"))
                    let content = String(response[contentRange])
                    if !foundPaths.contains(path), !path.isEmpty {
                        foundPaths.insert(path)
                        actions.append(AIAction(name: "Create \(path)", description: "Creating file: \(path)", status: .pending, filePath: path, fileContent: content))
                    }
                }
            }
        }
        let altPattern = #"\*\*([^*\n]+\.[a-zA-Z0-9]+)\*\*[:\s]*\n```[a-zA-Z]*\n([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: altPattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            for match in matches where match.numberOfRanges > 2 {
                if let pathRange = Range(match.range(at: 1), in: response), let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: .whitespaces)
                    let content = String(response[contentRange])
                    if !foundPaths.contains(path), !path.isEmpty {
                        foundPaths.insert(path)
                        actions.append(AIAction(name: "Create \(path)", description: "Creating file: \(path)", status: .pending, filePath: path, fileContent: content))
                    }
                }
            }
        }
        let headerPattern = #"###\s+([^\n]+\.[a-zA-Z0-9]+)\s*\n```[a-zA-Z]*\n([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: headerPattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            for match in matches where match.numberOfRanges > 2 {
                if let pathRange = Range(match.range(at: 1), in: response), let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: .whitespaces)
                    let content = String(response[contentRange])
                    if !foundPaths.contains(path), !path.isEmpty {
                        foundPaths.insert(path)
                        actions.append(AIAction(name: "Create \(path)", description: "Creating file: \(path)", status: .pending, filePath: path, fileContent: content))
                    }
                }
            }
        }
        return actions
    }
    
    static func detectRunRequest(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        return lowercased.contains("run it") || lowercased.contains("run the") || lowercased.contains("start it") || lowercased.contains("start the") ||
               lowercased.contains("execute it") || lowercased.contains("execute the") || lowercased.contains("launch it") || lowercased.contains("launch the") ||
               (lowercased.contains("for me") && (lowercased.contains("run") || lowercased.contains("start") || lowercased.contains("execute")))
    }
    
    static func detectCheckRequest(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        return lowercased.contains("check") || lowercased.contains("review") || lowercased.contains("analyze") || lowercased.contains("inspect") ||
               lowercased.contains("validate") || lowercased.contains("audit") || lowercased.contains("look at") || lowercased.contains("examine") ||
               lowercased.contains("what's wrong") || lowercased.contains("any issues") || lowercased.contains("any problems")
    }
    
    static func enhancePromptForSteps(_ originalPrompt: String) -> String {
        let lowercased = originalPrompt.lowercased()
        let isProjectRequest = lowercased.contains("project") || lowercased.contains("app") || lowercased.contains("application") || lowercased.contains("create") ||
                              lowercased.contains("build") || lowercased.contains("scaffold") || lowercased.contains("landing page") || lowercased.contains("website") ||
                              lowercased.contains("web app") || lowercased.contains("web application") || lowercased.contains("dashboard") || lowercased.contains("portfolio") ||
                              lowercased.contains("blog") || lowercased.contains("write me") || lowercased.contains("make me") || lowercased.contains("build me")
        if isProjectRequest {
            return originalPrompt + "\n\n**Generate a COMPLETE, WORKING application with ALL necessary files. Use format: `path/to/file.ext`:\n```language\ncode\n```"
        }
        let mightNeedMultiple = lowercased.contains("page") || lowercased.contains("site") || lowercased.contains("component") || lowercased.contains("feature") || lowercased.contains("module")
        if mightNeedMultiple {
            return originalPrompt + "\n\n**If this requires multiple files (HTML + CSS + JS), generate ALL of them. Use format: `path/to/file.ext`:\n```language\ncode\n```"
        }
        return originalPrompt + "\n\n**WORKFLOW: Think out loud, then generate code for each file. Use format: `path/to/file.ext`:\n```language\ncode\n```"
    }
    
    static func enhancePromptForRun(_ originalPrompt: String, projectURL: URL?) -> String {
        var runCommand: String?
        if let projectURL = projectURL {
            if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("package.json").path) {
                if let data = try? Data(contentsOf: projectURL.appendingPathComponent("package.json")),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let scripts = json["scripts"] as? [String: String] {
                    runCommand = scripts["start"] ?? scripts["dev"] ?? scripts["serve"] ?? "npm start"
                } else { runCommand = "npm start" }
            } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("main.py").path) { runCommand = "python3 main.py"
            } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("app.py").path) { runCommand = "python3 app.py"
            } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) { runCommand = "cargo run"
            } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) { runCommand = "swift run"
            } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("main.go").path) { runCommand = "go run main.go"
            }
        }
        if let command = runCommand {
            return originalPrompt + "\n\nGenerate the terminal command to run this project:\n\n```bash\n\(command)\n```"
        }
        return originalPrompt + "\n\nGenerate the appropriate terminal command(s) to run/start the project. Format:\n\n```bash\n<command>\n```"
    }
}
