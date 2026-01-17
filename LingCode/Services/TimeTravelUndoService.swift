//
//  TimeTravelUndoService.swift
//  LingCode
//
//  Time-travel undo with AST snapshots (not text-based)
//

import Foundation

struct UndoSnapshot {
    let id: UUID
    let asts: [URL: [ASTSymbol]]
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
            return "⟲ Rename \(old) → \(new)"
        case .refactor(let description):
            return "⟲ Refactor: \(description)"
        case .extractFunction(let name):
            return "⟲ Extract function: \(name)"
        case .multiFileEdit(let count):
            return "⟲ Multi-file edit (\(count) files)"
        case .generic(let description):
            return "⟲ \(description)"
        }
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
        // symbolIndex would be populated from actual symbol references
        // For now, use empty dictionary as placeholder
        let symbolIndex: [UUID: SymbolReference] = [:]
        
        // Capture AST for each affected file
        for fileURL in affectedFiles {
            let ast = ASTIndex.shared.getSymbolsSync(for: fileURL)
            asts[fileURL] = ast
        }
        
        let snapshot = UndoSnapshot(
            id: UUID(),
            asts: asts,
            symbolIndex: symbolIndex,
            timestamp: Date(),
            operation: operation,
            compressed: false
        )
        
        // Compress in background
        compressionQueue.async {
            _ = self.compressSnapshot(snapshot)
            // Would store compressed version
        }
        
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
    
    private func restoreFromSnapshot(_ snapshot: UndoSnapshot, in workspaceURL: URL) {
        // Restore ASTs for each file
        for (fileURL, ast) in snapshot.asts {
            // Would restore file content from AST
            // For now, placeholder
            restoreFileFromAST(fileURL: fileURL, ast: ast, in: workspaceURL)
        }
        
        // Restore symbol index
        // Would update reference index
    }
    
    private func restoreFileFromAST(fileURL: URL, ast: [ASTSymbol], in workspaceURL: URL) {
        // Placeholder - would reconstruct file from AST
        // This is complex and would require full AST-to-text conversion
    }
    
    private func getModifiedFiles(in workspaceURL: URL) -> [URL] {
        // Would track modified files
        // For now, placeholder
        return []
    }
    
    private func compressSnapshot(_ snapshot: UndoSnapshot) -> UndoSnapshot {
        // Compress ASTs using diff-based compression
        // Store only changes, not full ASTs
        // For now, return as-is
        return snapshot
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
