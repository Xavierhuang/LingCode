//
//  AIEditSession.swift
//  EditorCore
//
//  Main orchestrator for AI edit sessions with transaction support
//

import Foundation

/// Main entry point for AI edit sessions
public class AIEditSession {
    public let id: UUID
    public let instruction: EditInstruction
    public let fileSnapshots: [String: FileSnapshot]
    
    /// Expose file snapshots for external access (read-only)
    public var currentFileSnapshots: [String: FileSnapshot] {
        return fileSnapshots
    }
    
    private(set) public var state: EditSessionState {
        didSet {
            stateChangeHandler?(state)
        }
    }
    
    private var accumulatedText: String = ""
    private let diffEngine = DiffEngine()
    private let streamParser = StreamParser()
    private let transactionHistory = TransactionHistory()
    
    public var stateChangeHandler: ((EditSessionState) -> Void)?
    
    /// Current transaction being prepared (if any)
    private var pendingTransaction: EditTransaction?
    
    public init(
        id: UUID = UUID(),
        instruction: EditInstruction,
        fileSnapshots: [FileSnapshot],
        stateChangeHandler: ((EditSessionState) -> Void)? = nil
    ) {
        self.id = id
        self.instruction = instruction
        self.fileSnapshots = Dictionary(uniqueKeysWithValues: fileSnapshots.map { ($0.path, $0) })
        self.state = .idle
        self.stateChangeHandler = stateChangeHandler
    }
    
    // MARK: - Session Lifecycle
    
    /// Start the edit session
    public func start() {
        guard state == .idle else {
            return
        }
        transition(to: .streaming)
    }
    
    /// Append streaming text chunk
    public func appendStreamingText(_ text: String) {
        guard state == .streaming else {
            return
        }
        
        accumulatedText += text
        // State remains streaming
    }
    
    /// Complete streaming and parse edits
    public func completeStreaming() {
        // IMPORTANT: This method must never block the main thread.
        // We keep the integration API synchronous, but perform heavy parse+diff work off-main.
        Task { @MainActor [weak self] in
            await self?.completeStreamingAsync()
        }
    }

    /// Complete streaming and parse edits (async, heavy work off-main).
    ///
    /// This is the true implementation. The synchronous `completeStreaming()` wrapper
    /// exists to preserve the `EditSessionHandle` protocol API.
    @MainActor
    public func completeStreamingAsync() async {
        // Capture required state on the caller thread (typically MainActor via EditSessionHandle).
        guard state == .streaming else {
            return
        }

        transition(to: .parsing)

        let textToParse = accumulatedText
        let snapshots = fileSnapshots

        // HEAVY WORK: Parse + diff in the background.
        let work = Task.detached(priority: .userInitiated) { () -> EditSessionState in
            let parser = StreamParser()
            let engine = DiffEngine()

            let parsedEdits = parser.parseStreamingText(textToParse, fileSnapshots: snapshots)

            let proposedEdits: [ProposedEdit] = parsedEdits.compactMap { parsedEdit in
                guard let snapshot = snapshots[parsedEdit.filePath] else {
                    return nil
                }

                let proposedContent = Self.applyOperation(
                    operation: parsedEdit.operation,
                    originalContent: snapshot.content,
                    newContent: parsedEdit.content,
                    range: parsedEdit.range
                )

                let diff = engine.computeDiff(
                    oldContent: snapshot.content,
                    newContent: proposedContent
                )

                let editType: EditType
                if snapshot.content.isEmpty && !proposedContent.isEmpty {
                    editType = .creation
                } else if !snapshot.content.isEmpty && proposedContent.isEmpty {
                    editType = .deletion
                } else {
                    editType = .modification
                }

                return ProposedEdit(
                    filePath: parsedEdit.filePath,
                    originalContent: snapshot.content,
                    proposedContent: proposedContent,
                    diff: diff,
                    metadata: EditMetadata(editType: editType)
                )
            }

            if proposedEdits.isEmpty {
                return .error("No valid edits found in stream")
            }

            return .proposed(proposedEdits)
        }

        let resultState = await work.value

        // State transitions should be serialized with other session interactions (which occur on MainActor).
        await MainActor.run { [weak self] in
            self?.transition(to: resultState)
        }
    }
    
    // MARK: - Transaction Management
    
    /// Create a transaction from proposed edits (groups edits atomically)
    public func createTransaction(
        editIds: Set<UUID>? = nil,
        metadata: TransactionMetadata? = nil
    ) -> EditTransaction? {
        guard let edits = state.proposedEdits else {
            return nil
        }
        
        let selectedEdits: [ProposedEdit]
        if let editIds = editIds {
            selectedEdits = edits.filter { editIds.contains($0.id) }
        } else {
            selectedEdits = edits
        }
        
        guard !selectedEdits.isEmpty else {
            return nil
        }
        
        // Validate transaction
        let transaction = EditTransaction(
            edits: selectedEdits,
            metadata: metadata ?? TransactionMetadata(description: instruction.text)
        )
        
        guard transaction.isValid(against: fileSnapshots) else {
            return nil
        }
        
        return transaction
    }
    
    /// Prepare a transaction (moves to transactionReady state)
    public func prepareTransaction(
        editIds: Set<UUID>? = nil,
        metadata: TransactionMetadata? = nil
    ) -> Bool {
        guard let transaction = createTransaction(editIds: editIds, metadata: metadata) else {
            return false
        }
        
        pendingTransaction = transaction
        transition(to: .transactionReady(transaction))
        return true
    }
    
    /// Commit the prepared transaction (atomic operation)
    /// Returns the transaction snapshot for undo support
    public func commitTransaction() -> TransactionSnapshot? {
        guard case .transactionReady(let transaction) = state else {
            return nil
        }
        
        // Create snapshot of current state (for undo)
        let snapshot = TransactionSnapshot(
            transactionId: transaction.id,
            fileSnapshots: getAffectedSnapshots(for: transaction)
        )
        
        // Record in history
        transactionHistory.recordApplied(transaction, snapshot: snapshot)
        
        // Commit transaction
        transition(to: .committed(transaction))
        pendingTransaction = nil
        
        return snapshot
    }
    
    /// Rollback the prepared transaction (before commit)
    public func rollbackTransaction() {
        guard case .transactionReady(let transaction) = state else {
            return
        }
        
        transition(to: .rolledBack(transaction))
        pendingTransaction = nil
    }
    
    /// Accept all proposed edits (creates and commits transaction)
    public func acceptAll() -> TransactionSnapshot? {
        guard prepareTransaction() else {
            return nil
        }
        return commitTransaction()
    }
    
    /// Accept specific edits by ID (creates and commits transaction)
    public func accept(editIds: Set<UUID>) -> TransactionSnapshot? {
        guard prepareTransaction(editIds: editIds) else {
            return nil
        }
        return commitTransaction()
    }
    
    /// Reject all proposed edits
    public func rejectAll() {
        guard let edits = state.proposedEdits else {
            return
        }
        transition(to: .rejected(edits))
    }
    
    /// Reject specific edits by ID
    public func reject(editIds: Set<UUID>) {
        guard let allEdits = state.proposedEdits else {
            return
        }
        
        let rejected = allEdits.filter { editIds.contains($0.id) }
        transition(to: .rejected(rejected))
    }
    
    // MARK: - Undo/Redo Support
    
    /// Undo the last committed transaction
    /// Returns the snapshot to restore (caller must apply this)
    public func undoLastTransaction() -> TransactionSnapshot? {
        guard let lastTransaction = transactionHistory.getLastApplied() else {
            return nil
        }
        
        guard let snapshot = transactionHistory.getSnapshot(for: lastTransaction.id) else {
            return nil
        }
        
        // Record as reverted
        transactionHistory.recordReverted(lastTransaction)
        
        return snapshot
    }
    
    /// Redo the last reverted transaction
    /// Returns the transaction to re-apply (caller must apply this)
    public func redoLastTransaction() -> EditTransaction? {
        guard let lastReverted = transactionHistory.getLastReverted() else {
            return nil
        }
        
        // Re-apply to history
        if let snapshot = transactionHistory.getSnapshot(for: lastReverted.id) {
            transactionHistory.recordApplied(lastReverted, snapshot: snapshot)
        }
        
        return lastReverted
    }
    
    /// Check if undo is possible
    public func canUndo() -> Bool {
        return transactionHistory.canUndo()
    }
    
    /// Check if redo is possible
    public func canRedo() -> Bool {
        return transactionHistory.canRedo()
    }
    
    /// Get transaction history (for internal use)
    internal func getTransactionHistory() -> TransactionHistory {
        return transactionHistory
    }
    
    // MARK: - Private Helpers
    
    private func transition(to newState: EditSessionState) {
        // Validate state transitions
        guard isValidTransition(from: state, to: newState) else {
            return
        }
        state = newState
    }
    
    private func isValidTransition(from: EditSessionState, to: EditSessionState) -> Bool {
        // Allow transitions from terminal states only to idle
        if from.isTerminal && to != .idle {
            return false
        }
        
        // Validate specific transitions
        switch (from, to) {
        case (.idle, .streaming),
             (.streaming, .streaming),
             (.streaming, .parsing),
             (.parsing, .proposed),
             (.parsing, .error),
             (.proposed, .transactionReady),
             (.proposed, .rejected),
             (.transactionReady, .committed),
             (.transactionReady, .rolledBack),
             (.committed, .idle),
             (.rolledBack, .idle),
             (.rejected, .idle),
             (.error, .idle):
            return true
        default:
            return false
        }
    }
    
    private func getAffectedSnapshots(for transaction: EditTransaction) -> [String: FileSnapshot] {
        var snapshots: [String: FileSnapshot] = [:]
        for filePath in transaction.affectedFiles {
            if let snapshot = fileSnapshots[filePath] {
                snapshots[filePath] = snapshot
            }
        }
        return snapshots
    }
    
    private static func applyOperation(
        operation: String,
        originalContent: String,
        newContent: String,
        range: (start: Int, end: Int)?
    ) -> String {
        let lines = originalContent.components(separatedBy: .newlines)
        
        switch operation {
        case "insert":
            guard let range = range else {
                return originalContent + "\n" + newContent
            }
            var result = lines
            let insertIndex = min(range.start, result.count)
            let newLines = newContent.components(separatedBy: .newlines)
            result.insert(contentsOf: newLines, at: insertIndex)
            return result.joined(separator: "\n")
            
        case "replace":
            guard let range = range else {
                return newContent
            }
            var result = lines
            let startIndex = max(0, range.start - 1)
            let endIndex = min(range.end, result.count)
            let newLines = newContent.components(separatedBy: .newlines)
            result.replaceSubrange(startIndex..<endIndex, with: newLines)
            return result.joined(separator: "\n")
            
        case "delete":
            guard let range = range else {
                return ""
            }
            var result = lines
            let startIndex = max(0, range.start - 1)
            let endIndex = min(range.end, result.count)
            result.removeSubrange(startIndex..<endIndex)
            return result.joined(separator: "\n")
            
        default:
            return newContent
        }
    }
}
