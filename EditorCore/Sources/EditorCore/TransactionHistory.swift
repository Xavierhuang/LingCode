//
//  TransactionHistory.swift
//  EditorCore
//
//  Manages transaction history for undo/redo operations.
//  Uses structural sharing: first snapshot stored in full; subsequent entries store only
//  deltas (edited files' "before" content) to keep memory low on 100k+ line codebases.
//

import Foundation

/// Single snapshot entry: either full state or delta from previous (only edited files).
private enum SnapshotEntry: Equatable {
    case full(TransactionSnapshot)
    case delta(transactionId: UUID, timestamp: Date, fileSnapshots: [String: FileSnapshot])
}

/// Manages the history of applied and reverted transactions with delta storage.
public class TransactionHistory {
    private var appliedTransactions: [EditTransaction] = []
    private var revertedTransactions: [EditTransaction] = []
    /// Structural sharing: first entry is full snapshot, rest are deltas (edited files only).
    private var snapshotEntries: [SnapshotEntry] = []
    
    public let maxHistorySize: Int
    
    public init(maxHistorySize: Int = 100) {
        self.maxHistorySize = maxHistorySize
    }
    
    /// Record a transaction as applied. Stores full snapshot for first transaction,
    /// then only deltas (before-state for edited files) for subsequent ones.
    public func recordApplied(
        _ transaction: EditTransaction,
        snapshot: TransactionSnapshot
    ) {
        appliedTransactions.append(transaction)
        
        if snapshotEntries.isEmpty {
            snapshotEntries.append(.full(snapshot))
        } else {
            let delta: [String: FileSnapshot] = Dictionary(
                uniqueKeysWithValues: transaction.affectedFiles.compactMap { path in
                    snapshot.fileSnapshots[path].map { (path, $0) }
                }
            )
            snapshotEntries.append(.delta(
                transactionId: snapshot.transactionId,
                timestamp: snapshot.timestamp,
                fileSnapshots: delta
            ))
        }
        
        if appliedTransactions.count > maxHistorySize {
            appliedTransactions.removeFirst()
            snapshotEntries.removeFirst()
        }
        
        revertedTransactions.removeAll()
    }
    
    /// Record a transaction as reverted
    public func recordReverted(_ transaction: EditTransaction) {
        revertedTransactions.append(transaction)
    }
    
    /// Get the snapshot for a transaction (for undo). Reconstructs full snapshot by merging deltas.
    public func getSnapshot(for transactionId: UUID) -> TransactionSnapshot? {
        guard let index = appliedTransactions.firstIndex(where: { $0.id == transactionId }) else {
            return nil
        }
        guard index >= 0, index < snapshotEntries.count else { return nil }
        let entry = snapshotEntries[index]
        guard case .full(let full) = entry else {
            return reconstructSnapshot(at: index)
        }
        return full
    }
    
    private func reconstructSnapshot(at index: Int) -> TransactionSnapshot? {
        guard index >= 0, index < snapshotEntries.count else { return nil }
        switch snapshotEntries[index] {
        case .full(let s):
            return s
        case .delta(let transactionId, let timestamp, let delta):
            var merged: [String: FileSnapshot] = [:]
            if index > 0, let prev = reconstructSnapshot(at: index - 1) {
                merged = prev.fileSnapshots
            }
            for (path, fileSnapshot) in delta {
                merged[path] = fileSnapshot
            }
            return TransactionSnapshot(
                transactionId: transactionId,
                timestamp: timestamp,
                fileSnapshots: merged
            )
        }
    }
    
    public func getLastApplied() -> EditTransaction? {
        return appliedTransactions.last
    }
    
    public func getLastReverted() -> EditTransaction? {
        return revertedTransactions.last
    }
    
    public func canUndo() -> Bool {
        return !appliedTransactions.isEmpty
    }
    
    public func canRedo() -> Bool {
        return !revertedTransactions.isEmpty
    }
    
    public func getAppliedTransactionIds() -> [UUID] {
        return appliedTransactions.map { $0.id }
    }
    
    public func clear() {
        appliedTransactions.removeAll()
        revertedTransactions.removeAll()
        snapshotEntries.removeAll()
    }
}
