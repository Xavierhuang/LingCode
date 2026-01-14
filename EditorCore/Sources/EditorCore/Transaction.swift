//
//  Transaction.swift
//  EditorCore
//
//  Transaction support for atomic, reversible edit operations
//

import Foundation

/// Represents a transaction containing multiple edits that must be applied atomically
public struct EditTransaction: Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let edits: [ProposedEdit]
    public let metadata: TransactionMetadata
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        edits: [ProposedEdit],
        metadata: TransactionMetadata = TransactionMetadata()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.edits = edits
        self.metadata = metadata
    }
    
    /// Check if transaction is valid (all edits reference existing files)
    public func isValid(against snapshots: [String: FileSnapshot]) -> Bool {
        edits.allSatisfy { edit in
            snapshots[edit.filePath] != nil
        }
    }
    
    /// Get all file paths affected by this transaction
    public var affectedFiles: Set<String> {
        Set(edits.map { $0.filePath })
    }
}

/// Metadata about a transaction
public struct TransactionMetadata: Equatable {
    public let description: String
    public let source: String
    public let canUndo: Bool
    
    public init(
        description: String = "",
        source: String = "ai",
        canUndo: Bool = true
    ) {
        self.description = description
        self.source = source
        self.canUndo = canUndo
    }
}

/// Represents the state before a transaction was applied (for undo)
public struct TransactionSnapshot: Equatable {
    public let transactionId: UUID
    public let timestamp: Date
    public let fileSnapshots: [String: FileSnapshot]
    
    public init(
        transactionId: UUID,
        timestamp: Date = Date(),
        fileSnapshots: [String: FileSnapshot]
    ) {
        self.transactionId = transactionId
        self.timestamp = timestamp
        self.fileSnapshots = fileSnapshots
    }
}

/// Result of applying or reverting a transaction
public enum TransactionResult: Equatable {
    case success(EditTransaction)
    case partialFailure(EditTransaction, failedEdits: [UUID])
    case failure(String)
    
    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
