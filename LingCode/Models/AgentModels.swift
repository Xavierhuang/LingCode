//
//  AgentModels.swift
//  LingCode
//
//  Shared models for the autonomous agent (extracted from AgentService).
//

import Foundation

struct AgentTask: Identifiable {
    let id = UUID()
    let description: String
    let projectURL: URL?
    let startTime: Date
}

struct AgentStep: Identifiable {
    let id = UUID()
    var type: AgentStepType  // var to allow conversion from thinking -> action
    var description: String
    var status: AgentStepStatus
    var output: String?
    var result: String?
    var error: String?
    var timestamp: Date = Date()
    
    // Streaming code content for write_file actions - populated immediately when step is created
    var streamingCode: String?
    // File path for code operations
    var targetFilePath: String?
}

enum AgentStepType: String, Codable {
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

enum AgentStepStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

struct AgentTaskResult: Codable {
    let success: Bool
    let error: String?
    let steps: [AgentStepCodable]

    init(success: Bool, error: String?, steps: [AgentStep]) {
        self.success = success
        self.error = error
        self.steps = steps.map { AgentStepCodable(from: $0) }
    }
}

struct AgentStepCodable: Codable {
    let id: UUID
    let type: AgentStepType
    let description: String
    let status: AgentStepStatus
    let output: String?
    let result: String?
    let error: String?
    let timestamp: Date
    let streamingCode: String?
    let targetFilePath: String?

    init(from step: AgentStep) {
        self.id = step.id
        self.type = step.type
        self.description = step.description
        self.status = step.status
        self.output = step.output
        self.result = step.result
        self.error = step.error
        self.timestamp = step.timestamp
        self.streamingCode = step.streamingCode
        self.targetFilePath = step.targetFilePath
    }
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
        description ?? defaultDescription
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
