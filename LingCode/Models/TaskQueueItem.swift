//
//  TaskQueueItem.swift
//  LingCode
//
//  Task queue item for managing multiple AI tasks (Cursor feature)
//

import Foundation

/// A queued AI task
struct TaskQueueItem: Identifiable, Equatable {
    let id: UUID
    let prompt: String
    let timestamp: Date
    var status: TaskStatus
    var result: String?
    var error: String?
    var priority: TaskPriority
    
    enum TaskStatus: String, Equatable {
        case pending = "pending"
        case executing = "executing"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }
    
    enum TaskPriority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        
        static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    init(
        id: UUID = UUID(),
        prompt: String,
        timestamp: Date = Date(),
        status: TaskStatus = .pending,
        result: String? = nil,
        error: String? = nil,
        priority: TaskPriority = .normal
    ) {
        self.id = id
        self.prompt = prompt
        self.timestamp = timestamp
        self.status = status
        self.result = result
        self.error = error
        self.priority = priority
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
