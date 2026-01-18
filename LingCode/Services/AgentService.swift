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
    case complete
    
    var icon: String {
        switch self {
        case .thinking: return "brain"
        case .terminal: return "terminal"
        case .complete: return "checkmark.circle.fill"
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
    let description: String?
    let command: String?
    let query: String?
    let filePath: String?
    let code: String?
    let thought: String?
    
    var displayDescription: String {
        return description ?? defaultDescription
    }
    
    private var defaultDescription: String {
        switch action.lowercased() {
        case "code":
            if let filePath = filePath {
                return "Updating code in \(filePath)"
            }
            return "Generating code"
        case "terminal":
            if let command = command {
                return "Running command: \(command)"
            }
            return "Executing terminal command"
        case "search":
            if let query = query {
                return "Searching: \(query)"
            }
            return "Performing web search"
        case "done":
            return "Task completed"
        default:
            return "Performing \(action)"
        }
    }
}

// MARK: - AgentService

// FIX: @MainActor guarantees UI updates happen serially on the main thread
@MainActor
class AgentService: ObservableObject {
    static let shared = AgentService()
    
    @Published var isRunning: Bool = false
    @Published var currentTask: AgentTask?
    @Published var steps: [AgentStep] = []
    
    // 🛑 Safety Brake State
    @Published var pendingApproval: AgentDecision?
    @Published var pendingApprovalReason: String?
    
    // Internal services
    private let aiService: AIProviderProtocol = ServiceContainer.shared.ai
    private let terminalService = TerminalExecutionService.shared
    private let webSearch = WebSearchService.shared
    
    private var isCancelled = false
    private var iterationCount = 0
    private let MAX_ITERATIONS = AgentConfiguration.maxIterations
    private var currentExecutionTask: Task<Void, Never>?
    private var currentThinkingStep: AgentStep?
    
    // Loop detection
    private var actionHistory: Set<String> = []
    private var failedActions: Set<String> = []
    private var recentActions: [String] = [] // Track last N actions for loop detection
    private var recentlyWrittenFiles: Set<String> = [] // Track files written recently (allow one read after write)
    private let maxRecentActions = 5 // Check last 5 actions for loops
    private let maxIterations = 20 // Maximum iterations before giving up
    
    // Context for resuming after approval
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
        isRunning = false
        
        // Cancel task immediately
        currentExecutionTask?.cancel()
        currentExecutionTask = nil
        
        actionHistory.removeAll()
        failedActions.removeAll()
        recentActions.removeAll()
        recentlyWrittenFiles.removeAll()
        
        // FIX: Remove thinking step strictly
        if let thinkingStep = currentThinkingStep {
            removeStep(thinkingStep.id)
            currentThinkingStep = nil
        }
        
        // Update statuses
        for step in steps where step.status == .running {
            updateStep(step.id, status: .cancelled)
        }
        
        pendingApproval = nil
        pendingApprovalReason = nil
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
        print("🔵 [AgentService] runTask() called - task: '\(taskDescription.prefix(50))...'")
        guard !isRunning else {
            print("⚠️ [AgentService] runTask() - Already running, ignoring")
            return
        }
        
        isCancelled = false
        isRunning = true
        steps = []
        iterationCount = 0
        actionHistory.removeAll()
        failedActions.removeAll()
        recentActions.removeAll()
        recentlyWrittenFiles.removeAll()
        pendingApproval = nil
        pendingApprovalReason = nil
        pendingExecutionContext = nil
        currentThinkingStep = nil
        
        let task = AgentTask(description: taskDescription, projectURL: projectURL, startTime: Date())
        currentTask = task
        
        print("🟢 [AgentService] runTask() - Starting first iteration")
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
        iterationCount += 1
        print("🔵 [AgentService] runNextIteration() - Iteration #\(iterationCount)")
        print("🟢 [AgentService] runNextIteration() - Iteration count: \(iterationCount), total steps: \(self.steps.count), action history: \(self.actionHistory.count), recent actions: \(self.recentActions.count)")
        
        // 1. Safety Checks (quick, synchronous)
        guard !isCancelled else {
            print("🟡 [AgentService] runNextIteration() - Cancelled, finalizing")
            finalize(success: false, error: "Cancelled by user", projectURL: projectURL, onComplete: onComplete)
            return
        }
        
        if iterationCount >= MAX_ITERATIONS {
            print("🟡 [AgentService] runNextIteration() - Max iterations reached (\(MAX_ITERATIONS)), finalizing")
            finalize(success: false, error: "Max iterations reached. Agent may be stuck in a loop.", projectURL: projectURL, onComplete: onComplete)
            return
        }
        
        // FIX: Check for repetitive recent actions (loop detection)
        if recentActions.count >= 3 {
            let lastThree = Array(recentActions.suffix(3))
            if lastThree.allSatisfy({ $0 == lastThree.first }) {
                print("🟡 [AgentService] runNextIteration() - Loop detected: Same action repeated 3+ times: \(lastThree.first ?? "unknown")")
                finalize(success: false, error: "Agent stuck in loop: repeating action '\(lastThree.first ?? "unknown")' multiple times", projectURL: projectURL, onComplete: onComplete)
                return
            }
        }
        
        // Add "Thinking" Step immediately (UI feedback)
        let thinkingStep = AgentStep(
            type: .thinking,
            description: "Analyzing next step...",
            status: .running
        )
        currentThinkingStep = thinkingStep
        addStep(thinkingStep, onUpdate: onStepUpdate)
        
        // FIX: Move all heavy work into Task to prevent UI freezing
        print("⚪ [AgentService] runNextIteration() - Creating Task for async work")
        currentExecutionTask = Task {
            do {
                print("⚪ [AgentService] Task started - Checking cancellation")
                guard !isCancelled else {
                    print("🟡 [AgentService] Task - Cancelled, cleaning up")
                    if let thinkingStep = self.currentThinkingStep {
                        self.removeStep(thinkingStep.id)
                        self.currentThinkingStep = nil
                    }
                    finalize(success: false, error: "Cancelled by user", projectURL: projectURL, onComplete: onComplete)
                    return
                }
                
                // Build History (moved into Task to avoid blocking UI)
                print("⚪ [AgentService] Task - Building history from \(self.steps.count) steps")
                let history = await self.steps.map { step in
                    var historyLine = "Step: \(step.description)\nStatus: \(step.status)"
                    if let output = step.output, !output.isEmpty {
                        historyLine += "\nOutput: \(output.prefix(500))"
                    }
                    if let error = step.error {
                        historyLine += "\nError: \(error)"
                    }
                    return historyLine
                }.joined(separator: "\n---\n")
                
                // Extract files already read from history (for loop prevention)
                let filesRead = self.steps.compactMap { step -> String? in
                    if step.type == .fileOperation, step.status == .completed, step.description.hasPrefix("Read: ") {
                        let filePath = String(step.description.dropFirst("Read: ".count))
                        return filePath
                    }
                    return nil
                }
                
                // Extract files that were written (allow re-reading files that were modified)
                let filesWritten = self.steps.compactMap { step -> String? in
                    if step.type == .codeGeneration, step.status == .completed, step.description.hasPrefix("Write: ") {
                        let filePath = String(step.description.dropFirst("Write: ".count))
                        return filePath
                    }
                    return nil
                }
                
                // Read agent memory (moved into Task)
                print("⚪ [AgentService] Task - Reading agent memory")
                let agentMemory = (projectURL != nil) 
                    ? AgentMemoryService.shared.readMemory(for: projectURL!)
                    : ""
                print("⚪ [AgentService] Task - Agent memory length: \(agentMemory.count) chars")
                
                // Loop detection hint (moved into Task)
                let loopDetectionHint = self.buildLoopDetectionHint()
                print("⚪ [AgentService] Task - Loop detection hint: \(loopDetectionHint.isEmpty ? "none" : "present")")
                
                // Build Prompt (moved into Task)
                print("⚪ [AgentService] Task - Building prompt")
                
                // Detect if task requires actual modifications (not just analysis)
                let taskLower = task.description.lowercased()
                let requiresModifications = taskLower.contains("upgrade") || 
                                         taskLower.contains("modify") || 
                                         taskLower.contains("improve") || 
                                         taskLower.contains("update") || 
                                         taskLower.contains("change") || 
                                         taskLower.contains("refactor") ||
                                         taskLower.contains("fix") ||
                                         taskLower.contains("add") ||
                                         taskLower.contains("implement")
                
                let modificationGuidance = requiresModifications ? """
                
                ⚠️ TASK REQUIREMENT: This task requires ACTUAL MODIFICATIONS to files, not just reading/analyzing them.
                - You MUST use write_file to make changes to the codebase
                - Reading files is only the first step - you must then modify and write them back
                - Do NOT call "done" until you have actually written modified files
                - Your summary should list the specific files you modified and what changes you made
                
                """ : ""
                
                let prompt = """
                You are an autonomous coding agent.
                Goal: \(task.description)
                \(modificationGuidance)
                \(agentMemory.isEmpty ? "" : """
                Project Memory (read from .lingcode/memory.md):
                \(agentMemory)
                
                """)
                History:
                \(history.isEmpty ? "No previous steps." : history)
                
                \(filesRead.isEmpty ? "" : """
                📁 Files Already Read (DO NOT read these again - use History instead):
                \(filesRead.map { "- \($0)" }.joined(separator: "\n"))
                
                ⚠️ CRITICAL: The FULL CONTENT of these files is already in the History section above. 
                - Reading them again will IMMEDIATELY trigger loop detection and stop the task
                - You MUST use the file content from the History section instead
                - If you need to reference a file, scroll up in the History to find its content
                - Do NOT call read_file for any file listed above
                
                """)
                ⚠️ CRITICAL RULES:
                1. Do NOT read the same file multiple times. If you have already read a file (listed above), use the information from the History instead of reading it again. The file content is already available in the History section above.
                2. Do NOT read files you just wrote unless absolutely necessary for verification. The file write is already confirmed when it succeeds.
                3. Do NOT repeat the same action multiple times. Check the History to see what has already been done.
                4. If a previous step failed, analyze why it failed and try a different approach.
                5. When the task is complete, ALWAYS use the "done" tool with a summary of what was accomplished.
                6. Use read_directory (not read_file) for directories. If you see "." or a path ending with "/", use read_directory.
                
                \(loopDetectionHint.isEmpty ? "" : """
                ⚠️ IMPORTANT: \(loopDetectionHint)
                
                """)
                Available tools:
                - run_terminal_command: Execute shell commands
                - write_file: Create or edit files
                - read_file: Read file contents (ONLY for files, not directories)
                - read_directory: List directory contents (use this for "." or any directory path)
                - codebase_search: Search the codebase
                - search_web: Search the web
                - done: Mark task complete and provide a summary (REQUIRED when task is finished)
                
                IMPORTANT: When the task is complete, you MUST use the "done" tool with a summary. Do not just stop.
                Analyze the history. If previous step failed, fix it.
                Otherwise, use the appropriate tool for the next step.
                """
                
                let agentTools: [AITool] = [
                    .runTerminalCommand(),
                    .writeFile(),
                    .codebaseSearch(),
                    .searchWeb(),
                    .readFile(),
                    .readDirectory(),
                    .done()
                ]
                print("⚪ [AgentService] Task - Prepared \(agentTools.count) tools")
                
                print("⚪ [AgentService] Task - Calling aiService.streamMessage()")
                var accumulatedResponse = ""
                var detectedToolCalls: [ToolCall] = []
                let stream = aiService.streamMessage(
                    prompt,
                    context: originalContext,
                    images: images,
                    maxTokens: nil,
                    systemPrompt: "You are an autonomous coding agent. Use tools to perform actions.",
                    tools: agentTools
                )
                print("🟢 [AgentService] Task - Stream obtained, starting to read chunks")
                
                var hasReceivedChunks = false
                let toolHandler = ToolCallHandler.shared
                var chunkCount = 0
                
                for try await chunk in stream {
                    chunkCount += 1
                    if chunkCount % 10 == 0 {
                        print("⚪ [AgentService] Task - Received chunk #\(chunkCount), accumulated: \(accumulatedResponse.count) chars")
                    }
                    if isCancelled || Task.isCancelled {
                        if let thinkingStep = self.currentThinkingStep {
                            self.removeStep(thinkingStep.id)
                            self.currentThinkingStep = nil
                        }
                        finalize(success: false, error: "Cancelled by user", projectURL: projectURL, onComplete: onComplete)
                        return
                    }
                    
                    hasReceivedChunks = true
                    accumulatedResponse += chunk
                    
                    // Debug: Check if chunk contains tool call marker
                    if chunk.contains("🔧 TOOL_CALL:") {
                        print("🔍 [AgentService] Chunk contains tool call marker: \(chunk.prefix(100))")
                    }
                    
                    let (text, toolCalls) = toolHandler.processChunk(chunk, projectURL: projectURL)
                    if !toolCalls.isEmpty {
                        print("🟢 [AgentService] Detected \(toolCalls.count) tool call(s) in chunk")
                    }
                    detectedToolCalls.append(contentsOf: toolCalls)
                    
                    if !text.isEmpty {
                        // FIX: Replace output (not append) since we're passing the full accumulated response
                        self.updateStep(thinkingStep.id, output: accumulatedResponse, append: false)
                    }
                }
                
                // Remove "Thinking" placeholder
                print("🟢 [AgentService] Task - Stream completed, total chunks: \(chunkCount), accumulated: \(accumulatedResponse.count) chars")
                self.removeStep(thinkingStep.id)
                self.currentThinkingStep = nil
                
                // FIX: Flush any incomplete tool calls from buffer
                let flushedToolCalls = toolHandler.flush()
                if !flushedToolCalls.isEmpty {
                    print("🟢 [AgentService] Task - Flushed \(flushedToolCalls.count) tool call(s) from buffer")
                    detectedToolCalls.append(contentsOf: flushedToolCalls)
                }
                
                if !hasReceivedChunks {
                    print("🔴 [AgentService] Task - No chunks received!")
                    let errorMessage: String
                    let localService = LocalOnlyService.shared
                    if localService.isLocalModeEnabled && !localService.isOllamaRunning {
                        errorMessage = "Cannot connect to Ollama. Make sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve\n3. Try again"
                    } else {
                        errorMessage = "Empty response received from AI service."
                    }
                    
                    self.addStep(AgentStep(type: .thinking, description: "AI Error", status: .failed, error: errorMessage), onUpdate: onStepUpdate)
                    self.finalize(success: false, error: errorMessage, projectURL: projectURL, onComplete: onComplete)
                    return
                }
                
                print("⚪ [AgentService] Task - Detected \(detectedToolCalls.count) tool call(s)")
                guard let toolCall = detectedToolCalls.first else {
                    print("🟡 [AgentService] Task - No tool calls detected")
                    if accumulatedResponse.lowercased().contains("done") || accumulatedResponse.lowercased().contains("complete") {
                        print("🟢 [AgentService] Task - 'Done' detected, finalizing success")
                        self.finalize(success: true, projectURL: projectURL, onComplete: onComplete)
                        return
                    }
                    
                    // Check if the response indicates API truncation
                    let isTruncated = accumulatedResponse.contains("API Response Truncated") || accumulatedResponse.contains("incomplete because the response was too large")
                    let errorMessage: String
                    if isTruncated {
                        errorMessage = "API response was truncated due to large file size. Consider breaking large files into smaller chunks or using incremental updates."
                        print("🟡 [AgentService] Task - API truncation detected, providing guidance")
                    } else {
                        errorMessage = "No tool used"
                    }
                    
                    print("🟡 [AgentService] Task - Retrying (no tool used)")
                    self.addStep(AgentStep(type: .thinking, description: "Retrying...", status: .failed, error: errorMessage), onUpdate: onStepUpdate)
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    return
                }
                
                print("🟢 [AgentService] Task - Tool call detected: \(toolCall.name)")
                guard let decision = self.convertToolCallToDecision(toolCall, projectURL: projectURL) else {
                    print("🔴 [AgentService] Task - Failed to convert tool call to decision")
                    self.addStep(AgentStep(type: .thinking, description: "Invalid tool call", status: .failed, error: "Parse error"), onUpdate: onStepUpdate)
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    return
                }
                
                print("🟢 [AgentService] Task - Decision: \(decision.action) - \(decision.displayDescription)")
                
                // FIX: Enhanced Loop Detection
                let actionHash = self.calculateActionHash(decision)
                
                // Check 1: Has this action failed before?
                if self.failedActions.contains(actionHash) {
                    print("🟡 [AgentService] Task - Loop detected: Action previously failed: \(actionHash)")
                    self.addStep(AgentStep(type: .thinking, description: "Loop Detected", status: .failed, error: "Action repeated after failure. Trying new approach."), onUpdate: onStepUpdate)
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    return
                }
                
                // Check 2: Has this exact action been done recently (even if successful)?
                if self.actionHistory.contains(actionHash) {
                    // FIX: Allow reading a file once after writing it (verification pattern)
                    let isReadingFile = decision.action == "file" || decision.action == "directory"
                    let isReadingRecentlyWritten = isReadingFile && decision.filePath != nil && self.recentlyWrittenFiles.contains(decision.filePath!)
                    
                    if isReadingRecentlyWritten {
                        // Allow one read after write, then remove from recently written set
                        print("🟢 [AgentService] Task - Allowing verification read of recently written file: \(decision.filePath ?? "unknown")")
                        self.recentlyWrittenFiles.remove(decision.filePath!)
                    } else {
                        // FIX: More permissive loop detection
                        // - File reads are low-cost, allow up to 3-4 reads before blocking
                        // - Only block if the same action is repeated consecutively (last 3 actions are identical)
                        // - Allow more flexibility if agent has made progress (written files, executed commands)
                        
                        let recentCount = self.recentActions.filter { $0 == actionHash }.count
                        
                        // Check if last 3 actions are all the same (consecutive repetition)
                        let lastThreeActions = Array(self.recentActions.suffix(3))
                        let isConsecutiveRepetition = lastThreeActions.count == 3 && lastThreeActions.allSatisfy { $0 == actionHash }
                        
                        // Check if agent has made progress (written files or executed commands) since last occurrence
                        // Find when this action was last executed by looking at steps
                        let lastOccurrenceStepIndex = self.steps.lastIndex { step in
                            // Match step by checking if it's the same action type and file path
                            let stepActionHash = self.calculateActionHashFromStep(step)
                            return stepActionHash == actionHash
                        }
                        
                        let hasMadeProgress: Bool
                        if let lastIndex = lastOccurrenceStepIndex, lastIndex < self.steps.count - 1 {
                            // Check if any steps after the last occurrence made progress (wrote files or executed commands)
                            let stepsSinceLastOccurrence = Array(self.steps[(lastIndex + 1)...])
                            hasMadeProgress = stepsSinceLastOccurrence.contains { step in
                                (step.type == .codeGeneration && step.status == .completed) ||
                                (step.type == .terminal && step.status == .completed)
                            }
                        } else {
                            // First occurrence or no other steps since - assume no progress yet
                            hasMadeProgress = false
                        }
                        
                        // Stricter for file reads - block after 2 reads of the same file (content is in history)
                        // Only allow more if it's a different file or if progress was made
                        let maxAllowedReads = isReadingFile ? 2 : 2
                        
                        // Check if this is reading a file that was already read (content should be in history)
                        // BUT allow re-reading if the file was written after it was read (file was modified)
                        let filePath = decision.filePath ?? ""
                        let wasRead = filesRead.contains(filePath)
                        let wasWritten = filesWritten.contains(filePath)
                        let isReReadingKnownFile = isReadingFile && !filePath.isEmpty && wasRead && !wasWritten
                        
                        if isReReadingKnownFile {
                            // Block immediately if trying to re-read a file that's already in history AND wasn't modified
                            print("🟡 [AgentService] Task - Loop detected: Attempting to re-read file that's already in history: \(filePath)")
                            let errorMsg = "This file was already read and its content is in the History above. Do NOT read it again - use the content from History instead."
                            self.addStep(AgentStep(type: .thinking, description: "Loop Detected", status: .failed, error: errorMsg), onUpdate: onStepUpdate)
                            self.finalize(success: false, error: "Agent stuck in loop: re-reading file '\(filePath)' that's already in history", projectURL: projectURL, onComplete: onComplete)
                            return
                        } else if wasRead && wasWritten {
                            // File was read, then written - allow reading again to verify changes
                            print("🟢 [AgentService] Task - Allowing re-read of file that was modified: \(filePath)")
                        }
                        
                        if isConsecutiveRepetition {
                            // Consecutive repetition is always suspicious - block immediately
                            print("🟡 [AgentService] Task - Loop detected: Same action repeated 3+ times consecutively: \(actionHash)")
                            self.addStep(AgentStep(type: .thinking, description: "Loop Detected", status: .failed, error: "Same action repeated multiple times consecutively. Stopping to avoid infinite loop."), onUpdate: onStepUpdate)
                            self.finalize(success: false, error: "Agent stuck in loop: repeating action '\(decision.displayDescription)'", projectURL: projectURL, onComplete: onComplete)
                            return
                        } else if recentCount >= maxAllowedReads && !hasMadeProgress {
                            // Only block if no progress has been made and threshold exceeded
                            print("🟡 [AgentService] Task - Loop detected: Action repeated \(recentCount) times without progress: \(actionHash)")
                            self.addStep(AgentStep(type: .thinking, description: "Loop Detected", status: .failed, error: "Same action repeated \(recentCount) times without making progress. Stopping to avoid infinite loop."), onUpdate: onStepUpdate)
                            self.finalize(success: false, error: "Agent stuck in loop: repeating action '\(decision.displayDescription)'", projectURL: projectURL, onComplete: onComplete)
                            return
                        } else if recentCount >= maxAllowedReads {
                            // Warn but allow if progress has been made
                            print("⚠️ [AgentService] Task - Action repeated \(recentCount) times, but progress detected. Allowing...")
                        }
                    }
                }
                
                // Check 3: Maximum iteration limit
                if self.steps.count >= self.maxIterations {
                    print("🟡 [AgentService] Task - Maximum iterations (\(self.maxIterations)) reached")
                    self.addStep(AgentStep(type: .thinking, description: "Max Iterations", status: .failed, error: "Reached maximum iterations. Task may be too complex or stuck."), onUpdate: onStepUpdate)
                    self.finalize(success: false, error: "Maximum iterations reached. Task may be too complex.", projectURL: projectURL, onComplete: onComplete)
                    return
                }
                
                // Add to history
                self.actionHistory.insert(actionHash)
                self.recentActions.append(actionHash)
                // Keep only last N actions
                if self.recentActions.count > self.maxRecentActions {
                    self.recentActions.removeFirst()
                }
                print("🟢 [AgentService] Task - Action added to history (total: \(self.actionHistory.count), recent: \(self.recentActions.count))")
                
                // Create Step
                let nextStep = AgentStep(
                    type: self.mapType(decision.action),
                    description: decision.displayDescription,
                    status: .running,
                    output: decision.thought
                )
                self.addStep(nextStep, onUpdate: onStepUpdate)
                
                // Safety Check
                print("⚪ [AgentService] Task - Running safety check")
                let safetyCheck = AgentSafetyGuard.shared.check(decision)
                
                switch safetyCheck {
                case .blocked(let reason):
                    print("🟡 [AgentService] Task - Action BLOCKED: \(reason)")
                    self.updateStep(nextStep.id, status: .failed, error: "Blocked: \(reason)")
                    onStepUpdate(nextStep)
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    
                case .needsApproval(let reason):
                    print("🟡 [AgentService] Task - Action NEEDS APPROVAL: \(reason)")
                    self.pendingApproval = decision
                    self.pendingApprovalReason = reason
                    self.pendingExecutionContext = PendingExecutionContext(
                        decision: decision, task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete, stepId: nextStep.id
                    )
                    
                case .safe:
                    print("🟢 [AgentService] Task - Action SAFE, executing")
                    self.executeDecision(decision, projectURL: projectURL, onOutput: { output in
                        print("⚪ [AgentService] executeDecision - Output received: \(output.prefix(100))...")
                        // Append incremental output from execution
                        self.updateStep(nextStep.id, output: output, append: true)
                        onStepUpdate(nextStep)
                    }, onComplete: { success, output in
                        print("🟢 [AgentService] executeDecision - Completed: \(success ? "SUCCESS" : "FAILED")")
                        let actionHash = self.calculateActionHash(decision)
                        if success {
                            self.failedActions.remove(actionHash)
                            
                            // FIX: Track files that were written (allow one read after write for verification)
                            if decision.action == "code" && decision.filePath != nil {
                                print("🟢 [AgentService] executeDecision - File written: \(decision.filePath!), allowing one verification read")
                                self.recentlyWrittenFiles.insert(decision.filePath!)
                            }
                        } else {
                            self.failedActions.insert(actionHash)
                            print("🟡 [AgentService] executeDecision - Added to failed actions: \(actionHash)")
                            
                            // SELF-HEALING: If code action failed due to validation errors, trigger auto-fix
                            if decision.action == "code" && output.contains("contains errors") {
                                print("🔧 [AgentService] executeDecision - Code validation failed, triggering self-healing loop")
                                
                                // Extract error messages from output
                                let errorMessages = output.components(separatedBy: "\n")
                                    .filter { $0.contains("error") || $0.contains("Error") }
                                
                                // Update step with detailed error information for the agent to see
                                let detailedError = "Code validation failed. Errors:\n\(errorMessages.joined(separator: "\n"))\n\nPlease fix these errors and try again."
                                self.updateStep(nextStep.id, status: .failed, error: detailedError)
                                onStepUpdate(nextStep)
                                
                                // Check iteration limit before self-healing
                                if self.iterationCount < self.MAX_ITERATIONS {
                                    print("🟢 [AgentService] executeDecision - Starting self-healing iteration (current: \(self.iterationCount)/\(self.MAX_ITERATIONS))")
                                    // Trigger next iteration to fix the errors
                                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                                    return
                                } else {
                                    print("🟡 [AgentService] executeDecision - Max iterations reached, cannot self-heal")
                                }
                            }
                        }
                        
                        self.updateStep(nextStep.id, status: success ? .completed : .failed, result: success ? "Success" : nil, error: success ? nil : output)
                        onStepUpdate(nextStep)
                        
                        // FIX: If action is "done", update the step with summary and finalize
                        if decision.action.lowercased() == "done" {
                            print("🟢 [AgentService] executeDecision - 'done' action detected, updating step and finalizing")
                            
                            // Check if task requires modifications and verify files were written
                            let taskLower = task.description.lowercased()
                            let requiresModifications = taskLower.contains("upgrade") || 
                                                     taskLower.contains("modify") || 
                                                     taskLower.contains("improve") || 
                                                     taskLower.contains("update") || 
                                                     taskLower.contains("change") || 
                                                     taskLower.contains("refactor") ||
                                                     taskLower.contains("fix") ||
                                                     taskLower.contains("add") ||
                                                     taskLower.contains("implement")
                            
                            if requiresModifications {
                                // Count how many files were written
                                let filesWritten = self.steps.filter { step in
                                    step.type == .codeGeneration && step.status == .completed
                                }.count
                                
                                if filesWritten == 0 {
                                    print("🟡 [AgentService] executeDecision - Task requires modifications but no files were written. Rejecting 'done' call.")
                                    let errorMsg = "This task requires making actual modifications to files, but no files were written. Please use write_file to make changes before marking the task as complete."
                                    self.updateStep(nextStep.id, status: .failed, error: errorMsg)
                                    onStepUpdate(nextStep)
                                    // Continue to next iteration instead of finalizing
                                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                                    return
                                } else {
                                    print("🟢 [AgentService] executeDecision - Task requires modifications and \(filesWritten) file(s) were written. Allowing completion.")
                                }
                            }
                            
                            let summary = decision.thought ?? output
                            // Update the step with the complete summary
                            self.updateStep(nextStep.id, status: .completed, output: summary, append: false)
                            onStepUpdate(nextStep)
                            // Finalize - it will detect the existing "Task Complete" step and update it instead of adding a new one
                            self.finalize(success: true, error: nil, projectURL: projectURL, summary: summary, onComplete: onComplete)
                            return
                        }
                        
                        print("🟢 [AgentService] executeDecision - Continuing to next iteration")
                        self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    })
                }
                
            } catch {
                print("🔴 [AgentService] Task - ERROR caught: \(error.localizedDescription)")
                print("🔴 [AgentService] Task - Error type: \(type(of: error))")
                if isCancelled || Task.isCancelled {
                    print("🟡 [AgentService] Task - Error was cancellation")
                    if let thinkingStep = self.currentThinkingStep {
                        self.removeStep(thinkingStep.id)
                        self.currentThinkingStep = nil
                    }
                    finalize(success: false, error: "Cancelled by user", projectURL: projectURL, onComplete: onComplete)
                    return
                }
                
                print("🔴 [AgentService] Task - Adding error step and finalizing")
                self.addStep(AgentStep(type: .thinking, description: "Error", status: .failed, error: error.localizedDescription), onUpdate: onStepUpdate)
                self.finalize(success: false, error: error.localizedDescription, projectURL: projectURL, onComplete: onComplete)
            }
            
            print("🟢 [AgentService] Task - Completed, clearing task reference")
            currentExecutionTask = nil
        }
    }
    
    // MARK: - Action Execution
    
    private func executeDecision(
        _ decision: AgentDecision,
        projectURL: URL?,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Bool, String) -> Void
    ) {
        print("🔵 [AgentService] executeDecision() - Action: \(decision.action)")
        switch decision.action.lowercased() {
        case "done":
            print("🟢 [AgentService] executeDecision() - Task marked as complete")
            let summary = decision.thought ?? "Task completed successfully"
            onOutput("✅ Task Complete\n\n\(summary)")
            // FIX: Don't call onComplete here - let the normal flow handle it
            // The step will be updated in the onComplete callback, and finalize will update it with summary
            onComplete(true, summary)
            return
        case "terminal":
            print("⚪ [AgentService] executeDecision() - Executing terminal command")
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
            print("⚪ [AgentService] executeDecision() - Writing code to file")
            guard let filePath = decision.filePath, let code = decision.code else {
                print("🔴 [AgentService] executeDecision() - Missing filePath or code")
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
                
                // FIX: Check if file exists BEFORE writing (to detect new files)
                let fileExisted = FileManager.default.fileExists(atPath: fullPath.path)
                
                // FIX: Read original content BEFORE writing (for change highlighting)
                let originalContent: String?
                if fileExisted {
                    originalContent = try? String(contentsOf: fullPath, encoding: .utf8)
                } else {
                    originalContent = nil
                }
                
                // Write file
                try code.write(to: fullPath, atomically: true, encoding: .utf8)
                onOutput("File written: \(filePath)")
                
                // FIX: Notify UI to refresh file tree AND open file in editor with highlighting
                if !fileExisted {
                    // New file created - notify UI to refresh file tree and open file
                    print("🟢 [AgentService] New file created: \(filePath), opening in editor with highlighting")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FileCreated"),
                        object: nil,
                        userInfo: [
                            "fileURL": fullPath,
                            "filePath": filePath,
                            "content": code,
                            "originalContent": originalContent ?? ""
                        ]
                    )
                } else {
                    // Existing file updated - notify UI to refresh and open with change highlighting
                    print("🟢 [AgentService] File updated: \(filePath), opening in editor with change highlighting")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FileUpdated"),
                        object: nil,
                        userInfo: [
                            "fileURL": fullPath,
                            "filePath": filePath,
                            "content": code,
                            "originalContent": originalContent ?? ""
                        ]
                    )
                }
                
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
                            // Warnings are acceptable - mark as success
                            onComplete(true, "File written with warnings")
                        case .errors(let messages):
                            let errorDetails = messages.joined(separator: "\n")
                            onOutput("❌ Code written but has errors:\n\(errorDetails)")
                            
                            // CONTEXTUAL SELF-HEALING: Attach GraphRAG context for failing symbols
                            Task { @MainActor in
                                let contextualError = await self.enrichErrorWithGraphRAG(
                                    errors: messages,
                                    fileURL: fullPath,
                                    projectURL: projectURL
                                )
                                // SELF-HEALING: Mark as failed with detailed error messages + GraphRAG context
                                onComplete(false, contextualError)
                            }
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
            print("⚪ [AgentService] executeDecision() - Searching codebase")
            guard let query = decision.query, !query.isEmpty else {
                print("🔴 [AgentService] executeDecision() - No query provided")
                onComplete(false, "No search query provided")
                return
            }
            
            webSearch.search(query: query) { results in
                let summary = results.prefix(5).map { "• \($0.title): \($0.snippet.prefix(100))" }.joined(separator: "\n")
                onOutput("Search results:\n\(summary)")
                onComplete(true, "Found \(results.count) results")
            }
            
        case "file":
             print("⚪ [AgentService] executeDecision() - Reading file")
             // Informational read for Agent
             guard let path = decision.filePath else {
                 print("🔴 [AgentService] executeDecision() - No path provided")
                 onComplete(false, "No path"); return
             }
             let url = (projectURL ?? URL(fileURLWithPath: "")).appendingPathComponent(path)
             if let content = try? String(contentsOf: url) {
                 onOutput(content)
                 onComplete(true, "Read file")
             } else {
                 onComplete(false, "Failed to read file")
             }
             
        case "directory":
            print("⚪ [AgentService] executeDecision() - Reading directory")
            // FIX: Properly handle directory reads using ToolExecutionService
            guard let path = decision.filePath else {
                print("🔴 [AgentService] executeDecision() - No path provided for directory read")
                onComplete(false, "No path provided")
                return
            }
            
            // Create a tool call for directory reading
            let recursive = decision.thought == "recursive"
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: "read_directory",
                input: [
                    "directory_path": AnyCodable(path),
                    "recursive": AnyCodable(recursive)
                ]
            )
            
            // Execute using ToolExecutionService
            // FIX: Set project URL before executing
            if let projectURL = projectURL {
                ToolExecutionService.shared.setProjectURL(projectURL)
            }
            
            Task {
                do {
                    let result = try await ToolExecutionService.shared.executeToolCall(toolCall)
                    if result.isError {
                        onComplete(false, result.content)
                    } else {
                        onOutput(result.content)
                        onComplete(true, "Read directory")
                    }
                } catch {
                    onComplete(false, "Error reading directory: \(error.localizedDescription)")
                }
            }
             
        default:
            print("🔴 [AgentService] executeDecision() - Unknown action: \(decision.action)")
            onComplete(false, "Unknown action: \(decision.action)")
        }
    }
    
    // MARK: - Contextual Self-Healing
    
    /// Enrich error messages with GraphRAG context for failing symbols
    /// This provides the agent with related files/symbols automatically, avoiding re-reads
    private func enrichErrorWithGraphRAG(
        errors: [String],
        fileURL: URL,
        projectURL: URL
    ) async -> String {
        // Extract symbol names from error messages
        let symbolNames = extractSymbolNames(from: errors)
        
        guard !symbolNames.isEmpty else {
            // No symbols found, return original error
            return "File written but contains errors:\n\(errors.joined(separator: "\n"))"
        }
        
        // Query GraphRAG for related files/symbols
        var graphRAGContext: [String] = []
        let graphRAG = GraphRAGService.shared
        
        for symbolName in symbolNames {
            let relationships = await graphRAG.findRelatedFiles(
                for: symbolName,
                in: projectURL,
                relationshipTypes: [.inheritance, .instantiation, .methodCall, .typeReference]
            )
            
            if !relationships.isEmpty {
                let relatedFiles = Set(relationships.map { $0.sourceFile.lastPathComponent })
                graphRAGContext.append("""
                📊 GraphRAG Context for '\(symbolName)':
                - Related files: \(relatedFiles.joined(separator: ", "))
                - Relationship types: \(Set(relationships.map { String(describing: $0.relationshipType) }).joined(separator: ", "))
                """)
            }
        }
        
        // Build enriched error message
        var enrichedError = "File written but contains errors:\n\(errors.joined(separator: "\n"))"
        
        if !graphRAGContext.isEmpty {
            enrichedError += "\n\n🔍 CONTEXTUAL INFORMATION (from GraphRAG - no need to re-read files):\n"
            enrichedError += graphRAGContext.joined(separator: "\n\n")
            enrichedError += "\n\n💡 Use this context to understand how these symbols are used in the codebase."
        }
        
        return enrichedError
    }
    
    /// Extract symbol names from error messages using common patterns
    private func extractSymbolNames(from errors: [String]) -> [String] {
        var symbols: Set<String> = []
        
        // Common error patterns:
        // - "Cannot find 'SymbolName' in scope"
        // - "Use of unresolved identifier 'SymbolName'"
        // - "Type 'SymbolName' has no member 'method'"
        // - "Value of type 'SymbolName' has no member"
        
        let patterns = [
            #"Cannot find '([A-Za-z_][A-Za-z0-9_]*)'"#,
            #"unresolved identifier '([A-Za-z_][A-Za-z0-9_]*)'"#,
            #"Type '([A-Za-z_][A-Za-z0-9_]*)' has no member"#,
            #"Value of type '([A-Za-z_][A-Za-z0-9_]*)' has no member"#,
            #"'([A-Za-z_][A-Za-z0-9_]*)' is not a member type"#,
            #"Initializer for type '([A-Za-z_][A-Za-z0-9_]*)' requires"#
        ]
        
        for error in errors {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: error, options: [], range: NSRange(location: 0, length: error.utf16.count)),
                   match.numberOfRanges > 1,
                   let symbolRange = Range(match.range(at: 1), in: error) {
                    let symbol = String(error[symbolRange])
                    symbols.insert(symbol)
                }
            }
        }
        
        return Array(symbols)
    }
    
    // MARK: - Shadow Workspace Validation
    
    private enum ValidationResult {
        case success
        case warnings([String])
        case errors([String])
        case skipped
    }
    
    private func validateCodeAfterWrite(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        // SHADOW WORKSPACE: Run validation in temporary directory
        // This allows running tests/builds safely without affecting the project
        let shadowService = ShadowWorkspaceService.shared
        
        // Create shadow workspace if it doesn't exist
        guard let shadowWorkspaceURL = shadowService.getShadowWorkspace(for: projectURL) ?? 
                                      shadowService.createShadowWorkspace(for: projectURL) else {
            // Fallback to direct validation if shadow workspace creation fails
            print("⚠️ [AgentService] Failed to create shadow workspace, using direct validation")
            validateCodeDirectly(fileURL: fileURL, projectURL: projectURL, completion: completion)
            return
        }
        
        // Read the modified file content
        guard let modifiedContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("🔴 [AgentService] Failed to read modified file content")
            completion(.errors(["Failed to read modified file content"]))
            return
        }
        
        // Calculate relative path
        let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
        
        // Prepare shadow workspace (copy dependencies and modified file)
        do {
            try shadowService.prepareShadowWorkspaceForValidation(
                modifiedFileURL: fileURL,
                projectURL: projectURL,
                shadowWorkspaceURL: shadowWorkspaceURL
            )
            
            // Write modified content to shadow workspace
            try shadowService.writeToShadowWorkspace(
                content: modifiedContent,
                relativePath: relativePath,
                shadowWorkspaceURL: shadowWorkspaceURL
            )
            
            // Run validation in shadow workspace
            let shadowFileURL = shadowWorkspaceURL.appendingPathComponent(relativePath)
            validateCodeInShadowWorkspace(
                fileURL: shadowFileURL,
                shadowWorkspaceURL: shadowWorkspaceURL,
                originalProjectURL: projectURL,
                completion: completion
            )
        } catch {
            print("🔴 [AgentService] Failed to prepare shadow workspace: \(error)")
            // Fallback to direct validation
            validateCodeDirectly(fileURL: fileURL, projectURL: projectURL, completion: completion)
        }
    }
    
    /// Validate code directly in project (fallback method)
    private func validateCodeDirectly(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
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
    
    /// Validate code in shadow workspace
    private func validateCodeInShadowWorkspace(
        fileURL: URL,
        shadowWorkspaceURL: URL,
        originalProjectURL: URL,
        completion: @escaping (ValidationResult) -> Void
    ) {
        // Use LinterService for validation in shadow workspace
        let linterService = LinterService.shared
        
        linterService.validate(files: [fileURL], in: shadowWorkspaceURL) { lintError in
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
                    self.validateSwiftCompilationInShadow(
                        fileURL: fileURL,
                        shadowWorkspaceURL: shadowWorkspaceURL,
                        originalProjectURL: originalProjectURL,
                        completion: completion
                    )
                } else {
                    // For non-Swift files, if no linter errors, consider it successful
                    completion(.success)
                }
            }
        }
    }
    
    /// Validate Swift file compilation using swift build in shadow workspace
    private func validateSwiftCompilationInShadow(
        fileURL: URL,
        shadowWorkspaceURL: URL,
        originalProjectURL: URL,
        completion: @escaping (ValidationResult) -> Void
    ) {
        // Check if it's a Swift Package or Xcode project
        let hasPackageSwift = FileManager.default.fileExists(atPath: shadowWorkspaceURL.appendingPathComponent("Package.swift").path)
        let hasXcodeProject = FileManager.default.enumerator(at: originalProjectURL, includingPropertiesForKeys: nil)?.contains { url in
            (url as? URL)?.pathExtension == "xcodeproj"
        } ?? false
        
        guard hasPackageSwift || hasXcodeProject else {
            // Not a Swift project - skip validation
            completion(.skipped)
            return
        }
        
        // Run swift build in shadow workspace
        let terminalService = TerminalExecutionService.shared
        terminalService.execute(
            "swift build 2>&1",
            workingDirectory: shadowWorkspaceURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                if exitCode == 0 {
                    completion(.success)
                } else {
                    // Try to extract error messages from build output
                    completion(.errors(["Compilation failed in shadow workspace. Check build output for details."]))
                }
            }
        )
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
                    completion(.errors(["Compilation failed. Check build output for details."]))
                }
            }
        )
    }
    
    // MARK: - Helpers
    
    private func finalize(success: Bool, error: String? = nil, projectURL: URL? = nil, summary: String? = nil, onComplete: @escaping (AgentTaskResult) -> Void) {
        print("🔵 [AgentService] finalize() - success: \(success), error: \(error ?? "none"), steps: \(self.steps.count)")
        self.isRunning = false
        
        // FIX: Generate summary if not provided
        let finalSummary: String
        if let providedSummary = summary {
            finalSummary = providedSummary
        } else if success {
            // Auto-generate summary from completed steps
            finalSummary = generateTaskSummary(from: self.steps)
        } else {
            finalSummary = error ?? "Task failed"
        }
        
        // FIX: Always add summary as final step if task succeeded (even if empty, show completion)
        // But check if we already have a "done" step to avoid duplicates
        if success {
            // Check if the last step is already a "done" or "complete" step
            let lastStep = self.steps.last
            let lastDescription = lastStep?.description.lowercased() ?? ""
            let isLastStepDone = lastStep?.type == .complete || 
                                 lastDescription.contains("task") && lastDescription.contains("complete")
            
            if isLastStepDone {
                // Update the existing step with the final summary instead of adding a new one
                if let lastStepId = lastStep?.id {
                    self.updateStep(lastStepId, output: finalSummary.isEmpty ? "Task completed successfully." : finalSummary, append: false)
                    print("🟢 [AgentService] finalize() - Updated existing summary step with \(finalSummary.count) characters")
                }
            } else {
                // Add new summary step
                let summaryStep = AgentStep(
                    type: .complete,
                    description: "Task Complete",
                    status: .completed,
                    output: finalSummary.isEmpty ? "Task completed successfully." : finalSummary
                )
                self.steps.append(summaryStep)
                print("🟢 [AgentService] finalize() - Added summary step with \(finalSummary.count) characters")
            }
        }
        
        let result = AgentTaskResult(success: success, error: error, steps: self.steps)
        self.currentTask = nil
        
        if success, let projectURL = projectURL {
            print("⚪ [AgentService] finalize() - Extracting learnings for memory")
            let learnings = self.extractLearnings(from: self.steps)
            if !learnings.isEmpty {
                Task {
                    do {
                        try AgentMemoryService.shared.appendNote(learnings, for: projectURL)
                        print("🟢 [AgentService] finalize() - Memory written successfully")
                    } catch {
                        print("⚠️ [AgentService] finalize() - Failed to write agent memory: \(error)")
                    }
                }
            }
        }
        
        print("🟢 [AgentService] finalize() - Calling onComplete callback")
        onComplete(result)
        print("🟢 [AgentService] finalize() - Complete")
    }
    
    /// Generate a summary from completed steps
    private func generateTaskSummary(from steps: [AgentStep]) -> String {
        var summaryParts: [String] = []
        
        // Count actions by type
        var filesWritten: [String] = []
        var filesRead: [String] = []
        var commandsExecuted: [String] = []
        
        for step in steps {
            if step.status == .completed {
                if step.description.hasPrefix("Write: ") {
                    let fileName = String(step.description.dropFirst("Write: ".count))
                    filesWritten.append(fileName)
                } else if step.description.hasPrefix("Read: ") {
                    let fileName = String(step.description.dropFirst("Read: ".count))
                    if !filesRead.contains(fileName) {
                        filesRead.append(fileName)
                    }
                } else if step.description.hasPrefix("Exec: ") {
                    let cmd = String(step.description.dropFirst("Exec: ".count))
                    commandsExecuted.append(cmd)
                }
            }
        }
        
        // Build summary
        if !filesWritten.isEmpty {
            summaryParts.append("📝 Files Created/Modified: \(filesWritten.joined(separator: ", "))")
        }
        if !filesRead.isEmpty && filesRead.count <= 10 {
            summaryParts.append("📖 Files Analyzed: \(filesRead.count) file(s)")
        }
        if !commandsExecuted.isEmpty {
            summaryParts.append("⚙️ Commands Executed: \(commandsExecuted.count) command(s)")
        }
        
        if summaryParts.isEmpty {
            return "Task completed successfully. \(steps.filter { $0.status == .completed }.count) step(s) executed."
        }
        
        return summaryParts.joined(separator: "\n")
    }
    
    private func extractLearnings(from steps: [AgentStep]) -> String {
        var learnings: [String] = []
        
        // Look for patterns that indicate preferences
        for step in steps {
            if step.status == .completed, let output = step.output {
                // Detect coding style preferences
                if output.contains("SwiftUI") && output.contains("View") {
                    learnings.append("User prefers SwiftUI Views to be split into separate files.")
                }
                if output.contains("struct") && !output.contains("class") {
                    learnings.append("User prefers structs over classes when possible.")
                }
            }
        }
        
        return learnings.joined(separator: "\n")
    }
    
    private func addStep(_ step: AgentStep, onUpdate: @escaping (AgentStep) -> Void) {
        // No DispatchQueue needed - already on MainActor
        self.steps.append(step)
        onUpdate(step)
    }
    
    private func updateStep(_ id: UUID, status: AgentStepStatus? = nil, result: String? = nil, error: String? = nil, output: String? = nil, append: Bool = false) {
        if let index = self.steps.firstIndex(where: { $0.id == id }) {
            var s = self.steps[index]
            if let st = status { s.status = st }
            if let r = result { s.result = r }
            if let e = error { s.error = e }
            if let o = output {
                // FIX: For streaming updates, replace the output (not append) to prevent duplication
                // For non-streaming updates (like executeDecision), append is used
                if append {
                    s.output = (s.output ?? "") + o
                } else {
                    s.output = o
                }
            }
            self.steps[index] = s
        }
    }
    
    private func removeStep(_ id: UUID) {
        self.steps.removeAll { $0.id == id }
    }
    
    /// Legacy JSON parser (preserved in case fallback needed)
    private func parseDecision(from response: String) -> AgentDecision? {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```json") || jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            if lines.count >= 3 {
                jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        
        if let extracted = extractFirstCompleteJSON(from: jsonString) {
            jsonString = extracted
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
    
    private func extractFirstCompleteJSON(from text: String) -> String? {
        var braceDepth = 0
        var inString = false
        var escapeNext = false
        var startIndex: String.Index?
        
        for (index, char) in text.enumerated() {
            let stringIndex = text.index(text.startIndex, offsetBy: index)
            
            if escapeNext { escapeNext = false; continue }
            if char == "\\" { escapeNext = true; continue }
            if char == "\"" { inString.toggle(); continue }
            if inString { continue }
            
            if char == "{" {
                if braceDepth == 0 { startIndex = stringIndex }
                braceDepth += 1
            } else if char == "}" {
                braceDepth -= 1
                if braceDepth == 0, let start = startIndex {
                    return String(text[start...stringIndex])
                }
            }
        }
        return nil
    }
    
    private func mapType(_ action: String) -> AgentStepType {
        switch action.lowercased() {
        case "terminal", "run_terminal_command": return .terminal
        case "code", "write_file": return .codeGeneration
        case "search", "search_web", "codebase_search": return .webSearch
        case "file", "read_file": return .fileOperation
        case "directory", "read_directory": return .fileOperation
        case "done": return .complete
        default: return .thinking
        }
    }
    
    private func buildLoopDetectionHint() -> String {
        if failedActions.isEmpty { return "" }
        return "⚠️ The following actions were already tried and failed. Do NOT repeat them: \(failedActions.joined(separator: ", "))"
    }
    
    private func calculateActionHash(_ decision: AgentDecision) -> String {
        let command = decision.command ?? ""
        let filePath = decision.filePath ?? ""
        // Use normalized code hash to catch semantically identical edits with different formatting
        let normalizedCode = normalizeCodeForHashing(decision.code ?? "")
        let codeHash = normalizedCode.hashValue
        return "\(decision.action):\(command):\(filePath):\(codeHash)"
    }
    
    /// Normalize code for hashing by removing whitespace, comments, and formatting differences
    /// This helps detect semantically identical edits even when formatting changes
    private func normalizeCodeForHashing(_ code: String) -> String {
        var normalized = code
        
        // Remove single-line comments (// ...) - process line by line
        let lines = normalized.components(separatedBy: .newlines)
        normalized = lines.map { line in
            if let commentRange = line.range(of: "//") {
                return String(line[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return line
        }.joined(separator: "\n")
        
        // Remove multi-line comments (/* ... */) using NSRegularExpression
        do {
            let multilineCommentPattern = #"/\*.*?\*/"#
            let regex = try NSRegularExpression(pattern: multilineCommentPattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        } catch {
            // Fallback: simple string replacement if regex fails
            normalized = normalized.replacingOccurrences(of: "/*", with: "")
            normalized = normalized.replacingOccurrences(of: "*/", with: "")
        }
        
        // Normalize whitespace: collapse multiple spaces/tabs to single space
        normalized = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        // Remove leading/trailing whitespace from each line
        let trimmedLines = normalized.components(separatedBy: .newlines)
        normalized = trimmedLines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        
        // Remove all remaining whitespace for final comparison
        normalized = normalized.replacingOccurrences(of: " ", with: "")
        normalized = normalized.replacingOccurrences(of: "\n", with: "")
        normalized = normalized.replacingOccurrences(of: "\t", with: "")
        
        return normalized.lowercased()
    }
    
    /// Calculate action hash from a step (for matching steps to decisions)
    private func calculateActionHashFromStep(_ step: AgentStep) -> String {
        // Extract action info from step description
        let description = step.description.lowercased()
        var action = "unknown"
        var filePath = ""
        
        if description.hasPrefix("read: ") {
            action = "file"
            filePath = String(description.dropFirst("read: ".count))
        } else if description.hasPrefix("write: ") {
            action = "code"
            filePath = String(description.dropFirst("write: ".count))
        } else if description.hasPrefix("exec: ") {
            action = "terminal"
            let command = String(description.dropFirst("exec: ".count))
            return "\(action):\(command)::0"
        }
        
        return "\(action)::\(filePath):0"
    }
    
    private func convertToolCallToDecision(_ toolCall: ToolCall, projectURL: URL?) -> AgentDecision? {
        print("🔍 [AgentService] convertToolCallToDecision - Tool: \(toolCall.name), ID: \(toolCall.id)")
        print("🔍 [AgentService] convertToolCallToDecision - Input keys: \(toolCall.input.keys.joined(separator: ", "))")
        
        let input = toolCall.input
        
        // Debug: Print all input values
        for (key, value) in input {
            print("🔍 [AgentService] convertToolCallToDecision - Input[\(key)]: type=\(type(of: value.value)), value=\(String(describing: value.value))")
        }
        
        switch toolCall.name {
        case "done":
            guard let summary = input["summary"]?.value as? String else {
                print("🔴 [AgentService] convertToolCallToDecision - Missing 'summary' for done")
                return nil
            }
            print("🟢 [AgentService] convertToolCallToDecision - Task complete with summary")
            return AgentDecision(action: "done", description: "Task Complete", command: nil, query: nil, filePath: nil, code: nil, thought: summary)
        case "run_terminal_command":
            guard let cmd = input["command"]?.value as? String else {
                print("🔴 [AgentService] convertToolCallToDecision - Missing 'command' for run_terminal_command")
                return nil
            }
            print("🟢 [AgentService] convertToolCallToDecision - Terminal command: \(cmd)")
            return AgentDecision(action: "terminal", description: "Exec: \(cmd)", command: cmd, query: nil, filePath: nil, code: nil, thought: nil)
        case "write_file":
            // Handle hallucinated keys: some AI models may send "path" instead of "file_path"
            let filePath: String? = input["file_path"]?.value as? String ?? 
                                   input["path"]?.value as? String
            let content = input["content"]?.value as? String
            
            guard let path = filePath, let fileContent = content else {
                print("🔴 [AgentService] convertToolCallToDecision - Missing required fields for write_file")
                print("🔴 [AgentService] convertToolCallToDecision - file_path: \(filePath ?? "nil"), content: \(content != nil ? "present" : "nil")")
                print("🔴 [AgentService] convertToolCallToDecision - Available keys: \(input.keys.joined(separator: ", "))")
                return nil
            }
            
            // Log if we used a fallback key
            if input["file_path"]?.value == nil {
                print("⚠️ [AgentService] convertToolCallToDecision - Used fallback key 'path' instead of 'file_path' for write_file")
            }
            
            print("🟢 [AgentService] convertToolCallToDecision - Write file: \(path)")
            return AgentDecision(action: "code", description: "Write: \(path)", command: nil, query: nil, filePath: path, code: fileContent, thought: nil)
        case "codebase_search", "search_web":
            guard let q = input["query"]?.value as? String else {
                print("🔴 [AgentService] convertToolCallToDecision - Missing 'query' for \(toolCall.name)")
                return nil
            }
            print("🟢 [AgentService] convertToolCallToDecision - Search query: \(q)")
            return AgentDecision(action: "search", description: "Search: \(q)", command: nil, query: q, filePath: nil, code: nil, thought: nil)
        case "read_file":
            // Handle hallucinated keys: some AI models may send "path" instead of "file_path"
            let filePath: String? = input["file_path"]?.value as? String ?? 
                                   input["path"]?.value as? String
            
            guard let path = filePath else {
                print("🔴 [AgentService] convertToolCallToDecision - Missing 'file_path' (and fallback 'path') for read_file")
                print("🔴 [AgentService] convertToolCallToDecision - Available keys: \(input.keys.joined(separator: ", "))")
                return nil
            }
            
            // Log if we used a fallback key
            if input["file_path"]?.value == nil {
                print("⚠️ [AgentService] convertToolCallToDecision - Used fallback key 'path' instead of 'file_path' for read_file")
            }
            
            print("🟢 [AgentService] convertToolCallToDecision - Read file: \(path)")
            return AgentDecision(action: "file", description: "Read: \(path)", command: nil, query: nil, filePath: path, code: nil, thought: nil)
        case "read_directory":
            // Handle hallucinated keys: some AI models may send "path" or "folder" instead of "directory_path"
            let path: String? = input["directory_path"]?.value as? String ?? 
                               input["path"]?.value as? String ?? 
                               input["folder"]?.value as? String
            
            guard let directoryPath = path else {
                print("🔴 [AgentService] convertToolCallToDecision - Missing 'directory_path' (and fallbacks 'path'/'folder') for read_directory")
                print("🔴 [AgentService] convertToolCallToDecision - Available keys: \(input.keys.joined(separator: ", "))")
                return nil
            }
            
            // Log if we used a fallback key (for monitoring model behavior)
            if input["directory_path"]?.value == nil {
                let usedKey = input["path"]?.value != nil ? "path" : "folder"
                print("⚠️ [AgentService] convertToolCallToDecision - Used fallback key '\(usedKey)' instead of 'directory_path' for read_directory")
            }
            
            let recursive = (input["recursive"]?.value as? Bool) ?? false
            print("🟢 [AgentService] convertToolCallToDecision - Read directory: \(directoryPath), recursive: \(recursive)")
            // FIX: Use "directory" action instead of "file" to properly handle directory reads
            return AgentDecision(action: "directory", description: "Read: \(directoryPath)", command: nil, query: nil, filePath: directoryPath, code: nil, thought: recursive ? "recursive" : nil)
        default:
            print("🔴 [AgentService] convertToolCallToDecision - Unknown tool name: \(toolCall.name)")
            return nil
        }
    }
    // 🛑 Resume after user approval
    func resumeWithApproval(_ approved: Bool) {
        guard let context = pendingExecutionContext else { return }
        let decision = context.decision
        let stepId = context.stepId
        
        self.pendingApproval = nil
        self.pendingApprovalReason = nil
        self.pendingExecutionContext = nil
        
        if approved {
            executeDecision(decision, projectURL: context.projectURL, onOutput: { output in
                // Append incremental output from execution
                self.updateStep(stepId, output: output, append: true)
                context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
            }, onComplete: { success, output in
                self.updateStep(stepId, status: success ? .completed : .failed, result: success ? "Success" : nil, error: success ? nil : output)
                context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
                self.runNextIteration(task: context.task, projectURL: context.projectURL, originalContext: context.originalContext, images: context.images, onStepUpdate: context.onStepUpdate, onComplete: context.onComplete)
            })
        } else {
            updateStep(stepId, status: .failed, error: "Action denied by user")
            context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
            runNextIteration(task: context.task, projectURL: context.projectURL, originalContext: context.originalContext, images: context.images, onStepUpdate: context.onStepUpdate, onComplete: context.onComplete)
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
        if decision.action == "terminal", let cmd = decision.command?.lowercased() {
            for blocked in blockedCommands {
                if cmd.contains(blocked.lowercased()) {
                    return .blocked(reason: "Catastrophic command detected: \(blocked)")
                }
            }
            for risk in dangerousCommands {
                if cmd.contains(risk.lowercased()) {
                    return .needsApproval(reason: "Risky command detected: \(risk)")
                }
            }
            if cmd.contains("git") {
                if cmd.contains("reset --hard") || cmd.contains("push --force") || cmd.contains("clean -fd") {
                    return .needsApproval(reason: "Destructive git operation")
                }
            }
        }
        
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

