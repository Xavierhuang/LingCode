//
//  NotepadService.swift
//  LingCode
//
//  Persistent notepads/scratchpads for temporary notes
//  Similar to Cursor's notepad feature
//

import Foundation
import Combine

struct Notepad: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var tags: [String]
    
    init(id: UUID = UUID(), name: String = "Untitled", content: String = "", isPinned: Bool = false, tags: [String] = []) {
        self.id = id
        self.name = name
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = isPinned
        self.tags = tags
    }
}

class NotepadService: ObservableObject {
    static let shared = NotepadService()
    
    @Published var notepads: [Notepad] = []
    @Published var activeNotepadId: UUID?
    
    private let storageKey = "lingcode_notepads"
    private let storageURL: URL
    
    private init() {
        // Store in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        
        storageURL = lingcodeDir.appendingPathComponent("notepads.json")
        
        loadNotepads()
    }
    
    // MARK: - CRUD Operations
    
    func createNotepad(name: String = "Untitled", content: String = "") -> Notepad {
        let notepad = Notepad(name: name, content: content)
        notepads.insert(notepad, at: 0)
        activeNotepadId = notepad.id
        saveNotepads()
        return notepad
    }
    
    func updateNotepad(_ id: UUID, name: String? = nil, content: String? = nil, isPinned: Bool? = nil, tags: [String]? = nil) {
        guard let index = notepads.firstIndex(where: { $0.id == id }) else { return }
        
        if let name = name {
            notepads[index].name = name
        }
        if let content = content {
            notepads[index].content = content
        }
        if let isPinned = isPinned {
            notepads[index].isPinned = isPinned
        }
        if let tags = tags {
            notepads[index].tags = tags
        }
        notepads[index].updatedAt = Date()
        
        saveNotepads()
    }
    
    func deleteNotepad(_ id: UUID) {
        notepads.removeAll { $0.id == id }
        if activeNotepadId == id {
            activeNotepadId = notepads.first?.id
        }
        saveNotepads()
    }
    
    func getNotepad(_ id: UUID) -> Notepad? {
        return notepads.first { $0.id == id }
    }
    
    func getNotepad(byName name: String) -> Notepad? {
        return notepads.first { $0.name.lowercased() == name.lowercased() }
    }
    
    var activeNotepad: Notepad? {
        guard let id = activeNotepadId else { return nil }
        return getNotepad(id)
    }
    
    // MARK: - Context Building
    
    /// Build context string for AI from a notepad
    func buildContext(from notepad: Notepad) -> String {
        return """
        ## Notepad: \(notepad.name)
        Last updated: \(formatDate(notepad.updatedAt))
        
        \(notepad.content)
        """
    }
    
    /// Build context from notepad by name or active notepad
    func buildContext(notepadName: String?) -> String {
        let notepad: Notepad?
        
        if let name = notepadName, !name.isEmpty {
            notepad = getNotepad(byName: name)
        } else {
            notepad = activeNotepad
        }
        
        guard let np = notepad else {
            return "No notepad found."
        }
        
        return buildContext(from: np)
    }
    
    // MARK: - Search
    
    func searchNotepads(query: String) -> [Notepad] {
        let lowercasedQuery = query.lowercased()
        return notepads.filter { notepad in
            notepad.name.lowercased().contains(lowercasedQuery) ||
            notepad.content.lowercased().contains(lowercasedQuery) ||
            notepad.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
    
    // MARK: - Sorting
    
    var sortedNotepads: [Notepad] {
        notepads.sorted { lhs, rhs in
            // Pinned first
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            // Then by updated date
            return lhs.updatedAt > rhs.updatedAt
        }
    }
    
    // MARK: - Persistence
    
    private func loadNotepads() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            // Create a default notepad
            _ = createNotepad(name: "Quick Notes", content: "# Quick Notes\n\nUse this notepad for temporary notes during your coding session.\n\nReference it in chat with @notepad:Quick Notes")
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            notepads = try JSONDecoder().decode([Notepad].self, from: data)
            
            if notepads.isEmpty {
                _ = createNotepad(name: "Quick Notes", content: "# Quick Notes\n\nUse this notepad for temporary notes.")
            } else {
                activeNotepadId = notepads.first?.id
            }
        } catch {
            print("Failed to load notepads: \(error)")
            _ = createNotepad(name: "Quick Notes", content: "# Quick Notes\n\nUse this notepad for temporary notes.")
        }
    }
    
    private func saveNotepads() {
        do {
            let data = try JSONEncoder().encode(notepads)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save notepads: \(error)")
        }
    }
    
    // MARK: - Import/Export
    
    func exportNotepad(_ id: UUID) -> String? {
        guard let notepad = getNotepad(id) else { return nil }
        return notepad.content
    }
    
    func importNotepad(name: String, content: String) -> Notepad {
        return createNotepad(name: name, content: content)
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Quick Actions

extension NotepadService {
    /// Append text to a notepad
    func appendToNotepad(_ id: UUID, text: String) {
        guard let notepad = getNotepad(id) else { return }
        let newContent = notepad.content + "\n\n" + text
        updateNotepad(id, content: newContent)
    }
    
    /// Append text to active notepad or create new one
    func appendToActiveNotepad(_ text: String) {
        if let id = activeNotepadId {
            appendToNotepad(id, text: text)
        } else {
            _ = createNotepad(name: "Quick Notes", content: text)
        }
    }
    
    /// Save code snippet to notepad
    func saveCodeSnippet(code: String, language: String, description: String? = nil) {
        let content = """
        ## Code Snippet
        \(description ?? "")
        
        ```\(language)
        \(code)
        ```
        
        ---
        Saved: \(formatDate(Date()))
        """
        
        appendToActiveNotepad(content)
    }
}
