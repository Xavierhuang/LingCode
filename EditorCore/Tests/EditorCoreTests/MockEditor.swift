//
//  MockEditor.swift
//  EditorCoreTests
//
//  Test-only mock editor that holds in-memory files
//

import Foundation
@testable import EditorCore

/// Mock editor for testing - holds files in memory
class MockEditor {
    private var files: [String: String] = [:]
    
    /// Get current file state
    func getFileState(path: String, language: String? = nil) -> FileState? {
        guard let content = files[path] else {
            return nil
        }
        return FileState(id: path, content: content, language: language)
    }
    
    /// Get all file states
    func getAllFileStates() -> [FileState] {
        return files.map { path, content in
            FileState(id: path, content: content)
        }
    }
    
    /// Set file content
    func setFile(path: String, content: String) {
        files[path] = content
    }
    
    /// Apply edit to file
    func applyEdit(_ edit: EditToApply) {
        files[edit.filePath] = edit.newContent
    }
    
    /// Get file content
    func getFileContent(path: String) -> String? {
        return files[path]
    }
    
    /// Clear all files
    func clear() {
        files.removeAll()
    }
    
    /// Get file count
    var fileCount: Int {
        files.count
    }
}
