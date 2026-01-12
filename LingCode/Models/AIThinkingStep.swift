//
//  AIThinkingStep.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

enum ThinkingStepType: String {
    case planning = "planning"
    case thinking = "thinking"
    case action = "action"
    case result = "result"
    case complete = "complete"
}

struct AIThinkingStep: Identifiable {
    let id: UUID
    let type: ThinkingStepType
    let content: String
    let timestamp: Date
    var isComplete: Bool
    var actionResult: String?
    
    init(
        id: UUID = UUID(),
        type: ThinkingStepType,
        content: String,
        timestamp: Date = Date(),
        isComplete: Bool = false,
        actionResult: String? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.isComplete = isComplete
        self.actionResult = actionResult
    }
}

struct AIPlan {
    let steps: [String]
    let estimatedTime: String?
    let complexity: String?
}

class AIAction: Identifiable, ObservableObject, Equatable {
    let id: UUID
    let name: String
    let description: String
    let parameters: [String: Any]?
    @Published var status: ActionStatus
    @Published var result: String?
    @Published var error: String?
    @Published var fileContent: String?  // Actual file content from AI
    let filePath: String?  // File path for this action
    
    enum ActionStatus {
        case pending
        case executing
        case completed
        case failed
    }
    
    static func == (lhs: AIAction, rhs: AIAction) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.description == rhs.description &&
        lhs.filePath == rhs.filePath &&
        lhs.status == rhs.status &&
        lhs.result == rhs.result &&
        lhs.error == rhs.error &&
        lhs.fileContent == rhs.fileContent
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        parameters: [String: Any]? = nil,
        status: ActionStatus = .pending,
        filePath: String? = nil,
        fileContent: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.parameters = parameters
        self.status = status
        self.filePath = filePath
        self.fileContent = fileContent
    }
}

