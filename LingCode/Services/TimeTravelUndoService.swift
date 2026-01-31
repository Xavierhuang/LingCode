//
//  TimeTravelUndoService.swift
//  LingCode
//
//  Time-travel undo with file content snapshots and AST metadata
//

import Foundation

struct UndoSnapshot {
    let id: UUID
    let asts: [URL: [ASTSymbol]]
    let fileContents: [URL: String]  // Store actual file contents for restoration
    let symbolIndex: [UUID: SymbolReference]
    let timestamp: Date
    let operation: UndoOperation
    let compressed: Bool
    
    enum UndoOperation {
        case rename(old: String, new: String)
        case refactor(description: String)
        case extractFunction(name: String)
        case multiFileEdit(fileCount: Int)
        case generic(description: String)
    }
    
    var displayName: String {
        switch operation {
        case .rename(let old, let new):
            return "Rename \(old) -> \(new)"
        case .refactor(let description):
            return "Refactor: \(description)"
        case .extractFunction(let name):
            return "Extract function: \(name)"
        case .multiFileEdit(let count):
            return "Multi-file edit (\(count) files)"
        case .generic(let description):
            return "\(description)"
        }
    }
    
    var affectedFilesCount: Int {
        return fileContents.count
    }
}

class TimeTravelUndoService {
    static let shared = TimeTravelUndoService()
    
    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private let maxStackSize = 50
    private let compressionQueue = DispatchQueue(label: "com.lingcode.undocompress", attributes: .concurrent)
    
    private init() {}
    
    /// Create snapshot after successful operation
    func createSnapshot(
        operation: UndoSnapshot.UndoOperation,
        affectedFiles: [URL],
        in workspaceURL: URL
    ) -> UndoSnapshot {
        var asts: [URL: [ASTSymbol]] = [:]
        var fileContents: [URL: String] = [:]
        let symbolIndex: [UUID: SymbolReference] = [:]
        
        // Capture AST and file content for each affected file
        for fileURL in affectedFiles {
            // Get AST symbols
            let ast = ASTIndex.shared.getSymbolsSync(for: fileURL)
            asts[fileURL] = ast
            
            // Store actual file content for restoration
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                fileContents[fileURL] = content
            }
        }
        
        let snapshot = UndoSnapshot(
            id: UUID(),
            asts: asts,
            fileContents: fileContents,
            symbolIndex: symbolIndex,
            timestamp: Date(),
            operation: operation,
            compressed: false
        )
        
        // Add to undo stack
        undoStack.append(snapshot)
        
        // Limit stack size
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        
        // Clear redo stack (new operation)
        redoStack.removeAll()
        
        return snapshot
    }
    
    /// Undo last operation (semantic rewind)
    func undo(in workspaceURL: URL) -> Bool {
        guard let snapshot = undoStack.popLast() else {
            return false
        }
        
        // Create current state snapshot for redo
        let currentSnapshot = createCurrentSnapshot(in: workspaceURL)
        redoStack.append(currentSnapshot)
        
        // Restore from snapshot
        restoreFromSnapshot(snapshot, in: workspaceURL)
        
        return true
    }
    
    /// Redo last undone operation
    func redo(in workspaceURL: URL) -> Bool {
        guard let snapshot = redoStack.popLast() else {
            return false
        }
        
        // Create current state snapshot for undo
        let currentSnapshot = createCurrentSnapshot(in: workspaceURL)
        undoStack.append(currentSnapshot)
        
        // Restore from snapshot
        restoreFromSnapshot(snapshot, in: workspaceURL)
        
        return true
    }
    
    /// Get undo stack (for UI display)
    func getUndoStack() -> [UndoSnapshot] {
        return undoStack
    }
    
    /// Get redo stack (for UI display)
    func getRedoStack() -> [UndoSnapshot] {
        return redoStack
    }
    
    /// Check if undo is available
    var canUndo: Bool {
        return !undoStack.isEmpty
    }
    
    /// Check if redo is available
    var canRedo: Bool {
        return !redoStack.isEmpty
    }
    
    // MARK: - Helper Methods
    
    private func createCurrentSnapshot(in workspaceURL: URL) -> UndoSnapshot {
        // Get all modified files
        let modifiedFiles = getModifiedFiles(in: workspaceURL)
        
        return createSnapshot(
            operation: .generic(description: "Current state"),
            affectedFiles: modifiedFiles,
            in: workspaceURL
        )
    }
    
    /// Restore workspace from snapshot
    func restoreFromSnapshot(_ snapshot: UndoSnapshot, in workspaceURL: URL) {
        // Restore file contents
        for (fileURL, content) in snapshot.fileContents {
            restoreFile(fileURL: fileURL, content: content)
        }
        
        // Refresh AST index for restored files using reparse
        for fileURL in snapshot.fileContents.keys {
            Task {
                // Trigger reparse by invalidating and refetching
                await ASTIndex.shared.reparse(fileURL: fileURL, editRange: 0..<0, newText: "")
            }
        }
    }
    
    private func restoreFile(fileURL: URL, content: String) {
        do {
            // Create backup before restore
            let backupURL = fileURL.appendingPathExtension("lingcode_backup")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            
            // Restore content
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Remove backup on success
            try? FileManager.default.removeItem(at: backupURL)
            
            // Notify editors of change
            NotificationCenter.default.post(
                name: NSNotification.Name("TimeTravelFileRestored"),
                object: nil,
                userInfo: ["fileURL": fileURL]
            )
        } catch {
            print("Failed to restore file \(fileURL.lastPathComponent): \(error)")
        }
    }
    
    private func getModifiedFiles(in workspaceURL: URL) -> [URL] {
        // Get files from undo stack that were modified
        guard let lastSnapshot = undoStack.last else { return [] }
        return Array(lastSnapshot.fileContents.keys)
    }
    
    /// Clear all undo/redo history
    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    /// Get snapshot by ID
    func getSnapshot(id: UUID) -> UndoSnapshot? {
        return undoStack.first { $0.id == id } ?? redoStack.first { $0.id == id }
    }
    
    /// Jump to specific snapshot (time travel)
    func jumpToSnapshot(_ snapshotId: UUID, in workspaceURL: URL) -> Bool {
        guard let snapshot = getSnapshot(id: snapshotId) else { return false }
        
        // Create snapshot of current state
        let currentFiles = Array(Set(undoStack.flatMap { $0.fileContents.keys }))
        let currentSnapshot = createSnapshot(
            operation: .generic(description: "Before time travel"),
            affectedFiles: currentFiles,
            in: workspaceURL
        )
        
        // Find position in undo stack
        if let undoIndex = undoStack.firstIndex(where: { $0.id == snapshotId }) {
            // Move all snapshots after this to redo
            let snapshotsToRedo = Array(undoStack[(undoIndex + 1)...])
            redoStack.append(contentsOf: snapshotsToRedo.reversed())
            undoStack.removeLast(undoStack.count - undoIndex - 1)
        }
        
        // Restore the target snapshot
        restoreFromSnapshot(snapshot, in: workspaceURL)
        
        return true
    }
}

// MARK: - Integration with Edit Services

extension TimeTravelUndoService {
    /// Create snapshot after rename operation
    func snapshotAfterRename(
        oldName: String,
        newName: String,
        affectedFiles: [URL],
        in workspaceURL: URL
    ) {
        _ = createSnapshot(
            operation: .rename(old: oldName, new: newName),
            affectedFiles: affectedFiles,
            in: workspaceURL
        )
    }
    
    /// Create snapshot after refactor
    func snapshotAfterRefactor(
        description: String,
        affectedFiles: [URL],
        in workspaceURL: URL
    ) {
        _ = createSnapshot(
            operation: .refactor(description: description),
            affectedFiles: affectedFiles,
            in: workspaceURL
        )
    }
    
    /// Create snapshot after multi-file edit
    func snapshotAfterMultiFileEdit(
        affectedFiles: [URL],
        in workspaceURL: URL
    ) {
        _ = createSnapshot(
            operation: .multiFileEdit(fileCount: affectedFiles.count),
            affectedFiles: affectedFiles,
            in: workspaceURL
        )
    }
}
