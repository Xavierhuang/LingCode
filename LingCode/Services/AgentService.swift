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
    private let maxRecentActions = 5
    private let maxDoneRejectionsNoWrites = 1
    private var doneRejectedNoWritesCount = 0
    private var noToolUseCount = 0
    private let maxNoToolUseRetries = 2

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
        clearThinkingStep()
        for step in steps where step.status == .running {
            updateStep(step.id, status: .cancelled)
        }
        pendingApproval = nil
        pendingApprovalReason = nil
        pendingExecutionContext = nil
    }
    
    func runTask(_ taskDescription: String, projectURL: URL?, context: String?, images: [AttachedImage] = [], onStepUpdate: @escaping (AgentStep) -> Void, onComplete: @escaping (AgentTaskResult) -> Void) {
        guard !isRunning else { return }
        
        let task = AgentTask(description: taskDescription, projectURL: projectURL, startTime: Date())
        resetForNewTask(task)
        AgentHistoryService.shared.saveAgentTask(task, steps: [], result: nil, status: .running)
        
        var enrichedContext = context ?? ""
        if let projectURL = projectURL, isVagueTask(taskDescription) {
            let files = listProjectFiles(at: projectURL, maxDepth: 2)
            if !files.isEmpty {
                enrichedContext = "Project files:\n\(files.prefix(30).joined(separator: "\n"))\n\n\(enrichedContext)"
            }
        }
        
        runNextIteration(task: task, projectURL: projectURL, originalContext: enrichedContext.isEmpty ? nil : enrichedContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
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
            executeDecision(decision, projectURL: context.projectURL, onOutput: { output in
                self.updateStep(stepId, output: output, append: true)
                context.onStepUpdate(self.steps.first(where: { $0.id == stepId })!)
            }, onComplete: { success, output in
                self.updateStep(stepId, status: success ? .completed : .failed, error: success ? nil : output)
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

    private func runNextIteration(task: AgentTask, projectURL: URL?, originalContext: String?, images: [AttachedImage] = [], onStepUpdate: @escaping (AgentStep) -> Void, onComplete: @escaping (AgentTaskResult) -> Void) {
        iterationCount += 1
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
                let filesRead = AgentStepHelpers.filesRead(from: self.steps, normalizePath: normalizePath)
                let filesWrittenCount = AgentStepHelpers.countFilesWritten(self.steps)
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
                
                let prompt = AgentPromptBuilder.buildPrompt(task: task, history: history, filesRead: filesRead, agentMemory: agentMemory, loopDetectionHint: loopDetectionHint, requiresModifications: requiresModifications, noFilesWrittenYet: noFilesWrittenYet, iterationCount: self.iterationCount, filesWrittenCount: filesWrittenCount, projectStructure: projectStructure)
                
                var agentTools: [AITool] = [.runTerminalCommand(), .writeFile(), .codebaseSearch(), .searchWeb(), .readFile(), .readDirectory(), .done()]
                
                // Dynamic tool filtering to prevent loops
                if self.iterationCount > 3 && !filesRead.isEmpty && filesWrittenCount == 0 && requiresModifications {
                    agentTools.removeAll { ["codebase_search", "search_web", "read_directory", "read_file"].contains($0.name) }
                }
                
                let forceToolName = (self.iterationCount >= 8 && filesWrittenCount == 0 && requiresModifications) ? "write_file" : nil
                
                let stream = aiService.streamMessage(prompt, context: originalContext, images: images, maxTokens: nil, systemPrompt: nil, tools: agentTools, forceToolName: forceToolName)
                
                var accumulatedResponse = ""
                var detectedToolCalls: [ToolCall] = []
                
                for try await chunk in stream {
                    if isCancelled || Task.isCancelled { break }
                    accumulatedResponse += chunk
                    
                    // Handle heartbeat - convert thinking step to action step
                    if chunk.contains("TOOL_STARTING:") {
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
                                }
                            }
                        }
                        continue
                    }
                    
                    // Throttled live code updates
                    if let activeStep = self.currentActionStep, activeStep.type == .codeGeneration {
                        if let content = self.extractPartialContent(from: accumulatedResponse) {
                            let now = Date()
                            if now.timeIntervalSince(lastUIUpdateTime) > 0.05 {
                                await MainActor.run {
                                    self.updateStepStreamingCode(activeStep.id, code: content)
                                    self.lastUIUpdateTime = now
                                }
                            }
                        }
                    }
                    
                    // Standard UI update
                    await MainActor.run {
                        self.streamingText = accumulatedResponse
                        if self.currentActionStep == nil && self.currentThinkingStep != nil {
                            self.updateStep(self.currentThinkingStep!.id, output: accumulatedResponse, append: false)
                        }
                    }
                    
                    let (_, toolCalls) = ToolCallHandler.shared.processChunk(chunk, projectURL: projectURL)
                    detectedToolCalls.append(contentsOf: toolCalls)
                    if !detectedToolCalls.isEmpty { break }
                }
                
                self.clearThinkingStep()
                
                let flushedToolCalls = ToolCallHandler.shared.flush()
                detectedToolCalls.append(contentsOf: flushedToolCalls)
                
                guard let toolCall = detectedToolCalls.first, let decision = AgentToolCallConverter.convert(toolCall) else {
                    self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    return
                }

                // Merge heartbeat step with final decision data
                let finalStep: AgentStep = await MainActor.run {
                    if let existing = self.currentActionStep, let idx = self.steps.firstIndex(where: { $0.id == existing.id }) {
                        self.steps[idx].description = decision.displayDescription
                        self.steps[idx].output = decision.thought
                        self.steps[idx].targetFilePath = decision.filePath
                        if let code = decision.code { self.steps[idx].streamingCode = code }
                        self.currentActionStep = nil
                        return self.steps[idx]
                    } else {
                        let newStep = AgentStep(type: AgentStepHelpers.mapType(decision.action), description: decision.displayDescription, status: .running, output: decision.thought, streamingCode: decision.code, targetFilePath: decision.filePath)
                        self.addStep(newStep, onUpdate: onStepUpdate)
                        return newStep
                    }
                }
                
                // Execute tool
                await MainActor.run {
                    self.executeDecision(decision, projectURL: projectURL, onOutput: { output in
                        self.updateStep(finalStep.id, output: output, append: true)
                    }, onComplete: { success, output in
                        self.updateStep(finalStep.id, status: success ? .completed : .failed, error: success ? nil : output)
                        self.runNextIteration(task: task, projectURL: projectURL, originalContext: originalContext, images: images, onStepUpdate: onStepUpdate, onComplete: onComplete)
                    })
                }

            } catch {
                self.finalize(success: false, error: error.localizedDescription, projectURL: projectURL, onComplete: onComplete)
            }
        }
    }

    // MARK: - Decision Execution
    
    func executeDecision(_ decision: AgentDecision, projectURL: URL?, onOutput: @escaping (String) -> Void, onComplete: @escaping (Bool, String) -> Void) {
        switch decision.action.lowercased() {
        case "done":
            let summary = decision.thought ?? "Task completed successfully"
            onOutput("Task Complete\n\n\(summary)")
            onComplete(true, summary)
            
        case "terminal":
            guard let cmd = decision.command, !cmd.isEmpty else {
                onComplete(false, "No command provided")
                return
            }
            terminalService.execute(cmd, workingDirectory: projectURL, onOutput: { onOutput($0) }, onError: { onOutput("Error: \($0)") }, onComplete: { onComplete($0 == 0, "Exit code: \($0)") })
            
        case "code":
            guard let filePath = decision.filePath, let code = decision.code else {
                onComplete(false, "Missing filePath or code")
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
                        onComplete(true, "Content matches existing file.")
                        return
                    }
                }
                
                let originalContent = fileExisted ? (try? String(contentsOf: fullPath, encoding: .utf8)) : nil
                try code.write(to: fullPath, atomically: true, encoding: .utf8)
                
                onOutput("File written: \(filePath)\n\n--- \(filePath) ---\n\(code)\n--- End of \(filePath) ---")
                
                NotificationCenter.default.post(name: NSNotification.Name(fileExisted ? "FileUpdated" : "FileCreated"), object: nil, userInfo: ["fileURL": fullPath, "filePath": filePath, "content": code, "originalContent": originalContent ?? ""])
                
                if let projectURL = projectURL {
                    validateCodeAfterWrite(fileURL: fullPath, projectURL: projectURL) { result in
                        switch result {
                        case .success: onComplete(true, "File written and validated")
                        case .warnings(let msgs): onOutput("Warnings:\n\(msgs.joined(separator: "\n"))"); onComplete(true, "File written with warnings")
                        case .errors(let msgs):
                            onOutput("Validation Errors:\n\(msgs.joined(separator: "\n"))")
                            Task { @MainActor in
                                let contextualError = await self.enrichErrorWithGraphRAG(errors: msgs, fileURL: fullPath, projectURL: projectURL)
                                onComplete(false, contextualError)
                            }
                        case .skipped: onComplete(true, "File written successfully")
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
                let summary = results.prefix(5).map { "- \($0.title): \($0.snippet.prefix(100))" }.joined(separator: "\n")
                onOutput("Search results:\n\(summary)")
                onComplete(true, "Found \(results.count) results")
            }
            
        case "file":
            guard let path = decision.filePath else { onComplete(false, "No path"); return }
            let url = (projectURL ?? URL(fileURLWithPath: "")).appendingPathComponent(path)
            if let content = try? String(contentsOf: url) {
                onOutput(content)
                onComplete(true, "Read file")
            } else {
                onComplete(false, "Failed to read file")
            }
             
        case "directory":
            guard let path = decision.filePath else { onComplete(false, "No path provided"); return }
            let recursive = decision.thought == "recursive"
            let toolCall = ToolCall(id: UUID().uuidString, name: "read_directory", input: ["directory_path": AnyCodable(path), "recursive": AnyCodable(recursive)])
            if let projectURL = projectURL { ToolExecutionService.shared.setProjectURL(projectURL) }
            Task {
                do {
                    let result = try await ToolExecutionService.shared.executeToolCall(toolCall)
                    if result.isError { onComplete(false, result.content) }
                    else { onOutput(result.content); onComplete(true, "Read directory") }
                } catch { onComplete(false, "Error: \(error.localizedDescription)") }
            }
             
        default:
            onComplete(false, "Unknown action: \(decision.action)")
        }
    }

    // MARK: - Validation
    
    enum ValidationResult {
        case success, warnings([String]), errors([String]), skipped
    }
    
    func validateCodeAfterWrite(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        let shadowService = ShadowWorkspaceService.shared
        
        guard let shadowWorkspaceURL = shadowService.getShadowWorkspace(for: projectURL) ?? shadowService.createShadowWorkspace(for: projectURL) else {
            validateCodeDirectly(fileURL: fileURL, projectURL: projectURL, completion: completion)
            return
        }
        
        guard let modifiedContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            completion(.errors(["Failed to read modified file content"]))
            return
        }
        
        let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
        
        do {
            try shadowService.prepareShadowWorkspaceForValidation(modifiedFileURL: fileURL, projectURL: projectURL, shadowWorkspaceURL: shadowWorkspaceURL)
            try shadowService.writeToShadowWorkspace(content: modifiedContent, relativePath: relativePath, shadowWorkspaceURL: shadowWorkspaceURL)
            let shadowFileURL = shadowWorkspaceURL.appendingPathComponent(relativePath)
            validateCodeInShadowWorkspace(fileURL: shadowFileURL, shadowWorkspaceURL: shadowWorkspaceURL, originalProjectURL: projectURL, completion: completion)
        } catch {
            validateCodeDirectly(fileURL: fileURL, projectURL: projectURL, completion: completion)
        }
    }
    
    private func validateCodeDirectly(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        LinterService.shared.validate(files: [fileURL], in: projectURL) { lintError in
            if let lintError = lintError {
                switch lintError {
                case .issues(let messages):
                    let errors = messages.filter { $0.lowercased().contains("error") }
                    let warnings = messages.filter { !$0.lowercased().contains("error") }
                    if !errors.isEmpty { completion(.errors(errors)) }
                    else if !warnings.isEmpty { completion(.warnings(warnings)) }
                    else { completion(.success) }
                }
            } else if fileURL.pathExtension.lowercased() == "swift" {
                self.validateSwiftCompilation(fileURL: fileURL, projectURL: projectURL, completion: completion)
            } else {
                completion(.success)
            }
        }
    }
    
    private func validateCodeInShadowWorkspace(fileURL: URL, shadowWorkspaceURL: URL, originalProjectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        LinterService.shared.validate(files: [fileURL], in: shadowWorkspaceURL) { lintError in
            if let lintError = lintError {
                switch lintError {
                case .issues(let messages):
                    let errors = messages.filter { $0.lowercased().contains("error") }
                    let warnings = messages.filter { !$0.lowercased().contains("error") }
                    if !errors.isEmpty { completion(.errors(errors)) }
                    else if !warnings.isEmpty { completion(.warnings(warnings)) }
                    else { completion(.success) }
                }
            } else if fileURL.pathExtension.lowercased() == "swift" {
                self.validateSwiftCompilationInShadow(fileURL: fileURL, shadowWorkspaceURL: shadowWorkspaceURL, originalProjectURL: originalProjectURL, completion: completion)
            } else {
                completion(.success)
            }
        }
    }
    
    private func validateSwiftCompilation(fileURL: URL, projectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        let hasPackageSwift = FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path)
        guard hasPackageSwift else { completion(.skipped); return }
        
        terminalService.execute(
            "swift build 2>&1",
            workingDirectory: projectURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                completion(exitCode == 0 ? .success : .errors(["Compilation failed."]))
            }
        )
    }
    
    private func validateSwiftCompilationInShadow(fileURL: URL, shadowWorkspaceURL: URL, originalProjectURL: URL, completion: @escaping (ValidationResult) -> Void) {
        let hasPackageSwift = FileManager.default.fileExists(atPath: shadowWorkspaceURL.appendingPathComponent("Package.swift").path)
        guard hasPackageSwift else { completion(.skipped); return }
        
        terminalService.execute(
            "swift build 2>&1",
            workingDirectory: shadowWorkspaceURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                completion(exitCode == 0 ? .success : .errors(["Compilation failed in shadow workspace."]))
            }
        )
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
        let finalSummary = success ? (summary ?? AgentSummaryGenerator.generateTaskSummary(from: steps)) : (error ?? "Task failed")
        steps.append(AgentStep(type: .complete, description: "Task Complete", status: .completed, output: finalSummary))
        onComplete(AgentTaskResult(success: success, error: error, steps: steps))
    }

    private func addStep(_ step: AgentStep, onUpdate: @escaping (AgentStep) -> Void) {
        steps.append(step)
        onUpdate(step)
    }

    private func resetForNewTask(_ task: AgentTask) {
        isCancelled = false; isRunning = true; steps = []; iterationCount = 0
        actionHistory.removeAll(); failedActions.removeAll(); recentActions.removeAll()
        currentThinkingStep = nil; currentActionStep = nil; currentTask = task
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
        steps.map { step in
            let output = step.output ?? ""
            // Read steps contain file content - allow more so the agent can use it without re-reading
            let limit = (step.type == .fileOperation && step.description.hasPrefix("Read:")) ? 6000 : 1200
            let truncated = output.count <= limit ? output : String(output.prefix(limit)) + "\n...(truncated)"
            return "Step: \(step.description)\nStatus: \(step.status)\nOutput: \(truncated)"
        }.joined(separator: "\n---\n")
    }
    
    private func updateStep(_ id: UUID, status: AgentStepStatus? = nil, result: String? = nil, error: String? = nil, output: String? = nil, append: Bool = false) {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            if let st = status { steps[index].status = st }
            if let e = error { steps[index].error = e }
            if let o = output {
                if append { steps[index].output = (steps[index].output ?? "") + o }
                else { steps[index].output = o }
            }
        }
    }
}
