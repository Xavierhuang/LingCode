//
//  TodoListPlanner.swift
//  LingCode
//
//  Generates todo lists for complex prompts (Cursor feature)
//  Shows actionable todo items before execution
//

import Foundation

/// Todo item for complex task breakdown
struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String?
    var status: TodoStatus
    var estimatedTime: String?
    
    enum TodoStatus: String {
        case pending = "pending"
        case inProgress = "in_progress"
        case completed = "completed"
        case skipped = "skipped"
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        status: TodoStatus = .pending,
        estimatedTime: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.estimatedTime = estimatedTime
    }
}

/// Service that generates todo lists for complex prompts
class TodoListPlanner {
    static let shared = TodoListPlanner()
    
    private let aiService: AIProviderProtocol = ServiceContainer.shared.ai
    
    private init() {}
    
    /// Generate a todo list for a complex prompt
    /// Returns todo items that can be executed step-by-step
    func generateTodoList(
        for prompt: String,
        context: String?,
        projectURL: URL?,
        completion: @escaping (Result<[TodoItem], Error>) -> Void
    ) {
        let planningPrompt = buildPlanningPrompt(userPrompt: prompt, context: context)
        
        // Use a quick, focused call to generate the plan
        Task {
            do {
                let response = try await aiService.sendMessage(
                    planningPrompt,
                    context: nil,
                    images: [],
                    tools: nil
                )
                
                let todos = parseTodoList(from: response)
                DispatchQueue.main.async {
                    completion(.success(todos))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Build prompt specifically for planning/todo generation
    private func buildPlanningPrompt(userPrompt: String, context: String?) -> String {
        var prompt = """
        Break down the following task into a clear, actionable todo list. Each item should be a specific, executable step.
        
        Task: \(userPrompt)
        """
        
        if let context = context, !context.isEmpty {
            prompt += "\n\nContext:\n\(context)"
        }
        
        prompt += """
        
        Output ONLY a numbered list of todo items in this exact format:
        
        1. [Action verb] [what to do] - [brief description if needed]
        2. [Action verb] [what to do] - [brief description if needed]
        3. ...
        
        Examples:
        1. Create User model with name and email fields
        2. Add authentication service with login method
        3. Update UI to show user profile
        4. Write unit tests for User model
        
        Be specific and actionable. Each item should be something that can be completed independently.
        """
        
        return prompt
    }
    
    /// Parse todo list from AI response
    private func parseTodoList(from response: String) -> [TodoItem] {
        var todos: [TodoItem] = []
        let lines = response.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Match numbered list items: "1. Task description" or "1) Task description"
            if let regex = try? NSRegularExpression(pattern: #"^(\d+)[\.\)]\s*(.+)$"#, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
               match.numberOfRanges > 2,
               let titleRange = Range(match.range(at: 2), in: trimmed) {
                let title = String(trimmed[titleRange])
                    .trimmingCharacters(in: .whitespaces)
                
                // Split title and description if there's a dash
                let parts = title.components(separatedBy: " - ")
                let todoTitle = parts.first?.trimmingCharacters(in: .whitespaces) ?? title
                let description = parts.count > 1 ? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) : nil
                
                if !todoTitle.isEmpty {
                    todos.append(TodoItem(
                        title: todoTitle,
                        description: description
                    ))
                }
            }
            // Also match markdown list items: "- Task" or "* Task"
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let title = String(trimmed.dropFirst(2))
                    .trimmingCharacters(in: .whitespaces)
                
                let parts = title.components(separatedBy: " - ")
                let todoTitle = parts.first?.trimmingCharacters(in: .whitespaces) ?? title
                let description = parts.count > 1 ? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) : nil
                
                if !todoTitle.isEmpty {
                    todos.append(TodoItem(
                        title: todoTitle,
                        description: description
                    ))
                }
            }
        }
        
        return todos
    }
}
