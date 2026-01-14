//
//  TransactionHistory.swift
//  EditorCore
//
//  Manages transaction history for undo/redo operations
//

import Foundation

/// Manages the history of applied and reverted transactions
public class TransactionHistory {
    private var appliedTransactions: [EditTransaction] = []
    private var revertedTransactions: [EditTransaction] = []
    private var snapshots: [UUID: TransactionSnapshot] = [:]
    
    public let maxHistorySize: Int
    
    public init(maxHistorySize: Int = 100) {
        self.maxHistorySize = maxHistorySize
    }
    
    /// Record a transaction as applied
    public func recordApplied(
        _ transaction: EditTransaction,
        snapshot: TransactionSnapshot
    ) {
        appliedTransactions.append(transaction)
        snapshots[transaction.id] = snapshot
        
        // Maintain history size limit
        if appliedTransactions.count > maxHistorySize {
            let removed = appliedTransactions.removeFirst()
            snapshots.removeValue(forKey: removed.id)
        }
        
        // Clear redo stack when new transaction is applied
        revertedTransactions.removeAll()
    }
    
    /// Record a transaction as reverted
    public func recordReverted(_ transaction: EditTransaction) {
        revertedTransactions.append(transaction)
    }
    
    /// Get the snapshot for a transaction (for undo)
    public func getSnapshot(for transactionId: UUID) -> TransactionSnapshot? {
        return snapshots[transactionId]
    }
    
    /// Get the most recently applied transaction
    public func getLastApplied() -> EditTransaction? {
        return appliedTransactions.last
    }
    
    /// Get the most recently reverted transaction (for redo)
    public func getLastReverted() -> EditTransaction? {
        return revertedTransactions.last
    }
    
    /// Check if undo is possible
    public func canUndo() -> Bool {
        return !appliedTransactions.isEmpty
    }
    
    /// Check if redo is possible
    public func canRedo() -> Bool {
        return !revertedTransactions.isEmpty
    }
    
    /// Get all applied transaction IDs
    public func getAppliedTransactionIds() -> [UUID] {
        return appliedTransactions.map { $0.id }
    }
    
    /// Clear all history
    public func clear() {
        appliedTransactions.removeAll()
        revertedTransactions.removeAll()
        snapshots.removeAll()
    }
}
