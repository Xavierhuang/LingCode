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
    @Published var showThinkingProcess: Bool = true
    @Published var autoExecuteCode: Bool = false // Disabled by default to prevent accidental code deletion
    @Published var createdFiles: [URL] = []
    
    // Project generation
    @Published var generationProgress: ProjectGenerationProgress?
    @Published var isGeneratingProject: Bool = false
    @Published var projectMode: Bool = false
    
    private let aiService = AIService.shared
    private let stepParser = AIStepParser.shared
    private let actionExecutor = ActionExecutor.shared
    private let projectGenerator = ProjectGeneratorService.shared
    
    // Reference to editor state (set by EditorViewModel)
    weak var editorViewModel: EditorViewModel?
    
    func sendMessage(context: String? = nil, projectURL: URL? = nil, images: [AttachedImage] = []) {
        guard !currentInput.isEmpty, !isLoading else { return }
        
        let userMessage = currentInput
        currentInput = ""
        isLoading = true
        errorMessage = nil
        createdFiles = []
        generationProgress = nil
        
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
        
        // Convert AITaskType to AITask for model selection
        let aiTask: AITask = {
            switch taskType {
            case .autocomplete: return .autocomplete
            case .inlineEdit: return .inlineEdit
            case .refactor: return .refactor
            case .debug: return .debug
            case .generate: return .generate
            case .chat: return .chat
            }
        }()
        
        // Model selection based on task (with offline-first support)
        let localModelService = LocalModelService.shared
        let (_, _) = localModelService.selectModel(
            for: aiTask,
            requiresReasoning: aiTask == .refactor || aiTask == .debug
        )
        
        // Show offline mode badge if active
        if let badge = localModelService.offlineModeBadge {
            print("ℹ️ \(badge)")
        }
        
        // TODO: Apply model selection to AI service (requires updating AIService to accept model parameter)
        
        // Clear previous thinking steps
        thinkingSteps = []
        currentPlan = nil
        currentActions = []
        
        conversation.addMessage(AIMessage(role: .user, content: userMessage))
        
        // Build full context with Cursor-like system prompt FIRST
        var fullContext = context ?? ""
        
        // Use Cursor system prompt (this is the PRIMARY prompt)
        let cursorPromptService = CursorSystemPromptService.shared
        let contextBuilder = CursorContextBuilder.shared
        
        // Build context from editor state (if available)
        var editorContext = ""
        if let editorVM = editorViewModel {
            editorContext = contextBuilder.buildContext(
                editorState: editorVM.editorState,
                cursorPosition: editorVM.editorState.cursorPosition,
                selectedText: editorVM.editorState.selectedText,
                projectURL: projectURL,
                includeDiagnostics: true,
                includeGitDiff: true,
                includeFileGraph: true
            )
        }
        
        // Use Cursor system prompt as the base
        let systemPrompt = cursorPromptService.getEnhancedSystemPrompt(context: editorContext.isEmpty ? nil : editorContext)
        
        // Use appropriate prompt enhancement (this adds to user message, not system prompt)
        let enhancedPrompt: String
        if isProjectRequest {
            enhancedPrompt = stepParser.enhancePromptForSteps(userMessage)
        } else if isRunRequest {
            enhancedPrompt = stepParser.enhancePromptForRun(userMessage, projectURL: projectURL)
        } else {
            enhancedPrompt = stepParser.enhancePromptForSteps(userMessage)
        }
        
        // Combine: System prompt first, then context, then enhanced user prompt
        fullContext = systemPrompt + "\n\n" + fullContext
        
        var assistantResponse = ""
        let assistantMessage = AIMessage(role: .assistant, content: "")
        conversation.addMessage(assistantMessage)
        let assistantMessageIndex = conversation.messages.count - 1
        
        // Track response chunks for step-by-step parsing
        var accumulatedResponse = ""
        
        // Add initial thinking step for all requests
        let initialStep = AIThinkingStep(
            type: .thinking,
            content: "Analyzing your request...",
            isComplete: false
        )
        thinkingSteps.append(initialStep)
        
        // Try streaming first for better UX
        // Use higher token limit for project generation (multiple files need more tokens)
        let maxTokens = isProjectRequest ? 16384 : nil // 16k tokens for projects, default (4k) for regular requests
        
        // Track latency
        let contextStart = Date()
        let contextTime = Date().timeIntervalSince(contextStart)
        LatencyOptimizer.shared.recordContextBuild(contextTime)
        
        // Parse edits from stream as they come
        var detectedEdits: [Edit]? = nil
        
        aiService.streamMessage(
            enhancedPrompt,
            context: fullContext.isEmpty ? nil : fullContext,
            images: images,
            maxTokens: maxTokens,
            onChunk: { chunk in
                accumulatedResponse += chunk
                
                // Try to parse edits from stream early
                if detectedEdits == nil {
                    detectedEdits = LatencyOptimizer.shared.parseEditsFromStream(accumulatedResponse)
                }
                
                // Parse steps incrementally as we receive chunks
                let parsed = self.stepParser.parseResponse(accumulatedResponse)
                DispatchQueue.main.async {
                    // Merge thinking steps instead of replacing - preserve existing thinking steps
                    if !parsed.steps.isEmpty {
                        var mergedSteps = self.thinkingSteps
                        for newStep in parsed.steps {
                            // Only add if it's not already present (avoid duplicates)
                            if !mergedSteps.contains(where: { $0.id == newStep.id }) {
                                mergedSteps.append(newStep)
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
                            // Update existing action with streaming content
                            let existingAction = self.currentActions[existingIndex]
                            existingAction.fileContent = parsedAction.fileContent ?? existingAction.fileContent
                            // Note: filePath is let constant, can't be modified
                            if existingAction.status == .pending {
                                existingAction.status = .executing
                            }
                        } else {
                            // Add new action
                            self.currentActions.append(parsedAction)
                        }
                    }
                    
                    // Update message with accumulated response for streaming display
                    self.conversation.messages[assistantMessageIndex] = AIMessage(
                        id: self.conversation.messages[assistantMessageIndex].id,
                        role: .assistant,
                        content: accumulatedResponse
                    )
                }
            },
            onComplete: {
                assistantResponse = accumulatedResponse
                
                // Final parse
                let parsed = self.stepParser.parseResponse(accumulatedResponse)
                
                // Merge thinking steps instead of replacing - preserve existing thinking steps
                var mergedSteps = self.thinkingSteps
                for newStep in parsed.steps {
                    // Only add if it's not already present (avoid duplicates)
                    if !mergedSteps.contains(where: { $0.id == newStep.id }) {
                        mergedSteps.append(newStep)
                    }
                }
                self.thinkingSteps = mergedSteps
                
                // Update plan and actions
                if parsed.plan != nil {
                    self.currentPlan = parsed.plan
                }
                self.currentActions = parsed.actions
                
                // Update message with full response
                self.conversation.messages[assistantMessageIndex] = AIMessage(
                    id: self.conversation.messages[assistantMessageIndex].id,
                    role: .assistant,
                    content: assistantResponse
                )
                
                // Check for missing referenced files (especially for website projects)
                if isProjectRequest {
                    self.checkAndRequestMissingFiles(
                        from: assistantResponse,
                        parsedActions: parsed.actions,
                        projectURL: projectURL,
                        originalPrompt: userMessage
                    )
                }
                
                // Automatically detect and show code changes (Cursor-like)
                self.detectAndShowCodeChanges(from: assistantResponse, projectURL: projectURL)
                
                // Execute code generation if enabled
                if self.autoExecuteCode {
                    self.executeCodeGeneration(from: assistantResponse, projectURL: projectURL)
                } else {
                    self.isLoading = false
                    self.isGeneratingProject = false
                }
            },
            onError: { error in
                // Fallback to non-streaming if streaming fails
                self.aiService.sendMessage(
                    enhancedPrompt,
                    context: fullContext.isEmpty ? nil : fullContext,
                    images: images,
                    onResponse: { response in
                        assistantResponse = response
                        
                        // Parse steps from response
                        let parsed = self.stepParser.parseResponse(response)
                        self.thinkingSteps = parsed.steps
                        self.currentPlan = parsed.plan
                        self.currentActions = parsed.actions
                        
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
                    },
                    onError: { error in
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.isGeneratingProject = false
                            let errorService = ErrorHandlingService.shared
                            self.errorMessage = errorService.formatError(error)
                        }
                    }
                )
            }
        )
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
        aiService.setAPIKey(key, provider: provider)
    }
    
    func hasAPIKey() -> Bool {
        return aiService.getAPIKey() != nil
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
        
        aiService.sendMessage(prompt, context: nil) { response in
            // Extract code from response
            var code = response
            
            // Remove markdown code blocks if present
            if code.contains("```") {
                let parts = code.components(separatedBy: "```")
                if parts.count >= 2 {
                    code = parts[1]
                    // Remove language identifier if present
                    if let newlineIndex = code.firstIndex(of: "\n") {
                        code = String(code[code.index(after: newlineIndex)...])
                    }
                }
            }
            
            completion(code.trimmingCharacters(in: .whitespacesAndNewlines))
        } onError: { error in
            print("Inline edit error: \(error)")
            completion(nil)
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
                newContent = try patchGenerator.applyPatch(patch)
                
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
}
