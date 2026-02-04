//
//  NotepadService.swift
//  LingCode
//
//  Notepads - Scratch pads for context (like Cursor's Notepads)
//  Provides persistent scratch space that can be referenced in chat
//

import Foundation
import Combine

// MARK: - Notepad Model

struct Notepad: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var tags: [String]
    var language: String?  // For syntax highlighting
    
    init(
        id: UUID = UUID(),
        name: String,
        content: String = "",
        language: String? = nil,
        isPinned: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = isPinned
        self.tags = tags
        self.language = language
    }
    
    mutating func updateContent(_ newContent: String) {
        self.content = newContent
        self.updatedAt = Date()
    }
}

// MARK: - Notepad Service

class NotepadService: ObservableObject {
    static let shared = NotepadService()
    
    @Published var notepads: [Notepad] = []
    @Published var selectedNotepadId: UUID?
    @Published var searchQuery: String = ""
    
    private let storageURL: URL
    private let maxNotepads = 50
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        storageURL = lingcodeDir.appendingPathComponent("notepads.json")
        
        loadNotepads()
    }
    
    // MARK: - CRUD Operations
    
    func createNotepad(name: String, content: String = "", language: String? = nil) -> Notepad {
        var notepad = Notepad(name: name, content: content, language: language)
        
        // Ensure unique name
        var uniqueName = name
        var counter = 1
        while notepads.contains(where: { $0.name == uniqueName }) {
            counter += 1
            uniqueName = "\(name) \(counter)"
        }
        notepad.name = uniqueName
        
        notepads.insert(notepad, at: 0)
        
        // Limit total notepads
        if notepads.count > maxNotepads {
            // Remove oldest unpinned notepad
            if let removeIndex = notepads.lastIndex(where: { !$0.isPinned }) {
                notepads.remove(at: removeIndex)
            }
        }
        
        saveNotepads()
        return notepad
    }
    
    func updateNotepad(_ id: UUID, content: String) {
        if let index = notepads.firstIndex(where: { $0.id == id }) {
            notepads[index].updateContent(content)
            saveNotepads()
        }
    }
    
    func renameNotepad(_ id: UUID, name: String) {
        if let index = notepads.firstIndex(where: { $0.id == id }) {
            notepads[index].name = name
            notepads[index].updatedAt = Date()
            saveNotepads()
        }
    }
    
    func deleteNotepad(_ id: UUID) {
        notepads.removeAll { $0.id == id }
        if selectedNotepadId == id {
            selectedNotepadId = notepads.first?.id
        }
        saveNotepads()
    }
    
    func togglePin(_ id: UUID) {
        if let index = notepads.firstIndex(where: { $0.id == id }) {
            notepads[index].isPinned.toggle()
            saveNotepads()
        }
    }
    
    func addTag(_ id: UUID, tag: String) {
        if let index = notepads.firstIndex(where: { $0.id == id }) {
            if !notepads[index].tags.contains(tag) {
                notepads[index].tags.append(tag)
                saveNotepads()
            }
        }
    }
    
    func removeTag(_ id: UUID, tag: String) {
        if let index = notepads.firstIndex(where: { $0.id == id }) {
            notepads[index].tags.removeAll { $0 == tag }
            saveNotepads()
        }
    }
    
    // MARK: - Queries
    
    func getNotepad(_ id: UUID) -> Notepad? {
        return notepads.first { $0.id == id }
    }
    
    func getNotepad(byName name: String) -> Notepad? {
        return notepads.first { $0.name.lowercased() == name.lowercased() }
    }
    
    var selectedNotepad: Notepad? {
        guard let id = selectedNotepadId else { return nil }
        return getNotepad(id)
    }
    
    var filteredNotepads: [Notepad] {
        let query = searchQuery.lowercased()
        guard !query.isEmpty else { return sortedNotepads }
        
        return sortedNotepads.filter { notepad in
            notepad.name.lowercased().contains(query) ||
            notepad.content.lowercased().contains(query) ||
            notepad.tags.contains { $0.lowercased().contains(query) }
        }
    }
    
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
    
    var pinnedNotepads: [Notepad] {
        notepads.filter { $0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var recentNotepads: [Notepad] {
        Array(sortedNotepads.prefix(5))
    }
    
    var allTags: [String] {
        Array(Set(notepads.flatMap { $0.tags })).sorted()
    }
    
    // MARK: - Context Generation
    
    /// Generate context string for AI from notepad content
    func getContextForNotepad(_ id: UUID) -> String? {
        guard let notepad = getNotepad(id) else { return nil }
        
        var context = "## Notepad: \(notepad.name)\n\n"
        
        if let language = notepad.language {
            context += "```\(language)\n\(notepad.content)\n```"
        } else {
            context += notepad.content
        }
        
        return context
    }
    
    /// Generate context for all pinned notepads
    func getPinnedContext() -> String {
        let pinned = pinnedNotepads
        guard !pinned.isEmpty else { return "" }
        
        var context = "## Pinned Notepads\n\n"
        for notepad in pinned {
            context += "### \(notepad.name)\n"
            if let language = notepad.language {
                context += "```\(language)\n\(notepad.content)\n```\n\n"
            } else {
                context += "\(notepad.content)\n\n"
            }
        }
        
        return context
    }
    
    /// Generate context for notepads matching a query (for @notepad mentions)
    func getContextForQuery(_ query: String) -> String {
        let matching: [Notepad]
        
        if query.isEmpty {
            matching = recentNotepads
        } else {
            matching = notepads.filter { notepad in
                notepad.name.lowercased().contains(query.lowercased()) ||
                notepad.tags.contains { $0.lowercased().contains(query.lowercased()) }
            }
        }
        
        guard !matching.isEmpty else { return "" }
        
        var context = "## Referenced Notepads\n\n"
        for notepad in matching {
            context += "### \(notepad.name)\n"
            if let language = notepad.language {
                context += "```\(language)\n\(notepad.content)\n```\n\n"
            } else {
                context += "\(notepad.content)\n\n"
            }
        }
        
        return context
    }
    
    // MARK: - Import/Export
    
    func importFromFile(_ url: URL) throws -> Notepad {
        let content = try String(contentsOf: url, encoding: .utf8)
        let name = url.deletingPathExtension().lastPathComponent
        let language = languageFromExtension(url.pathExtension)
        
        return createNotepad(name: name, content: content, language: language)
    }
    
    func exportNotepad(_ id: UUID, to url: URL) throws {
        guard let notepad = getNotepad(id) else { return }
        try notepad.content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func languageFromExtension(_ ext: String) -> String? {
        let mapping: [String: String] = [
            "swift": "swift",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "rb": "ruby",
            "go": "go",
            "rs": "rust",
            "java": "java",
            "kt": "kotlin",
            "c": "c",
            "cpp": "cpp",
            "h": "c",
            "hpp": "cpp",
            "cs": "csharp",
            "php": "php",
            "html": "html",
            "css": "css",
            "json": "json",
            "yaml": "yaml",
            "yml": "yaml",
            "xml": "xml",
            "sql": "sql",
            "sh": "bash",
            "bash": "bash",
            "zsh": "zsh",
            "md": "markdown"
        ]
        return mapping[ext.lowercased()]
    }
    
    // MARK: - Persistence
    
    private func loadNotepads() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: storageURL)
            notepads = try JSONDecoder().decode([Notepad].self, from: data)
        } catch {
            print("NotepadService: Failed to load notepads: \(error)")
        }
    }
    
    private func saveNotepads() {
        do {
            let data = try JSONEncoder().encode(notepads)
            try data.write(to: storageURL)
        } catch {
            print("NotepadService: Failed to save notepads: \(error)")
        }
    }
    
    // MARK: - Templates
    
    func createFromTemplate(_ template: NotepadTemplate) -> Notepad {
        return createNotepad(
            name: template.name,
            content: template.content,
            language: template.language
        )
    }
    
    enum NotepadTemplate {
        case scratchPad
        case codeSnippet(language: String)
        case todoList
        case meetingNotes
        case apiDocs
        case bugReport
        
        var name: String {
            switch self {
            case .scratchPad: return "Scratch Pad"
            case .codeSnippet(let lang): return "\(lang.capitalized) Snippet"
            case .todoList: return "Todo List"
            case .meetingNotes: return "Meeting Notes"
            case .apiDocs: return "API Documentation"
            case .bugReport: return "Bug Report"
            }
        }
        
        var content: String {
            switch self {
            case .scratchPad:
                return "# Scratch Pad\n\nQuick notes and ideas...\n"
            case .codeSnippet:
                return "// Code snippet\n\n"
            case .todoList:
                return """
                # Todo List
                
                ## High Priority
                - [ ] 
                
                ## Medium Priority
                - [ ] 
                
                ## Low Priority
                - [ ] 
                """
            case .meetingNotes:
                return """
                # Meeting Notes
                
                **Date:** \(Date().formatted(date: .abbreviated, time: .shortened))
                **Attendees:** 
                
                ## Agenda
                1. 
                
                ## Discussion
                
                ## Action Items
                - [ ] 
                """
            case .apiDocs:
                return """
                # API Documentation
                
                ## Endpoint
                `GET /api/v1/`
                
                ## Request
                ```json
                {
                }
                ```
                
                ## Response
                ```json
                {
                }
                ```
                """
            case .bugReport:
                return """
                # Bug Report
                
                ## Summary
                
                ## Steps to Reproduce
                1. 
                
                ## Expected Behavior
                
                ## Actual Behavior
                
                ## Environment
                - OS: 
                - Version: 
                """
            }
        }
        
        var language: String? {
            switch self {
            case .codeSnippet(let lang): return lang
            case .apiDocs: return "markdown"
            default: return "markdown"
            }
        }
    }
}
