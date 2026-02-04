//
//  SubagentService.swift
//  LingCode
//
//  Subagent system for delegating complex tasks to specialized agents
//

import Foundation
import Combine

// MARK: - Subagent Types

/// Specialized subagent types with different capabilities
enum SubagentType: String, Codable, CaseIterable {
    case coder = "coder"
    case reviewer = "reviewer"
    case tester = "tester"
    case documenter = "documenter"
    case debugger = "debugger"
    case researcher = "researcher"
    case refactorer = "refactorer"
    case architect = "architect"
    
    var displayName: String {
        switch self {
        case .coder: return "Coder"
        case .reviewer: return "Code Reviewer"
        case .tester: return "Test Writer"
        case .documenter: return "Documenter"
        case .debugger: return "Debugger"
        case .researcher: return "Researcher"
        case .refactorer: return "Refactorer"
        case .architect: return "Architect"
        }
    }
    
    var icon: String {
        switch self {
        case .coder: return "chevron.left.forwardslash.chevron.right"
        case .reviewer: return "eye"
        case .tester: return "checkmark.shield"
        case .documenter: return "doc.text"
        case .debugger: return "ladybug"
        case .researcher: return "magnifyingglass"
        case .refactorer: return "arrow.triangle.2.circlepath"
        case .architect: return "building.columns"
        }
    }
    
    var systemPrompt: String {
        switch self {
        case .coder:
            return """
            You are a specialized coding agent. Your job is to write clean, efficient, well-structured code.
            
            Focus on:
            - Writing idiomatic code for the target language
            - Following project conventions and patterns
            - Handling edge cases and errors
            - Writing self-documenting code with clear names
            
            Output complete, runnable code. Include necessary imports and type definitions.
            """
            
        case .reviewer:
            return """
            You are a specialized code review agent. Your job is to find issues and suggest improvements.
            
            Review for:
            - Bugs and logic errors
            - Security vulnerabilities
            - Performance issues
            - Code style and best practices
            - Test coverage gaps
            
            Be specific with line numbers and provide actionable feedback.
            Format: CRITICAL > WARNING > SUGGESTION > GOOD
            """
            
        case .tester:
            return """
            You are a specialized testing agent. Your job is to write comprehensive tests.
            
            Create tests for:
            - Happy path (normal usage)
            - Edge cases (empty, nil, boundaries)
            - Error conditions
            - Integration scenarios
            
            Use the project's testing framework. Include setup/teardown as needed.
            Aim for high coverage of critical paths.
            """
            
        case .documenter:
            return """
            You are a specialized documentation agent. Your job is to write clear documentation.
            
            Document:
            - Public APIs with full parameter descriptions
            - Complex algorithms with explanations
            - Architecture decisions and rationale
            - Usage examples and tutorials
            
            Use appropriate doc comment format for the language.
            Be concise but complete.
            """
            
        case .debugger:
            return """
            You are a specialized debugging agent. Your job is to find and fix bugs.
            
            Approach:
            1. Reproduce the issue (understand symptoms)
            2. Isolate the cause (narrow down)
            3. Identify the root cause (not just symptoms)
            4. Propose a fix
            5. Verify the fix
            
            Explain your reasoning. Add logging/assertions to prevent regression.
            """
            
        case .researcher:
            return """
            You are a specialized research agent. Your job is to gather information and provide recommendations.
            
            When researching:
            - Search the codebase for relevant patterns
            - Look for similar implementations
            - Check documentation and comments
            - Identify dependencies and their usage
            
            Provide summaries with links to specific files and lines.
            """
            
        case .refactorer:
            return """
            You are a specialized refactoring agent. Your job is to improve code structure without changing behavior.
            
            Focus on:
            - Reducing complexity
            - Eliminating duplication
            - Improving naming
            - Extracting reusable components
            - Applying design patterns
            
            Make small, incremental changes. Ensure tests still pass after each change.
            """
            
        case .architect:
            return """
            You are a specialized architecture agent. Your job is to design and evaluate system structure.
            
            Consider:
            - Separation of concerns
            - Dependency management
            - Scalability and performance
            - Maintainability
            - Security boundaries
            
            Create diagrams when helpful. Propose migrations for improvements.
            """
        }
    }
    
    var capabilities: [String] {
        switch self {
        case .coder: return ["write_file", "read_file", "terminal"]
        case .reviewer: return ["read_file", "codebase_search"]
        case .tester: return ["write_file", "read_file", "terminal"]
        case .documenter: return ["write_file", "read_file"]
        case .debugger: return ["read_file", "terminal", "codebase_search"]
        case .researcher: return ["read_file", "codebase_search", "web_search"]
        case .refactorer: return ["write_file", "read_file", "codebase_search"]
        case .architect: return ["read_file", "codebase_search"]
        }
    }
}

// MARK: - Subagent Task

/// A task assigned to a subagent
struct SubagentTask: Identifiable, Equatable {
    let id: UUID
    let type: SubagentType
    let description: String
    let context: SubagentContext
    let parentTaskId: UUID?
    var status: SubagentTaskStatus
    var result: SubagentResult?
    let createdAt: Date
    var completedAt: Date?
    
    init(
        id: UUID = UUID(),
        type: SubagentType,
        description: String,
        context: SubagentContext,
        parentTaskId: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.context = context
        self.parentTaskId = parentTaskId
        self.status = .pending
        self.result = nil
        self.createdAt = Date()
        self.completedAt = nil
    }
    
    static func == (lhs: SubagentTask, rhs: SubagentTask) -> Bool {
        lhs.id == rhs.id
    }
}

enum SubagentTaskStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

struct SubagentContext {
    let projectURL: URL?
    let files: [URL]
    let selectedText: String?
    let additionalContext: String?
}

struct SubagentResult {
    let success: Bool
    let output: String
    let changes: [SubagentChange]
    let errors: [String]
}

struct SubagentChange {
    let file: URL
    let description: String
    let diff: String?
}

// MARK: - Subagent Service

class SubagentService: ObservableObject {
    static let shared = SubagentService()
    
    @Published var activeTasks: [SubagentTask] = []
    @Published var completedTasks: [SubagentTask] = []
    @Published var isProcessing: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let maxConcurrentTasks = 3
    private let maxCompletedTasks = 50
    
    private init() {}
    
    // MARK: - Task Management
    
    /// Create and queue a new subagent task
    func createTask(
        type: SubagentType,
        description: String,
        context: SubagentContext,
        parentTaskId: UUID? = nil
    ) -> SubagentTask {
        let task = SubagentTask(
            type: type,
            description: description,
            context: context,
            parentTaskId: parentTaskId
        )
        
        activeTasks.append(task)
        
        // Auto-start if we have capacity
        processQueue()
        
        return task
    }
    
    /// Cancel a task
    func cancelTask(_ taskId: UUID) {
        if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
            var task = activeTasks[index]
            task.status = .cancelled
            task.completedAt = Date()
            activeTasks.remove(at: index)
            addToCompleted(task)
        }
    }
    
    /// Get task by ID
    func getTask(_ taskId: UUID) -> SubagentTask? {
        return activeTasks.first { $0.id == taskId } ?? completedTasks.first { $0.id == taskId }
    }
    
    /// Get all tasks for a parent task
    func getSubtasks(for parentId: UUID) -> [SubagentTask] {
        let active = activeTasks.filter { $0.parentTaskId == parentId }
        let completed = completedTasks.filter { $0.parentTaskId == parentId }
        return active + completed
    }
    
    // MARK: - Task Processing
    
    private func processQueue() {
        let runningCount = activeTasks.filter { $0.status == .running }.count
        guard runningCount < maxConcurrentTasks else { return }
        
        let pendingTasks = activeTasks.filter { $0.status == .pending }
        let tasksToStart = pendingTasks.prefix(maxConcurrentTasks - runningCount)
        
        for task in tasksToStart {
            startTask(task.id)
        }
    }
    
    private func startTask(_ taskId: UUID) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }
        
        activeTasks[index].status = .running
        isProcessing = true
        
        Task {
            await executeTask(taskId)
        }
    }
    
    private func executeTask(_ taskId: UUID) async {
        guard let task = activeTasks.first(where: { $0.id == taskId }) else { return }
        
        do {
            let result = try await runSubagent(task)
            await completeTask(taskId, result: result)
        } catch {
            await failTask(taskId, error: error.localizedDescription)
        }
    }
    
    private func runSubagent(_ task: SubagentTask) async throws -> SubagentResult {
        // Build the prompt for the subagent
        var prompt = """
        ## Task
        \(task.description)
        
        """
        
        // Add file context
        if !task.context.files.isEmpty {
            prompt += "## Files\n"
            for file in task.context.files {
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    prompt += """
                    
                    ### \(file.lastPathComponent)
                    ```
                    \(content)
                    ```
                    
                    """
                }
            }
        }
        
        // Add selected text
        if let selection = task.context.selectedText, !selection.isEmpty {
            prompt += """
            
            ## Selected Code
            ```
            \(selection)
            ```
            
            """
        }
        
        // Add additional context
        if let additional = task.context.additionalContext {
            prompt += """
            
            ## Additional Context
            \(additional)
            
            """
        }
        
        // Build system prompt with subagent specialization
        let systemPrompt = """
        \(task.type.systemPrompt)
        
        Available capabilities: \(task.type.capabilities.joined(separator: ", "))
        
        Complete the assigned task. Be thorough but concise.
        """
        
        // Call AI service
        let response = try await callAI(systemPrompt: systemPrompt, userPrompt: prompt)
        
        // Parse result
        let changes = parseChanges(response, projectURL: task.context.projectURL)
        
        return SubagentResult(
            success: true,
            output: response,
            changes: changes,
            errors: []
        )
    }
    
    private func callAI(systemPrompt: String, userPrompt: String) async throws -> String {
        var fullResponse = ""
        
        let stream = AIService.shared.streamMessage(
            userPrompt,
            context: nil,
            images: [],
            maxTokens: nil,
            systemPrompt: systemPrompt
        )
        
        for try await chunk in stream {
            fullResponse += chunk
        }
        
        return fullResponse
    }
    
    private func parseChanges(_ response: String, projectURL: URL?) -> [SubagentChange] {
        var changes: [SubagentChange] = []
        
        // Simple parser for file changes in the response
        // Look for patterns like "### filename.swift" followed by code blocks
        let pattern = #"###\s+([^\n]+)\n```[\w]*\n([\s\S]*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches {
                if let fileRange = Range(match.range(at: 1), in: response),
                   let contentRange = Range(match.range(at: 2), in: response) {
                    let fileName = String(response[fileRange]).trimmingCharacters(in: .whitespaces)
                    let content = String(response[contentRange])
                    
                    let fileURL: URL
                    if let projectURL = projectURL {
                        fileURL = projectURL.appendingPathComponent(fileName)
                    } else {
                        fileURL = URL(fileURLWithPath: fileName)
                    }
                    
                    changes.append(SubagentChange(
                        file: fileURL,
                        description: "Generated by \(SubagentType.coder.displayName)",
                        diff: content
                    ))
                }
            }
        }
        
        return changes
    }
    
    @MainActor
    private func completeTask(_ taskId: UUID, result: SubagentResult) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }
        
        var task = activeTasks.remove(at: index)
        task.status = result.success ? .completed : .failed
        task.result = result
        task.completedAt = Date()
        
        addToCompleted(task)
        
        isProcessing = !activeTasks.filter { $0.status == .running }.isEmpty
        processQueue()
    }
    
    @MainActor
    private func failTask(_ taskId: UUID, error: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }
        
        var task = activeTasks.remove(at: index)
        task.status = .failed
        task.result = SubagentResult(success: false, output: "", changes: [], errors: [error])
        task.completedAt = Date()
        
        addToCompleted(task)
        
        isProcessing = !activeTasks.filter { $0.status == .running }.isEmpty
        processQueue()
    }
    
    private func addToCompleted(_ task: SubagentTask) {
        completedTasks.insert(task, at: 0)
        if completedTasks.count > maxCompletedTasks {
            completedTasks = Array(completedTasks.prefix(maxCompletedTasks))
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Delegate a coding task
    func delegateCoding(description: String, files: [URL], projectURL: URL?) -> SubagentTask {
        return createTask(
            type: .coder,
            description: description,
            context: SubagentContext(projectURL: projectURL, files: files, selectedText: nil, additionalContext: nil)
        )
    }
    
    /// Delegate a review task
    func delegateReview(files: [URL], projectURL: URL?) -> SubagentTask {
        return createTask(
            type: .reviewer,
            description: "Review the provided files for issues, bugs, and improvements.",
            context: SubagentContext(projectURL: projectURL, files: files, selectedText: nil, additionalContext: nil)
        )
    }
    
    /// Delegate a testing task
    func delegateTesting(files: [URL], projectURL: URL?) -> SubagentTask {
        return createTask(
            type: .tester,
            description: "Write comprehensive unit tests for the provided files.",
            context: SubagentContext(projectURL: projectURL, files: files, selectedText: nil, additionalContext: nil)
        )
    }
    
    /// Delegate a documentation task
    func delegateDocumentation(files: [URL], projectURL: URL?) -> SubagentTask {
        return createTask(
            type: .documenter,
            description: "Generate documentation for the provided files.",
            context: SubagentContext(projectURL: projectURL, files: files, selectedText: nil, additionalContext: nil)
        )
    }
    
    /// Delegate a debugging task
    func delegateDebugging(description: String, files: [URL], projectURL: URL?) -> SubagentTask {
        return createTask(
            type: .debugger,
            description: description,
            context: SubagentContext(projectURL: projectURL, files: files, selectedText: nil, additionalContext: nil)
        )
    }
    
    /// Create multiple subagents for a complex task
    func createTaskBreakdown(mainTask: String, projectURL: URL?) -> [SubagentTask] {
        var tasks: [SubagentTask] = []
        
        // Create a parent task ID
        let parentId = UUID()
        
        // Researcher first to understand the codebase
        let researchTask = createTask(
            type: .researcher,
            description: "Research the codebase to understand: \(mainTask)",
            context: SubagentContext(projectURL: projectURL, files: [], selectedText: nil, additionalContext: nil),
            parentTaskId: parentId
        )
        tasks.append(researchTask)
        
        // Then architect to plan
        let architectTask = createTask(
            type: .architect,
            description: "Design the approach for: \(mainTask)",
            context: SubagentContext(projectURL: projectURL, files: [], selectedText: nil, additionalContext: nil),
            parentTaskId: parentId
        )
        tasks.append(architectTask)
        
        // Then coder to implement
        let coderTask = createTask(
            type: .coder,
            description: "Implement: \(mainTask)",
            context: SubagentContext(projectURL: projectURL, files: [], selectedText: nil, additionalContext: nil),
            parentTaskId: parentId
        )
        tasks.append(coderTask)
        
        // Then tester to verify
        let testerTask = createTask(
            type: .tester,
            description: "Write tests for: \(mainTask)",
            context: SubagentContext(projectURL: projectURL, files: [], selectedText: nil, additionalContext: nil),
            parentTaskId: parentId
        )
        tasks.append(testerTask)
        
        // Finally reviewer to check
        let reviewerTask = createTask(
            type: .reviewer,
            description: "Review the implementation of: \(mainTask)",
            context: SubagentContext(projectURL: projectURL, files: [], selectedText: nil, additionalContext: nil),
            parentTaskId: parentId
        )
        tasks.append(reviewerTask)
        
        return tasks
    }
}
