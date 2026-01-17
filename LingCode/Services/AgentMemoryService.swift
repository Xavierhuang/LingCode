//
//  AgentMemoryService.swift
//  LingCode
//
//  Persistent Agent Memory: Stores project architecture preferences in .lingcode/memory.md
//  Allows the agent to learn and remember user preferences over time
//

import Foundation

class AgentMemoryService {
    static let shared = AgentMemoryService()
    
    private init() {}
    
    /// Get the memory file path for a project
    private func getMemoryFilePath(for projectURL: URL) -> URL {
        let lingcodeDir = projectURL.appendingPathComponent(".lingcode")
        return lingcodeDir.appendingPathComponent("memory.md")
    }
    
    /// Read agent memory from .lingcode/memory.md
    func readMemory(for projectURL: URL) -> String {
        let memoryFile = getMemoryFilePath(for: projectURL)
        
        guard FileManager.default.fileExists(atPath: memoryFile.path),
              let content = try? String(contentsOf: memoryFile, encoding: .utf8) else {
            return getDefaultMemory()
        }
        
        return content
    }
    
    /// Write agent memory to .lingcode/memory.md
    func writeMemory(_ content: String, for projectURL: URL) throws {
        let memoryFile = getMemoryFilePath(for: projectURL)
        let lingcodeDir = memoryFile.deletingLastPathComponent()
        
        // Create .lingcode directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: lingcodeDir.path) {
            try FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        }
        
        // Write memory file
        try content.write(to: memoryFile, atomically: true, encoding: .utf8)
    }
    
    /// Append a note to agent memory
    func appendNote(_ note: String, for projectURL: URL) throws {
        let existingMemory = readMemory(for: projectURL)
        let timestamp = DateFormatter.iso8601.string(from: Date())
        
        let newNote = """
        
        ## \(timestamp)
        \(note)
        """
        
        let updatedMemory = existingMemory + newNote
        try writeMemory(updatedMemory, for: projectURL)
    }
    
    /// Update a specific section in memory (e.g., "User prefers SwiftUI Views to be split")
    func updateSection(_ sectionTitle: String, content: String, for projectURL: URL) throws {
        var memory = readMemory(for: projectURL)
        
        // Check if section exists
        let sectionHeader = "## \(sectionTitle)"
        if memory.contains(sectionHeader) {
            // Replace existing section
            let pattern = #"(?s)## \(sectionTitle).*?(?=\n## |\Z)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: memory, range: NSRange(memory.startIndex..., in: memory)) {
                let replacement = "## \(sectionTitle)\n\(content)\n"
                memory = regex.stringByReplacingMatches(in: memory, range: match.range, withTemplate: replacement)
            }
        } else {
            // Append new section
            memory += "\n\n## \(sectionTitle)\n\(content)\n"
        }
        
        try writeMemory(memory, for: projectURL)
    }
    
    /// Get default memory template
    private func getDefaultMemory() -> String {
        return """
        # Agent Memory
        
        This file stores persistent memory for the AI agent about this project.
        The agent reads this file before generating code to understand project preferences and architecture.
        
        ## Project Preferences
        
        (Agent will learn and update this section based on user feedback)
        
        ## Architecture Notes
        
        (Agent will record important architectural decisions here)
        
        ## Coding Style
        
        (Agent will learn coding style preferences from user edits)
        """
    }
}

extension DateFormatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
