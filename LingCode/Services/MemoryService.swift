//
//  MemoryService.swift
//  LingCode
//
//  Memory/Memories - Per-project AI memory (like Cursor's Memory)
//  Stores important context that persists across sessions
//

import Foundation
import Combine

// MARK: - Memory Model

struct AIMemory: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var category: MemoryCategory
    var source: MemorySource
    var projectURL: URL?
    var createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
    var importance: Double  // 0.0 to 1.0
    var isActive: Bool
    var relatedFiles: [String]
    var tags: [String]
    
    init(
        content: String,
        category: MemoryCategory,
        source: MemorySource = .manual,
        projectURL: URL? = nil,
        importance: Double = 0.5,
        relatedFiles: [String] = [],
        tags: [String] = []
    ) {
        self.id = UUID()
        self.content = content
        self.category = category
        self.source = source
        self.projectURL = projectURL
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.accessCount = 0
        self.importance = importance
        self.isActive = true
        self.relatedFiles = relatedFiles
        self.tags = tags
    }
    
    mutating func recordAccess() {
        lastAccessedAt = Date()
        accessCount += 1
        // Boost importance based on usage
        importance = min(1.0, importance + 0.05)
    }
}

enum MemoryCategory: String, Codable, CaseIterable {
    case preference = "Preference"
    case codeStyle = "Code Style"
    case architecture = "Architecture"
    case context = "Context"
    case correction = "Correction"
    case instruction = "Instruction"
    case fact = "Fact"
    
    var icon: String {
        switch self {
        case .preference: return "heart"
        case .codeStyle: return "paintbrush"
        case .architecture: return "building.columns"
        case .context: return "doc.text"
        case .correction: return "exclamationmark.triangle"
        case .instruction: return "list.bullet"
        case .fact: return "lightbulb"
        }
    }
}

enum MemorySource: String, Codable {
    case manual = "Manual"
    case learned = "Learned"
    case correction = "Correction"
    case workspace = "Workspace"
}

// MARK: - Memory Service

class MemoryService: ObservableObject {
    static let shared = MemoryService()
    
    @Published var memories: [AIMemory] = []
    @Published var globalMemories: [AIMemory] = []
    @Published var currentProjectURL: URL?
    
    private let storageURL: URL
    private let globalStorageURL: URL
    private let maxMemoriesPerProject = 100
    private let maxGlobalMemories = 50
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        let memoriesDir = lingcodeDir.appendingPathComponent("memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: memoriesDir, withIntermediateDirectories: true)
        
        storageURL = memoriesDir
        globalStorageURL = memoriesDir.appendingPathComponent("global_memories.json")
        
        loadGlobalMemories()
    }
    
    // MARK: - Project Memory Management
    
    func loadMemories(for projectURL: URL) {
        currentProjectURL = projectURL
        
        let projectId = projectURL.absoluteString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(50)
        let memoryFile = storageURL.appendingPathComponent("\(projectId).json")
        
        if FileManager.default.fileExists(atPath: memoryFile.path) {
            do {
                let data = try Data(contentsOf: memoryFile)
                memories = try JSONDecoder().decode([AIMemory].self, from: data)
            } catch {
                print("MemoryService: Failed to load memories: \(error)")
                memories = []
            }
        } else {
            memories = []
        }
    }
    
    func saveMemories() {
        guard let projectURL = currentProjectURL else { return }
        
        let projectId = projectURL.absoluteString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(50)
        let memoryFile = storageURL.appendingPathComponent("\(projectId).json")
        
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: memoryFile)
        } catch {
            print("MemoryService: Failed to save memories: \(error)")
        }
    }
    
    // MARK: - CRUD Operations
    
    func addMemory(
        content: String,
        category: MemoryCategory,
        source: MemorySource = .manual,
        importance: Double = 0.5,
        relatedFiles: [String] = [],
        tags: [String] = []
    ) -> AIMemory {
        let memory = AIMemory(
            content: content,
            category: category,
            source: source,
            projectURL: currentProjectURL,
            importance: importance,
            relatedFiles: relatedFiles,
            tags: tags
        )
        
        memories.insert(memory, at: 0)
        
        // Trim if over limit
        if memories.count > maxMemoriesPerProject {
            // Remove lowest importance inactive memories
            let sorted = memories.sorted { $0.importance > $1.importance }
            memories = Array(sorted.prefix(maxMemoriesPerProject))
        }
        
        saveMemories()
        return memory
    }
    
    func addGlobalMemory(
        content: String,
        category: MemoryCategory,
        importance: Double = 0.5,
        tags: [String] = []
    ) -> AIMemory {
        var memory = AIMemory(
            content: content,
            category: category,
            source: .manual,
            projectURL: nil,
            importance: importance,
            tags: tags
        )
        memory.projectURL = nil // Ensure it's global
        
        globalMemories.insert(memory, at: 0)
        
        if globalMemories.count > maxGlobalMemories {
            let sorted = globalMemories.sorted { $0.importance > $1.importance }
            globalMemories = Array(sorted.prefix(maxGlobalMemories))
        }
        
        saveGlobalMemories()
        return memory
    }
    
    func updateMemory(_ id: UUID, content: String) {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].content = content
            saveMemories()
        } else if let index = globalMemories.firstIndex(where: { $0.id == id }) {
            globalMemories[index].content = content
            saveGlobalMemories()
        }
    }
    
    func deleteMemory(_ id: UUID) {
        if memories.contains(where: { $0.id == id }) {
            memories.removeAll { $0.id == id }
            saveMemories()
        } else {
            globalMemories.removeAll { $0.id == id }
            saveGlobalMemories()
        }
    }
    
    func toggleMemoryActive(_ id: UUID) {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].isActive.toggle()
            saveMemories()
        } else if let index = globalMemories.firstIndex(where: { $0.id == id }) {
            globalMemories[index].isActive.toggle()
            saveGlobalMemories()
        }
    }
    
    // MARK: - Learning
    
    /// Learn from user correction
    func learnFromCorrection(originalOutput: String, correction: String, context: String) {
        let content = """
        When generating code similar to:
        \(originalOutput.prefix(200))...
        
        The user prefers:
        \(correction)
        """
        
        _ = addMemory(
            content: content,
            category: .correction,
            source: .correction,
            importance: 0.8
        )
    }
    
    /// Learn preference from user feedback
    func learnPreference(preference: String, context: String) {
        _ = addMemory(
            content: preference,
            category: .preference,
            source: .learned,
            importance: 0.6
        )
    }
    
    /// Learn code style from accepted changes
    func learnCodeStyle(pattern: String, example: String) {
        let content = """
        Code style preference:
        \(pattern)
        
        Example:
        ```
        \(example.prefix(500))
        ```
        """
        
        _ = addMemory(
            content: content,
            category: .codeStyle,
            source: .learned,
            importance: 0.5
        )
    }
    
    // MARK: - Query
    
    func getActiveMemories() -> [AIMemory] {
        let projectMemories = memories.filter { $0.isActive }
        let global = globalMemories.filter { $0.isActive }
        
        // Combine and sort by importance
        return (projectMemories + global).sorted { $0.importance > $1.importance }
    }
    
    func getMemories(forCategory category: MemoryCategory) -> [AIMemory] {
        return getActiveMemories().filter { $0.category == category }
    }
    
    func getMemories(forFile path: String) -> [AIMemory] {
        return getActiveMemories().filter { memory in
            memory.relatedFiles.contains { $0 == path || path.contains($0) }
        }
    }
    
    func searchMemories(query: String) -> [AIMemory] {
        let lowercased = query.lowercased()
        return getActiveMemories().filter { memory in
            memory.content.lowercased().contains(lowercased) ||
            memory.tags.contains { $0.lowercased().contains(lowercased) }
        }
    }
    
    // MARK: - Context Generation
    
    /// Generate memory context for AI system prompt
    func generateMemoryContext(forFile path: String? = nil, limit: Int = 10) -> String {
        var relevantMemories = getActiveMemories()
        
        // Boost file-specific memories
        if let filePath = path {
            relevantMemories = relevantMemories.map { memory in
                var boosted = memory
                if memory.relatedFiles.contains(where: { filePath.contains($0) }) {
                    boosted.importance = min(1.0, boosted.importance + 0.3)
                }
                return boosted
            }.sorted { $0.importance > $1.importance }
        }
        
        let selected = Array(relevantMemories.prefix(limit))
        
        guard !selected.isEmpty else { return "" }
        
        // Record access
        for memory in selected {
            recordAccess(memory.id)
        }
        
        var context = "## User Preferences and Memory\n\n"
        context += "Remember these user preferences and project context:\n\n"
        
        for memory in selected {
            context += "### \(memory.category.rawValue)\n"
            context += "\(memory.content)\n\n"
        }
        
        return context
    }
    
    private func recordAccess(_ id: UUID) {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].recordAccess()
        } else if let index = globalMemories.firstIndex(where: { $0.id == id }) {
            globalMemories[index].recordAccess()
        }
    }
    
    // MARK: - Persistence
    
    private func loadGlobalMemories() {
        guard FileManager.default.fileExists(atPath: globalStorageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: globalStorageURL)
            globalMemories = try JSONDecoder().decode([AIMemory].self, from: data)
        } catch {
            print("MemoryService: Failed to load global memories: \(error)")
        }
    }
    
    private func saveGlobalMemories() {
        do {
            let data = try JSONEncoder().encode(globalMemories)
            try data.write(to: globalStorageURL)
        } catch {
            print("MemoryService: Failed to save global memories: \(error)")
        }
    }
    
    // MARK: - Import/Export
    
    func exportMemories() -> Data? {
        let export = MemoryExport(
            projectMemories: memories,
            globalMemories: globalMemories,
            exportDate: Date()
        )
        return try? JSONEncoder().encode(export)
    }
    
    func importMemories(from data: Data) throws {
        let imported = try JSONDecoder().decode(MemoryExport.self, from: data)
        
        // Merge with existing
        for memory in imported.projectMemories where !memories.contains(where: { $0.content == memory.content }) {
            memories.append(memory)
        }
        
        for memory in imported.globalMemories where !globalMemories.contains(where: { $0.content == memory.content }) {
            globalMemories.append(memory)
        }
        
        saveMemories()
        saveGlobalMemories()
    }
    
    struct MemoryExport: Codable {
        let projectMemories: [AIMemory]
        let globalMemories: [AIMemory]
        let exportDate: Date
    }
    
    // MARK: - Cleanup
    
    func cleanupOldMemories(olderThan days: Int = 90) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        
        memories.removeAll { memory in
            memory.lastAccessedAt < cutoff && memory.importance < 0.5 && memory.accessCount < 3
        }
        
        globalMemories.removeAll { memory in
            memory.lastAccessedAt < cutoff && memory.importance < 0.5 && memory.accessCount < 3
        }
        
        saveMemories()
        saveGlobalMemories()
    }
    
    func clearAllMemories() {
        memories.removeAll()
        globalMemories.removeAll()
        saveMemories()
        saveGlobalMemories()
    }
}
