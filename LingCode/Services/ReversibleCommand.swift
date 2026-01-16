//
//  ReversibleCommand.swift
//  LingCode
//
//  AST-Based Time Travel: Command Pattern for reversible operations
//  Allows users to scrub through AI thought process visually
//

import Foundation
import Combine

// MARK: - Reversible Command Protocol

protocol ReversibleCommand {
    var id: UUID { get }
    var timestamp: Date { get }
    var description: String { get }
    
    /// Execute the command
    func execute() throws
    
    /// Undo the command (inverse operation)
    func undo() throws
}

// MARK: - File Edit Command

struct FileEditCommand: ReversibleCommand {
    let id = UUID()
    let timestamp = Date()
    let description: String
    
    let filePath: URL
    let originalContent: String
    let newContent: String
    let range: NSRange?
    
    init(filePath: URL, originalContent: String, newContent: String, range: NSRange? = nil, description: String) {
        self.filePath = filePath
        self.originalContent = originalContent
        self.newContent = newContent
        self.range = range
        self.description = description
    }
    
    func execute() throws {
        try newContent.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    func undo() throws {
        try originalContent.write(to: filePath, atomically: true, encoding: .utf8)
    }
}

// MARK: - File Create Command

struct FileCreateCommand: ReversibleCommand {
    let id = UUID()
    let timestamp = Date()
    let description: String
    
    let filePath: URL
    let content: String
    
    init(filePath: URL, content: String, description: String) {
        self.filePath = filePath
        self.content = content
        self.description = description
    }
    
    func execute() throws {
        let directory = filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try content.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    func undo() throws {
        try FileManager.default.removeItem(at: filePath)
    }
}

// MARK: - File Delete Command

struct FileDeleteCommand: ReversibleCommand {
    let id = UUID()
    let timestamp = Date()
    let description: String
    
    let filePath: URL
    let originalContent: String
    
    init(filePath: URL, originalContent: String, description: String) {
        self.filePath = filePath
        self.originalContent = originalContent
        self.description = description
    }
    
    func execute() throws {
        try FileManager.default.removeItem(at: filePath)
    }
    
    func undo() throws {
        let directory = filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try originalContent.write(to: filePath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Command History (Time Travel)

class CommandHistory: ObservableObject {
    static let shared = CommandHistory()
    
    @Published var commands: [ReversibleCommand] = []
    @Published var currentIndex: Int = -1 // -1 means at initial state
    
    private init() {}
    
    /// Execute a command and add to history
    func execute(_ command: ReversibleCommand) throws {
        // Remove any commands after current index (if we're in the middle of history)
        if currentIndex < commands.count - 1 {
            commands = Array(commands[0...currentIndex])
        }
        
        // Execute command
        try command.execute()
        
        // Add to history
        commands.append(command)
        currentIndex = commands.count - 1
    }
    
    /// Undo last command
    func undo() throws {
        guard currentIndex >= 0 else { return }
        
        let command = commands[currentIndex]
        try command.undo()
        currentIndex -= 1
    }
    
    /// Redo next command
    func redo() throws {
        guard currentIndex < commands.count - 1 else { return }
        
        currentIndex += 1
        let command = commands[currentIndex]
        try command.execute()
    }
    
    /// Jump to a specific point in history (time travel)
    func jumpTo(index: Int) throws {
        guard index >= -1 && index < commands.count else { return }
        
        // Undo or redo to reach target index
        while currentIndex > index {
            try undo()
        }
        
        while currentIndex < index {
            try redo()
        }
    }
    
    /// Get current state description
    func getCurrentState() -> String {
        if currentIndex < 0 {
            return "Initial state"
        } else if currentIndex >= commands.count {
            return "Final state"
        } else {
            return commands[currentIndex].description
        }
    }
    
    /// Clear history
    func clear() {
        commands.removeAll()
        currentIndex = -1
    }
}
