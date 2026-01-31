//
//  AgentSummaryGenerator.swift
//  LingCode
//
//  Generates task summary and learnings from completed steps (extracted from AgentService).
//

import Foundation

enum AgentSummaryGenerator {
    static func generateTaskSummary(from steps: [AgentStep]) -> String {
        var summaryParts: [String] = []
        var filesWritten: [String] = []
        var filesRead: [String] = []
        var commandsExecuted: [String] = []

        for step in steps {
            if step.status == .completed {
                if step.description.hasPrefix("Write: ") {
                    let fileName = String(step.description.dropFirst("Write: ".count))
                    filesWritten.append(fileName)
                } else if step.description.hasPrefix("Read: ") {
                    let fileName = String(step.description.dropFirst("Read: ".count))
                    if !filesRead.contains(fileName) {
                        filesRead.append(fileName)
                    }
                } else if step.description.hasPrefix("Exec: ") {
                    let cmd = String(step.description.dropFirst("Exec: ".count))
                    commandsExecuted.append(cmd)
                }
            }
        }

        if !filesWritten.isEmpty {
            summaryParts.append("Files Created/Modified: \(filesWritten.joined(separator: ", "))")
        }
        if !filesRead.isEmpty && filesRead.count <= 10 {
            summaryParts.append("Files Analyzed: \(filesRead.count) file(s)")
        }
        if !commandsExecuted.isEmpty {
            summaryParts.append("Commands Executed: \(commandsExecuted.count) command(s)")
        }

        if summaryParts.isEmpty {
            return "Task completed successfully. \(steps.filter { $0.status == .completed }.count) step(s) executed."
        }
        return "Task completed successfully.\n\n" + summaryParts.joined(separator: "\n")
    }

    static func extractLearnings(from steps: [AgentStep]) -> String {
        var learnings: [String] = []
        for step in steps {
            if step.status == .completed, let output = step.output {
                if output.contains("SwiftUI") && output.contains("View") {
                    learnings.append("User prefers SwiftUI Views to be split into separate files.")
                }
                if output.contains("struct") && !output.contains("class") {
                    learnings.append("User prefers structs over classes when possible.")
                }
            }
        }
        return learnings.joined(separator: "\n")
    }
}
