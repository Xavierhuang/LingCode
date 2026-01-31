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
    var isPinned: Bool
    var customName: String?
    var isUnread: Bool
    
    enum AgentTaskStatus: String, Codable {
        case running
        case completed
        case failed
        case cancelled
    }
    
    init(id: UUID, description: String, projectURL: URL?, startTime: Date, endTime: Date? = nil, status: AgentTaskStatus, steps: [AgentStepHistory], result: AgentTaskResult? = nil, filesChanged: [String], linesAdded: Int, linesRemoved: Int, isPinned: Bool = false, customName: String? = nil, isUnread: Bool = false) {
        self.id = id
        self.description = description
        self.projectURL = projectURL
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.steps = steps
        self.result = result
        self.filesChanged = filesChanged
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.isPinned = isPinned
        self.customName = customName
        self.isUnread = isUnread
    }
    
    enum CodingKeys: String, CodingKey {
        case id, description, projectURL, startTime, endTime, status, steps, result, filesChanged, linesAdded, linesRemoved
        case isPinned, customName, isUnread
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        description = try c.decode(String.self, forKey: .description)
        projectURL = try c.decodeIfPresent(URL.self, forKey: .projectURL)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        status = try c.decode(AgentTaskStatus.self, forKey: .status)
        steps = try c.decode([AgentStepHistory].self, forKey: .steps)
        result = try c.decodeIfPresent(AgentTaskResult.self, forKey: .result)
        filesChanged = try c.decode([String].self, forKey: .filesChanged)
        linesAdded = try c.decode(Int.self, forKey: .linesAdded)
        linesRemoved = try c.decode(Int.self, forKey: .linesRemoved)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        isUnread = try c.decodeIfPresent(Bool.self, forKey: .isUnread) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(description, forKey: .description)
        try c.encode(projectURL, forKey: .projectURL)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(status, forKey: .status)
        try c.encode(steps, forKey: .steps)
        try c.encode(result, forKey: .result)
        try c.encode(filesChanged, forKey: .filesChanged)
        try c.encode(linesAdded, forKey: .linesAdded)
        try c.encode(linesRemoved, forKey: .linesRemoved)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(customName, forKey: .customName)
        try c.encode(isUnread, forKey: .isUnread)
    }
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    var displayDescription: String {
        let base = customName ?? description
        if base.count > 50 {
            return String(base.prefix(50)) + "..."
        }
        return base
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
        
        let existing = historyItems.first { $0.id == task.id }
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
            linesRemoved: linesRemoved,
            isPinned: existing?.isPinned ?? false,
            customName: existing?.customName,
            isUnread: existing?.isUnread ?? false
        )
        
        // Update or add item
        if let index = historyItems.firstIndex(where: { $0.id == task.id }) {
            historyItems[index] = historyItem
        } else {
            historyItems.insert(historyItem, at: 0) // Most recent first
        }
        
        saveHistory()
    }
    
    /// Get filtered history based on search query (pinned first, then by date)
    var filteredHistory: [AgentHistoryItem] {
        let base: [AgentHistoryItem]
        if searchQuery.isEmpty {
            base = historyItems
        } else {
            let query = searchQuery.lowercased()
            base = historyItems.filter { item in
                let desc = (item.customName ?? item.description).lowercased()
                return desc.contains(query) ||
                    item.description.lowercased().contains(query) ||
                    item.filesChanged.contains(where: { $0.lowercased().contains(query) }) ||
                    item.steps.contains(where: { $0.description.lowercased().contains(query) })
            }
        }
        return base.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.startTime > b.startTime
        }
    }
    
    /// Pinned items from filtered history
    var pinnedHistory: [AgentHistoryItem] {
        filteredHistory.filter { $0.isPinned }
    }
    
    /// Unpinned items from filtered history
    var unpinnedHistory: [AgentHistoryItem] {
        filteredHistory.filter { !$0.isPinned }
    }
    
    /// Delete an agent history item
    func deleteItem(_ id: UUID) {
        historyItems.removeAll { $0.id == id }
        saveHistory()
    }
    
    /// Mark a running task as failed (e.g. it was stuck waiting for approval or never finished).
    func markAsFailed(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else { return }
        var item = historyItems[index]
        guard item.status == .running else { return }
        item.status = .failed
        item.endTime = Date()
        historyItems[index] = item
        saveHistory()
    }
    
    /// Toggle pin for an item
    func togglePin(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else { return }
        historyItems[index].isPinned.toggle()
        saveHistory()
    }
    
    /// Duplicate an item (new id, same description and metadata; for re-run or variation)
    func duplicateItem(_ id: UUID) -> UUID? {
        guard let item = historyItems.first(where: { $0.id == id }) else { return nil }
        let newItem = AgentHistoryItem(
            id: UUID(),
            description: item.description,
            projectURL: item.projectURL,
            startTime: Date(),
            endTime: nil,
            status: .running,
            steps: [],
            result: nil,
            filesChanged: [],
            linesAdded: 0,
            linesRemoved: 0,
            isPinned: false,
            customName: item.customName.map { "\($0) (copy)" },
            isUnread: true
        )
        historyItems.insert(newItem, at: 0)
        saveHistory()
        return newItem.id
    }
    
    /// Rename an item (custom display name)
    func renameItem(_ id: UUID, name: String) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        historyItems[index].customName = trimmed.isEmpty ? nil : trimmed
        saveHistory()
    }
    
    /// Mark an item as unread
    func markAsUnread(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else { return }
        historyItems[index].isUnread = true
        saveHistory()
    }
    
    /// Mark an item as read (clear unread)
    func markAsRead(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else { return }
        historyItems[index].isUnread = false
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
