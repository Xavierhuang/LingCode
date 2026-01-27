//
//  TaskQueueService.swift
//  LingCode
//
//  Manages a queue of AI tasks (Cursor feature)
//

import Foundation
import Combine

/// Service for managing a queue of AI tasks
@MainActor
class TaskQueueService: ObservableObject {
    static let shared = TaskQueueService()
    
    @Published var queue: [TaskQueueItem] = []
    @Published var isProcessing: Bool = false
    
    private var currentTask: Task<Void, Never>?
    private var currentExecutingItem: TaskQueueItem?
    private var onTaskComplete: ((TaskQueueItem, String?) -> Void)?
    private var onTaskError: ((TaskQueueItem, Error) -> Void)?
    
    private init() {}
    
    /// Add a task to the queue
    func enqueue(
        prompt: String,
        priority: TaskQueueItem.TaskPriority = .normal,
        onComplete: @escaping (TaskQueueItem, String?) -> Void,
        onError: @escaping (TaskQueueItem, Error) -> Void
    ) -> TaskQueueItem {
        let item = TaskQueueItem(
            prompt: prompt,
            priority: priority
        )
        
        queue.append(item)
        queue.sort { $0.priority > $1.priority } // Higher priority first
        
        onTaskComplete = onComplete
        onTaskError = onError
        
        processQueue()
        
        return item
    }
    
    /// Remove a task from the queue
    func remove(_ item: TaskQueueItem) {
        queue.removeAll { $0.id == item.id }
        
        // If removing current task, cancel it
        if item.status == .executing {
            currentTask?.cancel()
            currentTask = nil
            isProcessing = false
            processQueue()
        }
    }
    
    /// Cancel a task
    func cancel(_ item: TaskQueueItem) {
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            var updated = queue[index]
            updated.status = .cancelled
            queue[index] = updated
            
            if updated.status == .executing {
                currentTask?.cancel()
                currentTask = nil
                isProcessing = false
                processQueue()
            }
        }
    }
    
    /// Move task up in priority
    func moveUp(_ item: TaskQueueItem) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }),
              index > 0 else { return }
        
        queue.swapAt(index, index - 1)
    }
    
    /// Move task down in priority
    func moveDown(_ item: TaskQueueItem) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }),
              index < queue.count - 1 else { return }
        
        queue.swapAt(index, index + 1)
    }
    
    /// Clear completed tasks
    func clearCompleted() {
        queue.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }
    
    /// Clear all tasks
    func clearAll() {
        currentTask?.cancel()
        currentTask = nil
        queue.removeAll()
        isProcessing = false
    }
    
    /// Process the queue
    func processQueue() {
        guard !isProcessing else { return }
        guard let nextItem = queue.first(where: { $0.status == .pending }) else {
            isProcessing = false
            return
        }
        
        isProcessing = true
        
        // Update status to executing
        if let index = queue.firstIndex(where: { $0.id == nextItem.id }) {
            var updated = nextItem
            updated.status = .executing
            queue[index] = updated
            currentExecutingItem = updated
        }
        
        // Notify that a task is ready to execute
        // The caller (AIViewModel) will handle the actual execution
        NotificationCenter.default.post(
            name: NSNotification.Name("TaskQueueItemReady"),
            object: nextItem
        )
    }
    
    /// Mark task as completed
    func markCompleted(_ item: TaskQueueItem, result: String?) {
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.status = .completed
            updated.result = result
            queue[index] = updated
            
            if currentExecutingItem?.id == item.id {
                currentExecutingItem = nil
            }
            
            isProcessing = false
            onTaskComplete?(updated, result)
            
            // Process next item
            processQueue()
        }
    }
    
    /// Mark task as failed
    func markFailed(_ item: TaskQueueItem, error: Error) {
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.status = .failed
            updated.error = error.localizedDescription
            queue[index] = updated
            
            if currentExecutingItem?.id == item.id {
                currentExecutingItem = nil
            }
            
            isProcessing = false
            onTaskError?(updated, error)
            
            // Process next item
            processQueue()
        }
    }
    
    /// Get currently executing item
    func getCurrentExecutingItem() -> TaskQueueItem? {
        return currentExecutingItem
    }
}
