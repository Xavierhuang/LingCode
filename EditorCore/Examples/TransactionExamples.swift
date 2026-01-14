//
//  TransactionExamples.swift
//  EditorCore
//
//  Examples demonstrating transaction support, undo/redo, and atomic operations
//

import Foundation
import EditorCore

// MARK: - Example 1: Atomic Transaction

func exampleAtomicTransaction() {
    let files = [
        FileSnapshot(path: "src/model.swift", content: "struct User {}", language: "swift"),
        FileSnapshot(path: "src/view.swift", content: "struct UserView {}", language: "swift")
    ]
    
    let session = AIEditSession(
        instruction: EditInstruction(text: "Add ID property to User and update view"),
        fileSnapshots: files
    )
    
    session.start()
    
    // Simulate multi-file streaming
    let response = """
    `src/model.swift`:
    ```swift
    struct User {
        let id: UUID
    }
    ```
    
    `src/view.swift`:
    ```swift
    struct UserView {
        let user: User
        var userId: UUID { user.id }
    }
    ```
    """
    
    session.appendStreamingText(response)
    session.completeStreaming()
    
    // Create transaction (groups both edits atomically)
    guard session.prepareTransaction() else {
        print("Failed to create transaction")
        return
    }
    
    // Transaction is ready - both edits are grouped together
    if case .transactionReady(let transaction) = session.state {
        print("Transaction ready with \(transaction.edits.count) edits")
        print("Affected files: \(transaction.affectedFiles)")
        
        // Commit atomically (all or nothing)
        if let snapshot = session.commitTransaction() {
            print("Transaction committed successfully")
            print("Snapshot saved for undo: \(snapshot.transactionId)")
        }
    }
}

// MARK: - Example 2: Selective Transaction

func exampleSelectiveTransaction() {
    let session = AIEditSession(
        instruction: EditInstruction(text: "Refactor multiple files"),
        fileSnapshots: [
            FileSnapshot(path: "file1.swift", content: "code1", language: "swift"),
            FileSnapshot(path: "file2.swift", content: "code2", language: "swift"),
            FileSnapshot(path: "file3.swift", content: "code3", language: "swift")
        ]
    )
    
    session.start()
    session.appendStreamingText("...") // Simulate streaming
    session.completeStreaming()
    
    // Select only specific edits for transaction
    if case .proposed(let edits) = session.state {
        let selectedIds = Set(edits.prefix(2).map { $0.id })
        
        // Create transaction with only selected edits
        if session.prepareTransaction(editIds: selectedIds) {
            if let snapshot = session.commitTransaction() {
                print("Committed transaction with 2 edits")
                print("Remaining edit can be in separate transaction")
            }
        }
    }
}

// MARK: - Example 3: Undo/Redo

func exampleUndoRedo() {
    let file = FileSnapshot(
        path: "main.swift",
        content: "print(\"Hello\")",
        language: "swift"
    )
    
    let session = AIEditSession(
        instruction: EditInstruction(text: "Add error handling"),
        fileSnapshots: [file]
    )
    
    session.start()
    session.appendStreamingText("...")
    session.completeStreaming()
    
    // Commit first transaction
    if let snapshot1 = session.acceptAll() {
        print("Transaction 1 committed")
        
        // Start new session for second edit
        let session2 = AIEditSession(
            instruction: EditInstruction(text: "Add logging"),
            fileSnapshots: [FileSnapshot(
                path: "main.swift",
                content: snapshot1.fileSnapshots["main.swift"]?.content ?? "",
                language: "swift"
            )]
        )
        
        session2.start()
        session2.appendStreamingText("...")
        session2.completeStreaming()
        
        if let snapshot2 = session2.acceptAll() {
            print("Transaction 2 committed")
            
            // Undo last transaction
            if let undoSnapshot = session2.undoLastTransaction() {
                print("Undone transaction 2")
                print("Restore to: \(undoSnapshot.fileSnapshots)")
                
                // Redo
                if let redoTransaction = session2.redoLastTransaction() {
                    print("Redone transaction")
                }
            }
        }
    }
}

// MARK: - Example 4: Rollback Before Commit

func exampleRollback() {
    let session = AIEditSession(
        instruction: EditInstruction(text: "Make changes"),
        fileSnapshots: [
            FileSnapshot(path: "file.swift", content: "original", language: "swift")
        ]
    )
    
    session.start()
    session.appendStreamingText("...")
    session.completeStreaming()
    
    // Prepare transaction
    if session.prepareTransaction() {
        print("Transaction prepared")
        
        // User reviews and decides to cancel
        session.rollbackTransaction()
        
        if case .rolledBack = session.state {
            print("Transaction rolled back - no changes committed")
        }
    }
}

// MARK: - Example 5: Transaction Validation

func exampleTransactionValidation() {
    let session = AIEditSession(
        instruction: EditInstruction(text: "Edit files"),
        fileSnapshots: [
            FileSnapshot(path: "existing.swift", content: "code", language: "swift")
        ]
    )
    
    session.start()
    session.appendStreamingText("...")
    session.completeStreaming()
    
    // Try to create transaction with invalid edit (references non-existent file)
    if case .proposed(let edits) = session.state {
        // Create transaction
        if let transaction = session.createTransaction() {
            // Validate transaction
            let isValid = transaction.isValid(against: session.fileSnapshots)
            print("Transaction valid: \(isValid)")
            print("Affected files: \(transaction.affectedFiles)")
        }
    }
}

// MARK: - Example 6: Prevent Partial Commits

func examplePreventPartialCommits() {
    let session = AIEditSession(
        instruction: EditInstruction(text: "Multi-file refactor"),
        fileSnapshots: [
            FileSnapshot(path: "file1.swift", content: "code1", language: "swift"),
            FileSnapshot(path: "file2.swift", content: "code2", language: "swift")
        ]
    )
    
    session.start()
    session.appendStreamingText("...")
    session.completeStreaming()
    
    // Transaction ensures all edits are applied together
    // If any edit fails validation, entire transaction is rejected
    if session.prepareTransaction() {
        // At this point, all edits are validated
        // Commit is atomic - either all succeed or all fail
        if let snapshot = session.commitTransaction() {
            print("All edits committed atomically")
        } else {
            print("Transaction commit failed - no partial state")
        }
    }
}
