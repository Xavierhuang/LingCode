//
//  AIViewModel.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import SwiftUI
import Combine

class AIViewModel: ObservableObject {
    @Published var conversation = AIConversation()
    @Published var currentInput: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var thinkingSteps: [AIThinkingStep] = []
    @Published var currentPlan: AIPlan?
    @Published var currentActions: [AIAction] = []
    @Published var todoList: [TodoItem] = [] // Cursor-style todo list
    @Published var showTodoList: Bool = false // Whether to show todo list before execution
    @Published var showThinkingProcess: Bool = true
    @Published var autoExecuteCode: Bool = false // Disabled by default to prevent accidental code deletion
    @Published var isAutoApplyEnabled: Bool = false // Auto-apply edits when ProposedEdit is fully parsed
    @Published var createdFiles: [URL] = []
    
    // Project generation
    @Published var generationProgress: ProjectGenerationProgress?
    @Published var isGeneratingProject: Bool = false
    @Published var projectMode: Bool = false
    @Published var isSpeculating: Bool = false // Visual feedback for speculative context building
    
    // FIX: Tool call progress and permissions
    @Published var toolCallProgresses: [ToolCallProgress] = []
    @Published var toolPermissions: [ToolPermission] = ToolPermission.defaultPermissions
    @Published var pendingToolCalls: [String: ToolCall] = [:] // Tool calls awaiting approval
    private var toolResults: [String: ToolResult] = [:] // Collected tool results for feedback
    private var collectedToolCalls: [ToolCall] = [] // Tool calls collected during streaming
    
    // Code review before apply
    @Published var codeReviewResults: [String: CodeReviewResult] = [:] // file path -> review result
    @Published var isReviewingCode: Bool = false
    
    // Context tracking
    private let contextTracker = ContextTrackingService.shared
    
    // Performance metrics
    private let metricsService = PerformanceMetricsService.shared
    
    // Use ModernAIService via ServiceContainer for async/await
    private let aiService: AIProviderProtocol = ServiceContainer.shared.ai
    // Keep reference to ModernAIService for configuration
    private var modernAIService: ModernAIService? {
        ServiceContainer.shared.modernAIService
    }
    private let stepParser = AIStepParser.shared
    private let actionExecutor = ActionExecutor.shared
    private let projectGenerator = ProjectGeneratorService.shared
    private let queueService = TaskQueueService.shared
    private var queueObserver: NSObjectProtocol?
    
    // Reference to editor state (set by EditorViewModel)
    weak var editorViewModel: EditorViewModel?
    
    // Combine pipeline for speculative context
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSpeculativePipeline()
        
        // Listen for queue items ready to execute
        queueObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TaskQueueItemReady"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let item = notification.object as? TaskQueueItem else { return }
            
            // Execute the queued task
            self.executeQueuedTask(item)
        }
    }
    
    deinit {
        if let observer = queueObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Execute a task from the queue
    private func executeQueuedTask(_ item: TaskQueueItem) {
        guard !isLoading else {
            // If still loading, wait
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Execute the task
        sendMessageInternal(
            userMessage: item.prompt,
            context: nil,
            projectURL: nil,
            images: [],
            forceEditMode: false
        )
        
        // Note: The queue service will mark it as completed/failed when done
        // We need to hook into the completion handlers
    }
    
    private func setupSpeculativePipeline() {
        // Watch for typing - trigger speculation when user pauses
        $currentInput
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main) // Wait for pause
            .removeDuplicates()
            .filter { !$0.isEmpty && $0.count > 5 } // Don't speculate on empty or very short input
            .sink { [weak self] query in
                self?.triggerSpeculation(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func triggerSpeculation(query: String) {
        guard let editorVM = editorViewModel else { return }
        
        let activeFile = editorVM.editorState.activeDocument?.filePath
        let selectedText = editorVM.editorState.selectedText.isEmpty ? nil : editorVM.editorState.selectedText
        let projectURL = editorVM.rootFolderURL
        
        // 🚀 START THE ENGINE BEFORE USER HITS ENTER
        isSpeculating = true
        LatencyOptimizer.shared.startSpeculativeContext(
            activeFile: activeFile,
            selectedText: selectedText,
            projectURL: projectURL,
            query: query,
            onComplete: { [weak self] in
                // Clear speculation flag when context is ready
                self?.isSpeculating = false
            }
        )
    }
    
    func sendMessage(context: String? = nil, projectURL: URL? = nil, images: [AttachedImage] = [], forceEditMode: Bool = false) {
        guard !currentInput.isEmpty, !isLoading else { return }
        
        let userMessage = currentInput
        currentInput = ""
        isLoading = true
        errorMessage = nil
        createdFiles = []
        generationProgress = nil
        isSpeculating = false
        
        sendMessageInternal(userMessage: userMessage, context: context, projectURL: projectURL, images: images, forceEditMode: forceEditMode)
    }
    
    /// Send message with explicit user message (for todo list execution and internal use)
    func sendMessageInternal(userMessage: String, context: String?, projectURL: URL?, images: [AttachedImage], forceEditMode: Bool) {
        isLoading = true
        errorMessage = nil
        createdFiles = []
        generationProgress = nil
        isSpeculating = false // Clear speculation flag when sending message
        
        // Detect if this is a project generation request
        let isProjectRequest = detectProjectRequest(userMessage)
        isGeneratingProject = isProjectRequest
        
        // Detect if this is a "run it" request
        let isRunRequest = stepParser.detectRunRequest(userMessage)
        
        // Detect if this is a "check/review" request
        let isCheckRequest = stepParser.detectCheckRequest(userMessage)
        
        // If it's a check request, trigger code review instead of normal generation
        if isCheckRequest, let editorVM = editorViewModel, let activeDoc = editorVM.editorState.activeDocument {
            let reviewService = AICodeReviewService.shared
            isLoading = true
            
            reviewService.reviewCode(
                activeDoc.content,
                language: activeDoc.language,
                fileName: activeDoc.filePath?.lastPathComponent ?? "code"
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    switch result {
                    case .success(let review):
                        // Format review as a message
                        var reviewMessage = "## Code Review Results\n\n"
                        reviewMessage += "**Score:** \(review.score)/100\n\n"
                        reviewMessage += "**Summary:** \(review.summary)\n\n"
                        
                        if !review.issues.isEmpty {
                            reviewMessage += "**Issues Found:**\n\n"
                            for issue in review.issues {
                                reviewMessage += "- **\(issue.severity.rawValue)** [\(issue.category.rawValue)]"
                                if let line = issue.lineNumber {
                                    reviewMessage += " (Line \(line))"
                                }
                                reviewMessage += ": \(issue.message)\n"
                                if let suggestion = issue.suggestion {
                                    reviewMessage += "  💡 Suggestion: \(suggestion)\n"
                                }
                                reviewMessage += "\n"
                            }
                        }
                        
                        // Add review as assistant message
                        self?.conversation.addMessage(AIMessage(role: .assistant, content: reviewMessage))
                        return
                    case .failure(let error):
                        self?.conversation.addMessage(AIMessage(role: .assistant, content: "Failed to review code: \(error.localizedDescription)"))
                        return
                    }
                }
            }
            return
        }
        
        // Clear previous thinking steps
        thinkingSteps = []
        currentPlan = nil
        currentActions = []
        todoList = []
        
        conversation.addMessage(AIMessage(role: .user, content: userMessage))
        
        // Cursor feature: Generate todo list for complex prompts
        if shouldGenerateTodoList(for: userMessage) {
            generateTodoList(userMessage: userMessage, context: context, projectURL: projectURL, images: images, forceEditMode: forceEditMode)
            return // Wait for user to approve todo list before executing
        }
        
        // Continue with normal execution (if no todo list was generated)
        executeTask(userMessage: userMessage, context: context, projectURL: projectURL, images: images, forceEditMode: forceEditMode)
    }
    
    /// Execute the actual AI task (internal implementation)
    private func executeTask(
        userMessage: String,
        context: String?,
        projectURL: URL?,
        images: [AttachedImage],
        forceEditMode: Bool
    ) {
        
        // Detect if this is a project generation request
        let isProjectRequest = detectProjectRequest(userMessage)
        isGeneratingProject = isProjectRequest
        
        // Detect if this is a "run it" request
        let isRunRequest = stepParser.detectRunRequest(userMessage)
        
        // Fast task classification with heuristics
        let classifier = TaskClassifier.shared
        let editorState = editorViewModel?.editorState
        let classificationContext = ClassificationContext(
            userInput: userMessage,
            cursorIsMidLine: false, // TODO: Get from editor state
            diagnosticsPresent: false, // TODO: Get from diagnostics
            selectionExists: !(editorState?.selectedText.isEmpty ?? true),
            activeFile: editorState?.activeDocument?.filePath,
            selectedText: (editorState?.selectedText.isEmpty ?? true) ? nil : editorState?.selectedText
        )
        let taskType = classifier.classify(context: classificationContext)
        
        // Build full context (editor context + optional extra context)
        // IMPORTANT: Do NOT include "plan/think out loud" instructions when we need strict edit output.
        let fullContext = context ?? ""
        
        let contextBuilder = CursorContextBuilder.shared
        
        // Build context from editor state (if available)
        // ⚡️ SPEED CHECK: Do we have speculative context ready?
        var editorContext = ""
        if let speculative = LatencyOptimizer.shared.getSpeculativeContext() {
            print("⚡️ SPEED WIN: Used Speculative Context (0ms latency)")
            editorContext = speculative
            
            // Clear it so we don't use stale data next time
            LatencyOptimizer.shared.clearSpeculativeContext()
        }
        // Note: Context building is now done inside the Task block to handle async properly
        
        // Note: Prompt computation is moved into Task block to ensure context is built first
        
        let assistantMessage = AIMessage(role: .assistant, content: "")
        conversation.addMessage(assistantMessage)
        let assistantMessageIndex = conversation.messages.count - 1
        
        // Track response chunks for step-by-step parsing
        var accumulatedResponse = ""
        
        // FIX: Declare assistantResponse outside do block so it's accessible in catch block
        var assistantResponse = ""
        
        // Add initial thinking step for all requests
        let initialStep = AIThinkingStep(
            type: .thinking,
            content: "Analyzing your request...",
            isComplete: false
        )
        thinkingSteps.append(initialStep)
        
        // Track latency
        let contextStart = Date()
        
        // Parse edits from stream as they come
        var detectedEdits: [Edit]? = nil
        
        // FIX: Wrap async context building in Task since sendMessage is not async
        Task { @MainActor [isProjectRequest, isRunRequest, taskType, contextStart] in
            // Capture variables for use in Task block
            let capturedIsProjectRequest = isProjectRequest
            let capturedIsRunRequest = isRunRequest
            let capturedTaskType = taskType
            let capturedContextStart = contextStart
            
            // Try streaming first for better UX
            // Use higher token limit for project generation (multiple files need more tokens)
            let maxTokens = capturedIsProjectRequest ? 16384 : nil // 16k tokens for projects, default (4k) for regular requests
            
            let contextTime = Date().timeIntervalSince(capturedContextStart)
            LatencyOptimizer.shared.recordContextBuild(contextTime)
            // Clear previous context tracking
            contextTracker.clearCurrentContext()
            
            // Build context asynchronously if not already built
            var finalEditorContext = editorContext
            if finalEditorContext.isEmpty, let editorVM = editorViewModel {
                let activeFile = editorVM.editorState.activeDocument?.filePath
                let selectedText = editorVM.editorState.selectedText.isEmpty ? nil : editorVM.editorState.selectedText
                
                // Track active file context
                if let activeFile = activeFile {
                    contextTracker.trackContext(
                        type: .activeFile,
                        name: activeFile.lastPathComponent,
                        path: activeFile.path,
                        tokenCount: nil
                    )
                }
                
                // Track selection context
                if let selectedText = selectedText, !selectedText.isEmpty {
                    contextTracker.trackContext(
                        type: .selectedText,
                        name: "Selection",
                        path: activeFile?.path,
                        tokenCount: selectedText.components(separatedBy: .whitespacesAndNewlines).count
                    )
                }
                
                finalEditorContext = await ContextRankingService.shared.buildContext(
                    activeFile: activeFile,
                    selectedRange: selectedText,
                    diagnostics: nil,
                    projectURL: projectURL,
                    query: userMessage
                )
                
                // Also add Cursor-style context for compatibility
                let cursorContext = contextBuilder.buildContext(
                    editorState: editorVM.editorState,
                    cursorPosition: editorVM.editorState.cursorPosition,
                    selectedText: editorVM.editorState.selectedText,
                    projectURL: projectURL,
                    includeDiagnostics: true,
                    includeGitDiff: true,
                    includeFileGraph: true
                )
                if !cursorContext.isEmpty {
                    if finalEditorContext.isEmpty {
                        finalEditorContext = cursorContext
                    } else {
                        finalEditorContext = finalEditorContext + "\n\n" + cursorContext
                    }
                }
            }
            
            // Compute prompts after context is built
            let intent = IntentClassifier.shared.classify(userMessage)
            
            let shouldUseEditMode: Bool = {
                // Force Edit Mode if explicitly requested (e.g., Agent mode)
                if forceEditMode {
                    return true
                }
                // For other modes, check intent and task type
                switch intent {
                case .simpleReplace, .rename:
                    return true
                default:
                    break
                }
                // Also use Edit Mode for edit/refactor tasks.
                return capturedTaskType == .inlineEdit || capturedTaskType == .refactor
            }()

            // Context channel: include editor context (file/selection/diagnostics) plus any extra caller context.
            let finalFullContext: String = {
                var result = context ?? ""
                if shouldUseEditMode, !finalEditorContext.isEmpty {
                    result = finalEditorContext + "\n\n" + result
                } else if !shouldUseEditMode, !finalEditorContext.isEmpty {
                    result = finalEditorContext + "\n\n" + result
                }
                return result
            }()

            // System prompt and user message. Use spec architecture (docs/PROMPT_ARCHITECTURE.md) when in project mode with a workspace root.
            let (systemPromptForRequest, messageForRequest, contextForRequest): (String?, String, String?) = {
                if shouldUseEditMode {
                    return (
                        EditModePromptBuilder.shared.buildEditModeSystemPrompt(),
                        EditModePromptBuilder.shared.buildEditModeUserPrompt(instruction: userMessage),
                        finalFullContext.isEmpty ? nil : finalFullContext
                    )
                }
                if projectMode, let workspaceRoot = projectURL {
                    let (sys, user) = SpecPromptAssemblyService.buildPrompt(
                        userMessage: userMessage,
                        context: finalFullContext.isEmpty ? nil : finalFullContext,
                        workspaceRootURL: workspaceRoot
                    )
                    return (sys, user, nil)
                }
                return (
                    CursorSystemPromptService.shared.getEnhancedSystemPrompt(context: finalEditorContext.isEmpty ? nil : finalEditorContext),
                    capturedIsProjectRequest ? stepParser.enhancePromptForSteps(userMessage)
                        : (capturedIsRunRequest ? stepParser.enhancePromptForRun(userMessage, projectURL: projectURL) : stepParser.enhancePromptForSteps(userMessage)),
                    finalFullContext.isEmpty ? nil : finalFullContext
                )
            }()
            
            do {
                // FIX: Enable tools for agent mode (Composer mode)
                let tools: [AITool]? = projectMode ? [
                    .codebaseSearch(),
                    .readFile(),
                    .writeFile(),
                    .runTerminalCommand(),
                    .searchWeb(),
                    .readDirectory()
                ] : nil
                
                let stream = aiService.streamMessage(
                    messageForRequest,
                    context: contextForRequest,
                    images: images,
                    maxTokens: maxTokens,
                    systemPrompt: systemPromptForRequest,
                    tools: tools // FIX: Enable tools in Composer mode
                )
                
                // FIX: Tool call handler for agent capabilities
                let toolHandler = ToolCallHandler.shared
                toolHandler.clear()
                self.collectedToolCalls.removeAll()
                self.toolResults.removeAll()
                self.toolCallProgresses.removeAll()
                
                // Process stream chunks
                for try await chunk in stream {
                    // FIX: Detect and handle tool calls
                    let (text, toolCalls) = toolHandler.processChunk(chunk, projectURL: projectURL)
                    
                    if !text.isEmpty {
                        accumulatedResponse += text
                    }
                    
                    // FIX: Handle tool calls with progress indicators and permissions
                    for toolCall in toolCalls {
                        // Add to collected tool calls for result feedback
                        collectedToolCalls.append(toolCall)
                        
                        // Check if tool requires approval
                        let permission = toolPermissions.first { $0.toolName == toolCall.name }
                        let requiresApproval = permission?.requiresApproval ?? false
                        let autoApprove = permission?.autoApprove ?? false
                        
                        // Build descriptive message for the tool call
                        let message: String
                        switch toolCall.name {
                        case "write_file":
                            if let filePathValue = toolCall.input["file_path"],
                               let filePath = filePathValue.value as? String {
                                message = "Write to file: \(filePath)"
                            } else {
                                message = "Write file"
                            }
                        case "run_terminal_command":
                            if let commandValue = toolCall.input["command"],
                               let command = commandValue.value as? String {
                                message = "Run command: \(command)"
                            } else {
                                message = "Run terminal command"
                            }
                        case "read_file":
                            if let filePathValue = toolCall.input["file_path"],
                               let filePath = filePathValue.value as? String {
                                message = "Read file: \(filePath)"
                            } else {
                                message = "Read file"
                            }
                        case "codebase_search":
                            if let queryValue = toolCall.input["query"],
                               let query = queryValue.value as? String {
                                message = "Search codebase: \(String(query.prefix(50)))"
                            } else {
                                message = "Search codebase"
                            }
                        default:
                            message = "Execute \(toolCall.name)"
                        }
                        
                        // Add progress indicator
                        let progress = ToolCallProgress(
                            id: toolCall.id,
                            toolName: toolCall.name,
                            status: requiresApproval && !autoApprove ? .pending : .executing,
                            message: message,
                            startTime: Date()
                        )
                        self.toolCallProgresses.append(progress)
                        
                        // If requires approval and not auto-approved, wait for user
                        if requiresApproval && !autoApprove {
                            pendingToolCalls[toolCall.id] = toolCall
                            // Update progress to pending
                            if let index = toolCallProgresses.firstIndex(where: { $0.id == toolCall.id }) {
                                toolCallProgresses[index] = ToolCallProgress(
                                    id: toolCall.id,
                                    toolName: toolCall.name,
                                    status: .pending,
                                    message: progress.displayMessage,
                                    startTime: progress.startTime
                                )
                            }
                            continue // Skip execution until approved
                        }
                        
                        // Execute tool call
                        Task { @MainActor in
                            // Update progress to executing
                            if let index = self.toolCallProgresses.firstIndex(where: { $0.id == toolCall.id }) {
                                self.toolCallProgresses[index] = ToolCallProgress(
                                    id: toolCall.id,
                                    toolName: toolCall.name,
                                    status: .executing,
                                    message: progress.displayMessage,
                                    startTime: progress.startTime
                                )
                            }
                            
                            do {
                                let result = try await toolHandler.executeToolCall(toolCall, projectURL: projectURL)
                                
                                // Store result for feedback
                                self.toolResults[toolCall.id] = result
                                
                                // Update progress to completed
                                if let index = self.toolCallProgresses.firstIndex(where: { $0.id == toolCall.id }) {
                                    self.toolCallProgresses[index] = ToolCallProgress(
                                        id: toolCall.id,
                                        toolName: toolCall.name,
                                        status: result.isError ? .failed : .completed,
                                        message: result.isError ? "Failed: \(result.content)" : "Completed",
                                        startTime: progress.startTime
                                    )
                                }
                                
                                // If tool was write_file, update Composer files
                                if toolCall.name == "write_file",
                                   let filePathValue = toolCall.input["file_path"],
                                   let filePath = filePathValue.value as? String,
                                   let contentValue = toolCall.input["content"],
                                   let content = contentValue.value as? String {
                                    // Notify ComposerView of file change
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("ToolFileWritten"),
                                        object: nil,
                                        userInfo: ["filePath": filePath, "content": content]
                                    )
                                }
                            } catch {
                                // Update progress to failed
                                if let index = self.toolCallProgresses.firstIndex(where: { $0.id == toolCall.id }) {
                                    self.toolCallProgresses[index] = ToolCallProgress(
                                        id: toolCall.id,
                                        toolName: toolCall.name,
                                        status: .failed,
                                        message: "Error: \(error.localizedDescription)",
                                        startTime: progress.startTime
                                    )
                                }
                                
                                self.toolResults[toolCall.id] = ToolResult(
                                    toolUseId: toolCall.id,
                                    content: "Error: \(error.localizedDescription)",
                                    isError: true
                                )
                            }
                        }
                    }
                    
                    // Try to parse edits from stream early
                    if detectedEdits == nil {
                        detectedEdits = LatencyOptimizer.shared.parseEditsFromStream(accumulatedResponse)
                    }
                    
                    // Parse steps incrementally as we receive chunks
                    let parsed = self.stepParser.parseResponse(accumulatedResponse)
                    
                    // Merge thinking steps instead of replacing - preserve existing thinking steps
                    if !parsed.steps.isEmpty {
                        var mergedSteps = self.thinkingSteps
                        for newStep in parsed.steps {
                            // Check for duplicates by content similarity, not just ID
                            let isDuplicate = mergedSteps.contains { existingStep in
                                existingStep.type == newStep.type &&
                                existingStep.content.trimmingCharacters(in: .whitespacesAndNewlines) == newStep.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            
                            if !isDuplicate {
                                // Check if this is an update to an existing step
                                if let existingIndex = mergedSteps.firstIndex(where: { existingStep in
                                    existingStep.type == newStep.type &&
                                    newStep.content.contains(existingStep.content) &&
                                    newStep.content.count > existingStep.content.count
                                }) {
                                    mergedSteps[existingIndex] = newStep
                                } else {
                                    mergedSteps.append(newStep)
                                }
                            }
                        }
                        self.thinkingSteps = mergedSteps
                    }
                    if let plan = parsed.plan {
                        self.currentPlan = plan
                    }
                    
                    // Update actions and their content in real-time
                    for parsedAction in parsed.actions {
                        if let existingIndex = self.currentActions.firstIndex(where: { 
                            ($0.filePath != nil && $0.filePath == parsedAction.filePath) ||
                            ($0.filePath == nil && $0.name == parsedAction.name)
                        }) {
                            let existingAction = self.currentActions[existingIndex]
                            existingAction.fileContent = parsedAction.fileContent ?? existingAction.fileContent
                            if existingAction.status == .pending {
                                existingAction.status = .executing
                            }
                            
                            // Auto-apply if enabled and action is complete
                            if self.isAutoApplyEnabled && existingAction.status == .executing {
                                self.autoApplyActionIfReady(existingAction)
                            }
                        } else {
                            self.currentActions.append(parsedAction)
                            
                            // Auto-apply if enabled and action is ready
                            if self.isAutoApplyEnabled {
                                self.autoApplyActionIfReady(parsedAction)
                            }
                        }
                    }
                    
                    // Update message with accumulated response for streaming display
                    self.conversation.messages[assistantMessageIndex] = AIMessage(
                        id: self.conversation.messages[assistantMessageIndex].id,
                        role: .assistant,
                        content: accumulatedResponse
                    )
                }
                
                // Stream completed successfully
                assistantResponse = accumulatedResponse
                
                // FIX: Send tool results back to AI for chained tool calls
                if !collectedToolCalls.isEmpty && !toolResults.isEmpty {
                    await sendToolResultsToAI(
                        toolCalls: collectedToolCalls,
                        results: toolResults,
                        originalMessage: messageForRequest,
                        context: fullContext.isEmpty ? nil : fullContext,
                        projectURL: projectURL,
                        assistantResponse: &assistantResponse
                    )
                }
                
                // Final parse
                let parsed = self.stepParser.parseResponse(assistantResponse)
                
                // Merge thinking steps
                var mergedSteps = self.thinkingSteps
                for newStep in parsed.steps {
                    let isDuplicate = mergedSteps.contains { existingStep in
                        existingStep.type == newStep.type &&
                        existingStep.content.trimmingCharacters(in: .whitespacesAndNewlines) == newStep.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    if !isDuplicate {
                        if let existingIndex = mergedSteps.firstIndex(where: { existingStep in
                            existingStep.type == newStep.type &&
                            newStep.content.contains(existingStep.content) &&
                            newStep.content.count > existingStep.content.count
                        }) {
                            mergedSteps[existingIndex] = newStep
                        } else {
                            mergedSteps.append(newStep)
                        }
                    }
                }
                self.thinkingSteps = mergedSteps
                
                // Update plan and actions
                if parsed.plan != nil {
                    self.currentPlan = parsed.plan
                }
                self.currentActions = parsed.actions
                
                // Auto-apply actions if enabled
                if self.isAutoApplyEnabled {
                    for action in self.currentActions {
                        self.autoApplyActionIfReady(action)
                    }
                }
                
                // Update message with full response
                self.conversation.messages[assistantMessageIndex] = AIMessage(
                    id: self.conversation.messages[assistantMessageIndex].id,
                    role: .assistant,
                    content: assistantResponse
                )
                
                // Check for missing referenced files
                if capturedIsProjectRequest {
                    self.checkAndRequestMissingFiles(
                        from: assistantResponse,
                        parsedActions: parsed.actions,
                        projectURL: projectURL,
                        originalPrompt: userMessage
                    )
                }
                
                // Automatically detect and show code changes
                self.detectAndShowCodeChanges(from: assistantResponse, projectURL: projectURL)
                
                // Execute code generation if enabled
                if self.autoExecuteCode {
                    self.executeCodeGeneration(from: assistantResponse, projectURL: projectURL)
                } else {
                    self.isLoading = false
                    self.isGeneratingProject = false
                }
                
                // Track performance metrics
                let requestEndTime = Date()
                let latency = requestEndTime.timeIntervalSince(capturedContextStart)
                let modelName = self.modernAIService?.currentModel ?? "unknown"
                let inputTokens = (finalFullContext.count + userMessage.count) / 4
                let outputTokens = assistantResponse.count / 4
                
                self.metricsService.recordMetric(
                    requestType: shouldUseEditMode ? "Edit" : (capturedIsProjectRequest ? "Project" : "Chat"),
                    model: modelName,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    latency: latency,
                    contextBuildTime: contextTime,
                    success: true
                )
                
                // Save conversation to history
                let fileCount = self.currentActions.count
                ConversationHistoryService.shared.saveConversation(
                    self.conversation,
                    title: nil,
                    projectURL: projectURL,
                    fileCount: fileCount
                )
                
            } catch {
                // Handle errors
                let localService = LocalOnlyService.shared
                if localService.isLocalModeEnabled {
                    // Local mode enabled - show error, don't fall back
                    self.isLoading = false
                    self.isGeneratingProject = false
                    let errorService = ErrorHandlingService.shared
                    var errorMsg = errorService.formatError(error)
                    
                    let nsError = error as NSError
                    if nsError.domain == "LocalOnlyService" || nsError.domain == NSURLErrorDomain {
                        if nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCannotConnectToHost || nsError.code == -1021 {
                            errorMsg = "⚠️ Cannot connect to Ollama.\n\nMake sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve\n3. Try again\n\nError: \(error.localizedDescription)"
                        }
                    }
                    
                    // Track error in metrics
                    let requestEndTime = Date()
                    let latency = requestEndTime.timeIntervalSince(capturedContextStart)
                    let modelName = self.modernAIService?.currentModel ?? "unknown"
                    let inputTokens = (finalFullContext.count + userMessage.count) / 4
                    
                    self.metricsService.recordMetric(
                        requestType: shouldUseEditMode ? "Edit" : (capturedIsProjectRequest ? "Project" : "Chat"),
                        model: modelName,
                        inputTokens: inputTokens,
                        outputTokens: 0,
                        latency: latency,
                        contextBuildTime: contextTime,
                        success: false
                    )
                    
                    self.errorMessage = errorMsg
                    self.conversation.addMessage(AIMessage(
                        role: .assistant,
                        content: "❌ Error: \(errorMsg)"
                    ))
                } else {
                    // Fallback to non-streaming if streaming fails
                    do {
                        let response = try await aiService.sendMessage(
                            messageForRequest,
                            context: fullContext.isEmpty ? nil : fullContext,
                            images: images,
                            tools: nil
                        )
                        assistantResponse = response
                        
                        // Parse steps from response
                        let parsed = self.stepParser.parseResponse(response)
                        self.thinkingSteps = parsed.steps
                        self.currentPlan = parsed.plan
                        self.currentActions = parsed.actions
                        
                        // Auto-apply actions if enabled
                        if self.isAutoApplyEnabled {
                            for action in self.currentActions {
                                self.autoApplyActionIfReady(action)
                            }
                        }
                        
                        // Update message with full response
                        self.conversation.messages[assistantMessageIndex] = AIMessage(
                            id: self.conversation.messages[assistantMessageIndex].id,
                            role: .assistant,
                            content: assistantResponse
                        )
                        
                        // Execute code generation if enabled
                        if self.autoExecuteCode {
                            self.executeCodeGeneration(from: response, projectURL: projectURL)
                        } else {
                            self.isLoading = false
                            self.isGeneratingProject = false
                        }
                    } catch {
                        self.isLoading = false
                        self.isGeneratingProject = false
                        let errorService = ErrorHandlingService.shared
                        self.errorMessage = errorService.formatError(error)
                        
                        // Mark queued task as failed if applicable
                        if let currentQueuedItem = self.queueService.getCurrentExecutingItem() {
                            self.queueService.markFailed(currentQueuedItem, error: error)
                        }
                    }
                }
            }
        }
    }
    
    /// Detect if the message is requesting project generation
    private func detectProjectRequest(_ message: String) -> Bool {
        let projectKeywords = [
            "create a project",
            "create project",
            "new project",
            "build a project",
            "scaffold",
            "create an app",
            "create app",
            "build an app",
            "build app",
            "create application",
            "new application",
            "generate project",
            "generate app",
            "create a full",
            "complete project",
            "entire project",
            "whole project",
            "full application",
            "from scratch",
            "boilerplate",
            "starter",
            "template project",
            // Web-related keywords
            "landing page",
            "write me a landing page",
            "create a landing page",
            "build a landing page",
            "make a landing page",
            "website",
            "dating website",
            "ecommerce website",
            "portfolio website",
            "blog website",
            "create a website",
            "build a website",
            "make a website",
            "web app",
            "web application",
            "create a web app",
            "build a web app",
            "webpage",
            "web page",
            "create a page",
            "build a page",
            "make a page",
            "site",
            "create a site",
            "build a site",
            // UI/Component keywords that typically need multiple files
            "dashboard",
            "create a dashboard",
            "admin panel",
            "create an admin",
            "portfolio",
            "create a portfolio",
            "blog",
            "create a blog",
            "e-commerce",
            "ecommerce",
            "shop",
            "store",
            // Framework-specific that imply full apps
            "react app",
            "vue app",
            "angular app",
            "next.js",
            "nextjs",
            "nuxt",
            "svelte app",
            "flask app",
            "django app",
            "rails app",
            "express app"
        ]
        
        let lowercased = message.lowercased()
        return projectKeywords.contains { lowercased.contains($0) }
    }
    
    func clearThinkingProcess() {
        thinkingSteps = []
        currentPlan = nil
        currentActions = []
        generationProgress = nil
        toolCallProgresses.removeAll()
        pendingToolCalls.removeAll()
        toolResults.removeAll()
        collectedToolCalls.removeAll()
    }
    
    // MARK: - FIX: Tool Result Feedback
    
    /// Send tool results back to AI for chained tool calls
    private func sendToolResultsToAI(
        toolCalls: [ToolCall],
        results: [String: ToolResult],
        originalMessage: String,
        context: String?,
        projectURL: URL?,
        assistantResponse: inout String
    ) async {
        // Build tool result messages for Anthropic format
        var toolResultContent: [[String: Any]] = []
        
        for toolCall in toolCalls {
            if let result = results[toolCall.id] {
                toolResultContent.append([
                    "type": "tool_result",
                    "tool_use_id": toolCall.id,
                    "content": result.content,
                    "is_error": result.isError
                ])
            }
        }
        
        guard !toolResultContent.isEmpty else { return }
        
        // Send follow-up message with tool results
        do {
            let tools: [AITool]? = projectMode ? [
                .codebaseSearch(),
                .readFile(),
                .writeFile(),
                .runTerminalCommand(),
                .searchWeb(),
                .readDirectory()
            ] : nil
            
            let followUpMessage = "Continue with the tool results provided."
            
            let stream = aiService.streamMessage(
                followUpMessage,
                context: context,
                images: [],
                maxTokens: 4096,
                systemPrompt: nil,
                tools: tools
            )
            
            // Process follow-up response
            var followUpResponse = ""
            for try await chunk in stream {
                followUpResponse += chunk
                
                // Update conversation with follow-up response
                if let lastIndex = conversation.messages.indices.last,
                   conversation.messages[lastIndex].role == .assistant {
                    conversation.messages[lastIndex] = AIMessage(
                        id: conversation.messages[lastIndex].id,
                        role: .assistant,
                        content: assistantResponse + "\n\n[Tool Results Applied]\n" + followUpResponse
                    )
                }
            }
            
            assistantResponse += "\n\n[Tool Results Applied]\n" + followUpResponse
        } catch {
            print("Failed to send tool results to AI: \(error)")
        }
    }
    
    // MARK: - FIX: Tool Approval
    
    /// Approve a pending tool call
    func approveToolCall(_ toolCallId: String) {
        guard let toolCall = pendingToolCalls[toolCallId] else { return }
        
        pendingToolCalls.removeValue(forKey: toolCallId)
        
        // Update progress to approved
        if let index = toolCallProgresses.firstIndex(where: { $0.id == toolCallId }) {
            toolCallProgresses[index] = ToolCallProgress(
                id: toolCallId,
                toolName: toolCall.name,
                status: .approved,
                message: "Approved",
                startTime: toolCallProgresses[index].startTime
            )
        }
        
        // Execute the tool call
        Task { @MainActor in
            let toolHandler = ToolCallHandler.shared
            
            // Update to executing
            if let index = toolCallProgresses.firstIndex(where: { $0.id == toolCallId }) {
                toolCallProgresses[index] = ToolCallProgress(
                    id: toolCallId,
                    toolName: toolCall.name,
                    status: .executing,
                    message: toolCallProgresses[index].displayMessage,
                    startTime: toolCallProgresses[index].startTime
                )
            }
            
            do {
                let result = try await toolHandler.executeToolCall(toolCall, projectURL: editorViewModel?.rootFolderURL)
                toolResults[toolCallId] = result
                
                // Update to completed
                if let index = toolCallProgresses.firstIndex(where: { $0.id == toolCallId }) {
                    toolCallProgresses[index] = ToolCallProgress(
                        id: toolCallId,
                        toolName: toolCall.name,
                        status: result.isError ? .failed : .completed,
                        message: result.isError ? "Failed" : "Completed",
                        startTime: toolCallProgresses[index].startTime
                    )
                }
            } catch {
                if let index = toolCallProgresses.firstIndex(where: { $0.id == toolCallId }) {
                    toolCallProgresses[index] = ToolCallProgress(
                        id: toolCallId,
                        toolName: toolCall.name,
                        status: .failed,
                        message: "Error: \(error.localizedDescription)",
                        startTime: toolCallProgresses[index].startTime
                    )
                }
            }
        }
    }
    
    /// Reject a pending tool call
    func rejectToolCall(_ toolCallId: String) {
        pendingToolCalls.removeValue(forKey: toolCallId)
        
        // Update progress to rejected
        if let index = toolCallProgresses.firstIndex(where: { $0.id == toolCallId }) {
            toolCallProgresses[index] = ToolCallProgress(
                id: toolCallId,
                toolName: toolCallProgresses[index].toolName,
                status: .rejected,
                message: "Rejected by user",
                startTime: toolCallProgresses[index].startTime
            )
        }
    }
    
    /// Check if prompt is complex enough to warrant a todo list
    private func shouldGenerateTodoList(for prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        
        // Complex indicators
        let complexKeywords = [
            "implement", "create", "build", "add", "multiple", "several",
            "refactor", "restructure", "migrate", "convert", "rewrite",
            "feature", "module", "component", "system", "architecture"
        ]
        
        let hasComplexKeyword = complexKeywords.contains { lowercased.contains($0) }
        let wordCount = prompt.components(separatedBy: .whitespaces).count
        let hasMultipleActions = lowercased.contains("and") || lowercased.contains(",") || lowercased.contains("then")
        
        // Generate todo list if:
        // - Has complex keywords AND (long prompt OR multiple actions)
        return hasComplexKeyword && (wordCount > 15 || hasMultipleActions)
    }
    
    /// Generate todo list for complex prompt (Cursor feature)
    private func generateTodoList(userMessage: String, context: String?, projectURL: URL?, images: [AttachedImage], forceEditMode: Bool) {
        // Store execution parameters for later use
        pendingExecutionContext = (userMessage: userMessage, context: context, projectURL: projectURL, images: images, forceEditMode: forceEditMode)
        
        TodoListPlanner.shared.generateTodoList(
            for: userMessage,
            context: context,
            projectURL: projectURL
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let todos):
                self.todoList = todos
                self.showTodoList = !todos.isEmpty
            case .failure(let error):
                print("Failed to generate todo list: \(error)")
                // Continue with normal execution if todo generation fails
                if let pending = self.pendingExecutionContext {
                    self.executeWithTodoList(
                        userMessage: pending.userMessage,
                        context: pending.context,
                        projectURL: pending.projectURL,
                        images: pending.images,
                        forceEditMode: pending.forceEditMode
                    )
                    self.pendingExecutionContext = nil
                }
            }
        }
    }
    
    /// Store pending execution context for todo list approval
    private var pendingExecutionContext: (userMessage: String, context: String?, projectURL: URL?, images: [AttachedImage], forceEditMode: Bool)?
    
    /// Execute the actual task (called after todo list is approved)
    func executeWithTodoList(userMessage: String, context: String?, projectURL: URL?, images: [AttachedImage] = [], forceEditMode: Bool = false) {
        // Clear todo list UI
        showTodoList = false
        
        // Continue with normal execution, preserving all original parameters
        sendMessageInternal(userMessage: userMessage, context: context, projectURL: projectURL, images: images, forceEditMode: forceEditMode)
        
        // Clear pending context
        pendingExecutionContext = nil
    }
    
    func executeCodeGeneration(from response: String, projectURL: URL?) {
        // Add execution step
        let executionStep = AIThinkingStep(
            type: .action,
            content: "Executing file operations...",
            isComplete: false
        )
        thinkingSteps.append(executionStep)
        
        let progressHandler: (String) -> Void = { [weak self] message in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Update progress
                self.generationProgress = ProjectGenerationProgress(
                    phase: .creatingFiles,
                    message: message,
                    totalFiles: self.currentActions.count,
                    completedFiles: self.createdFiles.count
                )
                
                // Update action status
                if let lastAction = self.currentActions.first(where: { $0.status == .pending || $0.status == .executing }) {
                    lastAction.status = .executing
                    lastAction.result = message
                }
                
                // Add progress step
                let progressStep = AIThinkingStep(
                    type: .action,
                    content: message,
                    isComplete: false
                )
                self.thinkingSteps.append(progressStep)
            }
        }
        
        let completeHandler: ([URL]) -> Void = { [weak self] createdFiles in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.createdFiles = createdFiles
                
                // Mark all actions as completed
                for action in self.currentActions {
                    action.status = .completed
                    action.result = "File created successfully"
                }
                
                // Update progress
                self.generationProgress = ProjectGenerationProgress(
                    phase: .complete,
                    message: "Created \(createdFiles.count) files",
                    totalFiles: createdFiles.count,
                    completedFiles: createdFiles.count
                )
                
                // Add completion step
                let files = createdFiles.map { $0.lastPathComponent }.joined(separator: ", ")
                let completeStep = AIThinkingStep(
                    type: .complete,
                    content: "Successfully created \(createdFiles.count) file(s):\n\(files)",
                    isComplete: true
                )
                self.thinkingSteps.append(completeStep)
                
                // Notify that files were created
                NotificationCenter.default.post(
                    name: NSNotification.Name("FilesCreated"),
                    object: nil,
                    userInfo: ["files": createdFiles]
                )
                
                self.isLoading = false
                self.isGeneratingProject = false
            }
        }
        
        let errorHandler: (Error) -> Void = { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.handleCodeGenerationError(error)
            }
        }
        
        actionExecutor.executeFromAIResponse(
            response,
            projectURL: projectURL,
            onProgress: progressHandler,
            onComplete: completeHandler,
            onError: errorHandler
        )
    }
    
    /// Check if HTML references CSS/JS files that weren't generated, and request them
    private func checkAndRequestMissingFiles(
        from response: String,
        parsedActions: [AIAction],
        projectURL: URL?,
        originalPrompt: String
    ) {
        // Only check for website requests
        let lowercased = originalPrompt.lowercased()
        let isWebsite = lowercased.contains("website") ||
                       lowercased.contains("web page") ||
                       lowercased.contains("webpage") ||
                       lowercased.contains("landing page") ||
                       lowercased.contains("site") ||
                       lowercased.contains("dating website") ||
                       lowercased.contains("ecommerce website")
        
        guard isWebsite else { return }
        
        // Extract all generated file paths
        let generatedFiles = Set(parsedActions.compactMap { $0.filePath })
        
        // Check if HTML was generated
        guard let htmlContent = parsedActions.first(where: { $0.filePath?.hasSuffix(".html") == true })?.fileContent,
              htmlContent.contains("styles.css") || htmlContent.contains("script.js") else {
            return // No HTML or no references found
        }
        
        // Check for missing files
        var missingFiles: [String] = []
        if htmlContent.contains("styles.css") && !generatedFiles.contains("styles.css") {
            missingFiles.append("styles.css")
        }
        if htmlContent.contains("script.js") && !generatedFiles.contains("script.js") {
            missingFiles.append("script.js")
        }
        
        // If files are missing, automatically request them
        if !missingFiles.isEmpty {
            let missingFilesList = missingFiles.joined(separator: ", ")
            let followUpPrompt = """
            You generated index.html but forgot to generate the following referenced files: \(missingFilesList)
            
            Please generate these files now. Use the exact format:
            
            `\(missingFiles[0])`:
            ```css
            /* Complete CSS code here */
            ```
            
            \(missingFiles.count > 1 ? """
            `\(missingFiles[1])`:
            ```javascript
            // Complete JavaScript code here
            ```
            """ : "")
            
            Generate complete, working code for these files.
            """
            
            // Add a small delay then send follow-up
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.currentInput = followUpPrompt
                self.sendMessage(projectURL: projectURL)
            }
        }
    }
    
    private func handleCodeGenerationError(_ error: Error) {
        // Use ErrorHandlingService for user-friendly messages
        let errorService = ErrorHandlingService.shared
        let (message, suggestion) = errorService.userFriendlyError(error)
        
        // Check if partial success
        if let actionError = error as? ActionExecutorError,
           case .partialFailure(let errors, let files) = actionError {
            self.createdFiles = files
            
            // Mark some actions as completed, others as failed
            for (index, action) in self.currentActions.enumerated() {
                if index < files.count {
                    action.status = .completed
                    action.result = "Created successfully"
                } else {
                    action.status = .failed
                    let firstErrorString = errors.first ?? error.localizedDescription
                    let firstError = NSError(domain: "ActionExecutor", code: 0, userInfo: [NSLocalizedDescriptionKey: firstErrorString])
                    let errorMsg = errorService.formatError(firstError)
                    action.error = errorMsg
                }
            }
            
            // Notify about created files
            if !files.isEmpty {
                NotificationCenter.default.post(
                    name: NSNotification.Name("FilesCreated"),
                    object: nil,
                    userInfo: ["files": files]
                )
            }
            
            // Add partial completion step
            let completeStep = AIThinkingStep(
                type: .result,
                content: "Partially completed: Created \(files.count) files with \(errors.count) errors",
                isComplete: true
            )
            self.thinkingSteps.append(completeStep)
        } else {
            // Mark all actions as failed
            for action in self.currentActions {
                action.status = .failed
                action.error = errorService.formatError(error)
            }
            
            // Set user-friendly error message
            var errorMessage = message
            if let suggestion = suggestion {
                errorMessage += "\n\n💡 \(suggestion)"
            }
            self.errorMessage = errorMessage
            
            // Add error step
            let errorStep = AIThinkingStep(
                type: .result,
                content: "Error: \(message)",
                isComplete: true
            )
            self.thinkingSteps.append(errorStep)
        }
        
        self.isLoading = false
        self.isGeneratingProject = false
    }
    
    // MARK: - Project Templates
    
    func createProjectFromTemplate(_ template: ProjectTemplate, name: String, at location: URL) {
        isLoading = true
        isGeneratingProject = true
        errorMessage = nil
        createdFiles = []
        
        projectGenerator.createFromTemplate(
            template,
            projectName: name,
            at: location
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isGeneratingProject = false
                
                if result.success {
                    self.createdFiles = result.createdFiles
                    
                    // Notify about created files
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FilesCreated"),
                        object: nil,
                        userInfo: ["files": result.createdFiles, "projectPath": result.projectPath]
                    )
                    
                    // Add success message to conversation
                    let message = "Created \(template.name) project '\(name)' with \(result.createdFiles.count) files at \(result.projectPath.path)"
                    self.conversation.addMessage(AIMessage(role: .assistant, content: message))
                } else {
                    let errorService = ErrorHandlingService.shared
                    let formattedErrors = result.errors.map { errorService.formatError(NSError(domain: "ProjectGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: $0])) }
                    self.errorMessage = formattedErrors.joined(separator: "\n")
                }
            }
        }
    }
    
    func getProjectTemplates() -> [ProjectTemplate] {
        return projectGenerator.getProjectTemplates()
    }
    
    // MARK: - Cancellation
    
    /// Cancel the current generation
    func cancelGeneration() {
        // Cancel the AI request
        aiService.cancelCurrentRequest()
        
        // Reset states
        isLoading = false
        isGeneratingProject = false
        
        // Add cancellation step
        let cancelStep = AIThinkingStep(
            type: .result,
            content: "Generation cancelled by user",
            isComplete: true
        )
        thinkingSteps.append(cancelStep)
        
        // Update last message to show it was cancelled
        if let lastIndex = conversation.messages.indices.last,
           conversation.messages[lastIndex].role == .assistant {
            let currentContent = conversation.messages[lastIndex].content
            conversation.messages[lastIndex] = AIMessage(
                id: conversation.messages[lastIndex].id,
                role: .assistant,
                content: currentContent.isEmpty ? "[Generation cancelled]" : currentContent + "\n\n[Generation cancelled]"
            )
        }
    }
    
    // MARK: - Other Methods
    
    func setProjectURL(_ url: URL?) {
        // This will be used when executing code generation
    }
    
    func clearConversation() {
        conversation.clear()
        errorMessage = nil
        clearThinkingProcess()
        createdFiles = []
    }
    
    func setAPIKey(_ key: String, provider: AIProvider) {
        // Update both old and new services for compatibility
        AIService.shared.setAPIKey(key, provider: provider)
        if let modernService = modernAIService {
            modernService.setAPIKey(key, provider: provider)
        }
    }
    
    func hasAPIKey() -> Bool {
        // Check modern service first, fallback to old service
        if let modernService = modernAIService {
            return modernService.getAPIKey() != nil
        }
        return AIService.shared.getAPIKey() != nil
    }
    
    func explainCode(_ code: String) {
        let message = "Explain this code:\n\n\(code)"
        currentInput = message
        sendMessage()
    }
    
    func suggestCompletion(_ code: String, cursorPosition: Int) {
        let beforeCursor = String(code.prefix(cursorPosition))
        let message = "Complete this code:\n\n\(beforeCursor)"
        currentInput = message
        sendMessage(context: code)
    }
    
    /// Inline edit - Cmd+K style edit
    func inlineEdit(selectedCode: String, instruction: String, completion: @escaping (String?) -> Void) {
        let prompt = """
        Edit this code according to the instruction. Return ONLY the modified code, no explanation.
        
        Instruction: \(instruction)
        
        Code to edit:
        ```
        \(selectedCode)
        ```
        
        Return the modified code only:
        """
        
        Task { @MainActor in
            do {
                let response = try await aiService.sendMessage(prompt, context: nil, images: [], tools: nil)
                
                // Extract code from response
                var code = response
                
                // Remove markdown code blocks if present
                if code.contains("```") {
                    let parts = code.components(separatedBy: "```")
                    if parts.count >= 2 {
                        code = parts[1]
                        // Remove language identifier if present
                        if let newlineIndex = code.firstIndex(of: "\n") {
                            // FIX: Safe string indexing - check bounds before accessing
                            let nextIndex = code.index(after: newlineIndex)
                            if nextIndex < code.endIndex {
                                code = String(code[nextIndex...])
                            } else {
                                code = ""
                            }
                        }
                    }
                }
                
                completion(code.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                print("Inline edit error: \(error)")
                completion(nil)
            }
        }
    }
    
    /// Generate a project with specific requirements
    func generateProject(description: String, projectURL: URL) {
        let prompt = """
        Create a complete, working project based on this description:
        
        \(description)
        
        Requirements:
        - Include ALL necessary files
        - Provide complete, runnable code
        - Include configuration files
        - Include README with instructions
        """
        
        currentInput = prompt
        projectMode = true
        sendMessage(projectURL: projectURL)
    }
    
    /// Detect code changes from AI response and show diffs (Cursor-like)
    private func detectAndShowCodeChanges(from response: String, projectURL: URL?) {
        let patchGenerator = PatchGeneratorService.shared
        let patches = patchGenerator.generatePatches(from: response, projectURL: projectURL)
        
        guard !patches.isEmpty else { return }
        
        // Convert patches to CodeChange objects for display
        let applyService = ApplyCodeService.shared
        var changes: [CodeChange] = []
        
        for patch in patches {
            // Get original content if file exists
            let originalContent: String?
            if FileManager.default.fileExists(atPath: patch.filePath) {
                let fileURL = URL(fileURLWithPath: patch.filePath)
                originalContent = try? String(contentsOf: fileURL, encoding: .utf8)
            } else {
                originalContent = nil
            }
            
            // Apply patch to get new content
            let newContent: String
            do {
                newContent = try patchGenerator.applyPatch(patch, projectURL: projectURL)
                
                // Safety check: Don't create changes with empty content (unless it's a delete operation)
                if newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && patch.operation != .delete {
                    print("⚠️ Warning: Skipping patch - would result in empty content for \(patch.filePath)")
                    continue
                }
            } catch {
                print("⚠️ Error applying patch: \(error)")
                continue // Skip invalid patches
            }
            
            // Create CodeChange
            let change = CodeChange(
                id: patch.id,
                filePath: patch.filePath,
                fileName: (patch.filePath as NSString).lastPathComponent,
                operationType: patch.operation == .insert ? .create : .update,
                originalContent: originalContent,
                newContent: newContent,
                lineRange: patch.range.map { ($0.startLine, $0.endLine) },
                language: detectLanguage(from: patch.filePath)
            )
            
            changes.append(change)
        }
        
        // Set pending changes to show diffs automatically
        if !changes.isEmpty {
            applyService.setPendingChanges(changes)
            
            // Notify that changes are ready to view
            NotificationCenter.default.post(
                name: NSNotification.Name("CodeChangesDetected"),
                object: nil,
                userInfo: ["changes": changes]
            )
        }
    }
    
    private func detectLanguage(from filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "md": return "markdown"
        default: return "plaintext"
        }
    }
    
    // MARK: - Auto-Apply Logic
    
    /// Automatically apply an action if it's ready (has content and file path) and auto-apply is enabled
    private func autoApplyActionIfReady(_ action: AIAction) {
        // Only auto-apply if action has all required data and hasn't been applied yet
        guard let content = action.fileContent ?? action.result,
              let projectURL = editorViewModel?.rootFolderURL,
              let filePath = action.filePath,
              action.status != .completed,
              action.status != .failed else {
            return
        }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let directory = fileURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            action.status = .completed
            
            // Open the file in the editor
            editorViewModel?.openFile(at: fileURL)
            
            print("🟢 [AIViewModel] Auto-applied file: \(filePath)")
        } catch {
            action.status = .failed
            action.error = error.localizedDescription
            print("🔴 [AIViewModel] Failed to auto-apply file \(filePath): \(error.localizedDescription)")
        }
    }
}
