//
//  AgentHistoryService.swift
//  LingCode
//
//  Persistent storage for agent task history
//  Enables multiple agents, search, and history management
//

import Foundation
import Combine

/// Represents a completed or in-progress agent task with full history
struct AgentHistoryItem: Identifiable, Codable {
    let id: UUID
    let description: String
    let projectURL: URL?
    let startTime: Date
    var endTime: Date?
    var status: AgentTaskStatus
    var steps: [AgentStepHistory]
    var result: AgentTaskResult?
    var filesChanged: [String]
    var linesAdded: Int
    var linesRemoved: Int
    
    enum AgentTaskStatus: String, Codable {
        case running
        case completed
        case failed
        case cancelled
    }
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    var displayDescription: String {
        if description.count > 50 {
            return String(description.prefix(50)) + "..."
        }
        return description
    }
}

struct AgentStepHistory: Identifiable, Codable {
    let id: UUID
    let type: String
    let description: String
    let status: String
    let output: String?
    let result: String?
    let error: String?
    let timestamp: Date
}

/// Service for managing agent task history
@MainActor
class AgentHistoryService: ObservableObject {
    static let shared = AgentHistoryService()
    
    @Published var historyItems: [AgentHistoryItem] = []
    @Published var searchQuery: String = ""
    
    private let historyFileURL: URL
    private let fileManager = FileManager.default
    
    private init() {
        // Store history in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingCodeDir = appSupport.appendingPathComponent("LingCode")
        
        // Create directory if needed
        try? fileManager.createDirectory(at: lingCodeDir, withIntermediateDirectories: true)
        
        historyFileURL = lingCodeDir.appendingPathComponent("agent_history.json")
        loadHistory()
    }
    
    /// Add or update an agent task in history
    func saveAgentTask(_ task: AgentTask, steps: [AgentStep], result: AgentTaskResult?, status: AgentHistoryItem.AgentTaskStatus) {
        let stepHistory = steps.map { step in
            AgentStepHistory(
                id: step.id,
                type: String(describing: step.type),
                description: step.description,
                status: String(describing: step.status),
                output: step.output,
                result: step.result,
                error: step.error,
                timestamp: step.timestamp
            )
        }
        
        // Calculate file changes from steps
        let filesChanged = extractFilesChanged(from: steps)
        let (linesAdded, linesRemoved) = calculateLineChanges(from: steps)
        
        let historyItem = AgentHistoryItem(
            id: task.id,
            description: task.description,
            projectURL: task.projectURL,
            startTime: task.startTime,
            endTime: status != .running ? Date() : nil,
            status: status,
            steps: stepHistory,
            result: result,
            filesChanged: filesChanged,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved
        )
        
        // Update or add item
        if let index = historyItems.firstIndex(where: { $0.id == task.id }) {
            historyItems[index] = historyItem
        } else {
            historyItems.insert(historyItem, at: 0) // Most recent first
        }
        
        saveHistory()
    }
    
    /// Get filtered history based on search query
    var filteredHistory: [AgentHistoryItem] {
        if searchQuery.isEmpty {
            return historyItems
        }
        
        let query = searchQuery.lowercased()
        return historyItems.filter { item in
            item.description.lowercased().contains(query) ||
            item.filesChanged.contains(where: { $0.lowercased().contains(query) }) ||
            item.steps.contains(where: { $0.description.lowercased().contains(query) })
        }
    }
    
    /// Delete an agent history item
    func deleteItem(_ id: UUID) {
        historyItems.removeAll { $0.id == id }
        saveHistory()
    }
    
    /// Clear all history
    func clearHistory() {
        historyItems.removeAll()
        saveHistory()
    }
    
    /// Get agent by ID
    func getAgent(by id: UUID) -> AgentHistoryItem? {
        historyItems.first { $0.id == id }
    }
    
    // MARK: - Private Methods
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path),
              let data = try? Data(contentsOf: historyFileURL),
              let decoded = try? JSONDecoder().decode([AgentHistoryItem].self, from: data) else {
            historyItems = []
            return
        }
        
        historyItems = decoded.sorted { $0.startTime > $1.startTime } // Most recent first
    }
    
    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(historyItems) else { return }
        try? data.write(to: historyFileURL)
    }
    
    private func extractFilesChanged(from steps: [AgentStep]) -> [String] {
        var files: Set<String> = []
        for step in steps {
            if let output = step.output {
                // Extract file paths from step output (simple heuristic)
                let pattern = #"([\w\-\./]+\.(swift|js|ts|py|go|rs|java|cpp|h|m|mm|hpp|cc))"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(output.startIndex..<output.endIndex, in: output)
                    regex.enumerateMatches(in: output, range: range) { match, _, _ in
                        if let match = match,
                           let fileRange = Range(match.range(at: 1), in: output) {
                            files.insert(String(output[fileRange]))
                        }
                    }
                }
            }
        }
        return Array(files)
    }
    
    private func calculateLineChanges(from steps: [AgentStep]) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        
        for step in steps {
            if let output = step.output {
                // Simple heuristic: count + and - lines
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
                        added += 1
                    } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                        removed += 1
                    }
                }
            }
        }
        
        return (added, removed)
    }
}
