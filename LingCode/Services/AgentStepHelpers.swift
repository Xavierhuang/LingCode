//
//  AgentStepHelpers.swift
//  LingCode
//
//  Helpers for agent steps: counting writes, mapping action to step type, extracting file lists.
//

import Foundation

enum AgentStepHelpers {
    /// Number of completed code-generation (write) steps.
    static func countFilesWritten(_ steps: [AgentStep]) -> Int {
        steps.filter { $0.type == .codeGeneration && $0.status == .completed }.count
    }

    /// Map tool/action name to AgentStepType.
    static func mapType(_ action: String) -> AgentStepType {
        switch action.lowercased() {
        case "terminal", "run_terminal_command": return .terminal
        case "code", "write_file": return .codeGeneration
        case "search", "search_web", "codebase_search": return .webSearch
        case "file", "read_file": return .fileOperation
        case "directory", "read_directory": return .fileOperation
        case "done": return .complete
        default: return .thinking
        }
    }

    /// Extract normalized paths of files that were read (from completed Read: steps).
    static func filesRead(from steps: [AgentStep], normalizePath: (String) -> String) -> [String] {
        steps.compactMap { step -> String? in
            guard step.type == .fileOperation, step.status == .completed, step.description.hasPrefix("Read: ") else { return nil }
            let filePath = String(step.description.dropFirst("Read: ".count))
            return normalizePath(filePath)
        }
    }

    /// Extract normalized paths of files that were written (from completed Write: steps).
    static func filesWritten(from steps: [AgentStep], normalizePath: (String) -> String) -> [String] {
        steps.compactMap { step -> String? in
            guard step.type == .codeGeneration, step.status == .completed, step.description.hasPrefix("Write: ") else { return nil }
            let filePath = String(step.description.dropFirst("Write: ".count))
            return normalizePath(filePath)
        }
    }
}
