//
//  EditSessionCoordinatorImpl.swift
//  EditorCore
//
//  Implementation of EditSessionCoordinator using EditorCore internals
//

import Foundation
#if canImport(Combine)
import Combine
#endif

/// Default implementation of EditSessionCoordinator
public class DefaultEditSessionCoordinator: EditSessionCoordinator {
    private var currentSession: EditSessionHandleImpl?
    
    public init() {}
    
    public var activeSession: EditSessionHandle? {
        return currentSession
    }
    
    @MainActor
    public func startEditSession(
        instruction: String,
        files: [FileState]
    ) -> EditSessionHandle {
        // Convert FileState to FileSnapshot
        let snapshots = files.map { fileState in
            FileSnapshot(
                path: fileState.id,
                content: fileState.content,
                language: fileState.language
            )
        }
        
        // Create internal AIEditSession
        let editInstruction = EditInstruction(text: instruction)
        let internalSession = AIEditSession(
            instruction: editInstruction,
            fileSnapshots: snapshots
        )
        
        // Create handle that wraps internal session
        let handle = EditSessionHandleImpl(
            coordinator: self,
            internalSession: internalSession
        )
        
        currentSession = handle
        return handle
    }
    
    func sessionCompleted(_ handle: EditSessionHandleImpl) {
        if currentSession === handle {
            currentSession = nil
        }
    }
}

// MARK: - Edit Session Handle Implementation

/// Internal implementation of EditSessionHandle
@MainActor
class EditSessionHandleImpl: EditSessionHandle {
    weak var coordinator: DefaultEditSessionCoordinator?
    let internalSession: AIEditSession
    let model = EditSessionModel()
    
    var id: UUID {
        internalSession.id
    }
    
    var canUndo: Bool {
        internalSession.canUndo()
    }
    
    init(coordinator: DefaultEditSessionCoordinator, internalSession: AIEditSession) {
        self.coordinator = coordinator
        self.internalSession = internalSession
        
        // Bridge internal state to UI model
        setupStateBridge()
        
        // Start session
        internalSession.start()
    }
    
    func appendStreamingText(_ text: String) {
        internalSession.appendStreamingText(text)
        // Update streaming text in model
        model.streamingText += text
    }
    
    func completeStreaming() {
        internalSession.completeStreaming()
    }
    
    func acceptAll() -> [EditToApply] {
        guard let snapshot = internalSession.acceptAll() else {
            return []
        }
        
        // Convert committed transaction to EditToApply
        return extractEditsToApply(from: snapshot)
    }
    
    func accept(editIds: Set<UUID>) -> [EditToApply] {
        guard let snapshot = internalSession.accept(editIds: editIds) else {
            return []
        }
        
        return extractEditsToApply(from: snapshot)
    }
    
    func rejectAll() {
        internalSession.rejectAll()
    }
    
    func reject(editIds: Set<UUID>) {
        internalSession.reject(editIds: editIds)
    }
    
    func undo() -> [EditToApply]? {
        // Get the transaction before undoing (so we can access its edits)
        let history = internalSession.getTransactionHistory()
        guard let lastTransaction = history.getLastApplied() else {
            return nil
        }
        
        // Undo the transaction
        guard let snapshot = internalSession.undoLastTransaction() else {
            return nil
        }
        
        // Convert to edits that restore original state
        // Use snapshot content (original state) as newContent
        // Use transaction's proposed content as originalContent (what was applied)
        return lastTransaction.edits.compactMap { edit in
            guard let originalSnapshot = snapshot.fileSnapshots[edit.filePath] else {
                return nil
            }
            return EditToApply(
                id: edit.id,
                filePath: edit.filePath,
                newContent: originalSnapshot.content, // Restore to original (from snapshot)
                originalContent: edit.proposedContent // Current content (what was applied)
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupStateBridge() {
        internalSession.stateChangeHandler = { [weak self] state in
            Task { @MainActor in
                self?.updateModel(from: state)
            }
        }
    }
    
    private func updateModel(from state: EditSessionState) {
        switch state {
        case .idle:
            model.status = .idle
            model.streamingText = ""
            model.proposedEdits = []
            model.errorMessage = nil
            
        case .streaming:
            model.status = .streaming
            
        case .parsing:
            model.status = .streaming // Still show as streaming during parse
            
        case .proposed(let edits):
            model.status = .ready
            model.proposedEdits = edits.map { convertToEditProposal($0) }
            
        case .transactionReady:
            model.status = .ready
            
        case .committed:
            model.status = .applied
            // Clear proposed edits after commit
            model.proposedEdits = []
            
        case .rolledBack:
            model.status = .ready // Back to ready state
            
        case .rejected:
            model.status = .rejected
            model.proposedEdits = []
            
        case .error(let message):
            model.status = .error(message)
            model.errorMessage = message
        }
    }
    
    private func convertToEditProposal(_ edit: ProposedEdit) -> EditProposal {
        let fileName = (edit.filePath as NSString).lastPathComponent
        
        // Convert diff hunks to preview format
        let diffHunks = edit.diff.hunks.map { hunk in
            DiffHunkPreview(
                oldStartLine: hunk.oldStartLine,
                newStartLine: hunk.newStartLine,
                lines: hunk.lines.map { line in
                    let (type, content, lineNum) = convertDiffLine(line)
                    return DiffLinePreview(
                        type: type,
                        content: content,
                        lineNumber: lineNum
                    )
                }
            )
        }
        
        let preview = EditPreview(
            addedLines: edit.diff.addedLines,
            removedLines: edit.diff.removedLines,
            diffHunks: diffHunks
        )
        
        let statistics = EditStatistics(
            addedLines: edit.diff.addedLines,
            removedLines: edit.diff.removedLines
        )
        
        return EditProposal(
            id: edit.id,
            filePath: edit.filePath,
            fileName: fileName,
            preview: preview,
            statistics: statistics
        )
    }
    
    private func convertDiffLine(_ line: DiffLine) -> (DiffLinePreview.ChangeType, String, Int) {
        switch line {
        case .unchanged(let content, let num):
            return (.unchanged, content, num)
        case .added(let content, let num):
            return (.added, content, num)
        case .removed(let content, let num):
            return (.removed, content, num)
        }
    }
    
    private func extractEditsToApply(from snapshot: TransactionSnapshot) -> [EditToApply] {
        // Get the committed transaction from history
        let history = internalSession.getTransactionHistory()
        guard let transaction = history.getLastApplied() else {
            return []
        }
        
        // Convert transaction edits to EditToApply
        return transaction.edits.map { edit in
            EditToApply(
                id: edit.id,
                filePath: edit.filePath,
                newContent: edit.proposedContent,
                originalContent: edit.originalContent
            )
        }
    }
}
