//
//  AgentTaskIntent.swift
//  LingCode
//
//  Detects whether a task description implies file modifications (not just analysis).
//

import Foundation

enum AgentTaskIntent {
    /// True if the task is read-only (analyze, explain, inspect) — do not require file writes.
    static func taskIsReadOnly(_ taskDescription: String) -> Bool {
        let lower = taskDescription.lowercased()
        return lower.contains("analyze") || lower.contains("analyse") || lower.contains("explain")
            || lower.contains("inspect") || lower.contains("review") || lower.contains("read")
            || lower.contains("understand") || lower.contains("summarize") || lower.contains("describe")
    }
    
    /// True if the task description implies the user wants actual file changes (not just reading/analyzing).
    static func taskRequiresModifications(_ taskDescription: String) -> Bool {
        if taskIsReadOnly(taskDescription) { return false }
        let lower = taskDescription.lowercased()
        return lower.contains("upgrade") || lower.contains("modify") || lower.contains("improve")
            || lower.contains("update") || lower.contains("change") || lower.contains("refactor")
            || lower.contains("fix") || lower.contains("add") || lower.contains("implement")
            || lower.contains("modernize") || lower.contains("enhance") || lower.contains("edit")
            || lower.contains("rewrite") || lower.contains("redesign")
    }
}
