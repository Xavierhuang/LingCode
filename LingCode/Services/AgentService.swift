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
    private let maxRecentActions = 5
    private let maxDoneRejectionsNoWrites = 1
    private var doneRejectedNoWritesCount = 0
    private var noToolUseCount = 0
    private let maxNoToolUseRetries = 2
    private let maxRepeatedSearches = 2  // Stop after 2 searches for same/similar query

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
        // Ensure previous action is complete before starting new iteration
        guard currentActionStep == nil else {
            // Previous step still running - this shouldn't happen, but guard against it
            return
        }
        
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
                    // Don't break immediately - continue streaming to get full content
                    // Only break if we have tool calls AND it's not a write_file (which needs content)
                    if !detectedToolCalls.isEmpty {
                        let isWriteFile = detectedToolCalls.contains { $0.name == "write_file" }
                        if !isWriteFile {
                            break
                        }
                        // For write_file, check if we have content before breaking
                        if let tc = detectedToolCalls.first(where: { $0.name == "write_file" }),
                           let content = tc.input["content"]?.value as? String,
                           !content.isEmpty {
                            break
                        }
                    }
                }
                
                self.clearThinkingStep()
                
                let flushedToolCalls = ToolCallHandler.shared.flush()
                detectedToolCalls.append(contentsOf: flushedToolCalls)
                
                guard let toolCall = detectedToolCalls.first, let decision = self.convertToolCallToDecision(toolCall) else {
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
        default:
            return nil
        }
    }
    
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
                    AgentValidationService.shared.validateCodeAfterWrite(fileURL: fullPath, projectURL: projectURL) { result in
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
            
            // Check for repeated searches - if we've searched for this before, skip
            let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let similarSearchCount = searchQueries.filter { 
                $0.lowercased().contains(normalizedQuery) || normalizedQuery.contains($0.lowercased())
            }.count
            
            if similarSearchCount >= maxRepeatedSearches {
                onOutput("Search skipped: Already searched for '\(query)' multiple times. Try a different approach.")
                failedActions.insert("search:\(normalizedQuery)")
                onComplete(false, "Repeated search detected - try writing code instead")
                return
            }
            
            searchQueries.append(normalizedQuery)
            
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
        searchQueries.removeAll()  // Clear search history
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
            // Create a mutable copy, update it, then reassign to trigger @Published
            var updatedStep = steps[index]
            if let st = status { updatedStep.status = st }
            if let e = error { updatedStep.error = e }
            if let o = output {
                if append { updatedStep.output = (updatedStep.output ?? "") + o }
                else { updatedStep.output = o }
            }
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
