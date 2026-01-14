//
//  ExampleUsage.swift
//  EditorCore
//
//  Example usage of EditorCore (no UI, no networking)
//

import Foundation
import EditorCore

// MARK: - Example 1: Basic Edit Session

func exampleBasicEditSession() {
    // Create file snapshots
    let file1 = FileSnapshot(
        path: "src/main.swift",
        content: "print(\"Hello, World!\")",
        language: "swift"
    )
    
    let file2 = FileSnapshot(
        path: "src/utils.swift",
        content: "func add(a: Int, b: Int) -> Int { return a + b }",
        language: "swift"
    )
    
    // Create instruction
    let instruction = EditInstruction(
        text: "Add error handling to the add function",
        context: ["focus": "utils.swift"]
    )
    
    // Create session
    let session = AIEditSession(
        instruction: instruction,
        fileSnapshots: [file1, file2]
    )
    
    // Monitor state changes
    session.stateChangeHandler = { state in
        print("State changed: \(state)")
    }
    
    // Start session
    session.start()
    
    // Simulate streaming text (in real app, this comes from AI API)
    let streamingText = """
    `src/utils.swift`:
    ```swift
    func add(a: Int, b: Int) -> Int {
        guard a >= 0 && b >= 0 else {
            throw NegativeNumberError()
        }
        return a + b
    }
    ```
    """
    
    // Feed streaming chunks
    session.appendStreamingText(streamingText)
    
    // Complete streaming
    session.completeStreaming()
    
    // Access proposed edits
    if case .proposed(let edits) = session.state {
        for edit in edits {
            print("Edit for \(edit.filePath):")
            print("  Added: \(edit.diff.addedLines) lines")
            print("  Removed: \(edit.diff.removedLines) lines")
            
            // Preview diff
            for hunk in edit.diff.hunks {
                print("  Hunk at lines \(hunk.oldStartLine)-\(hunk.oldStartLine + hunk.oldLineCount)")
                for line in hunk.lines {
                    switch line {
                    case .added(let text, let num):
                        print("    +\(num): \(text)")
                    case .removed(let text, let num):
                        print("    -\(num): \(text)")
                    case .unchanged(let text, let num):
                        print("     \(num): \(text)")
                    }
                }
            }
        }
        
        // Accept all edits
        session.acceptAll()
    }
}

// MARK: - Example 2: JSON Edit Format

func exampleJSONEditFormat() {
    let file = FileSnapshot(
        path: "config.json",
        content: """
        {
          "name": "MyApp",
          "version": "1.0.0"
        }
        """,
        language: "json"
    )
    
    let session = AIEditSession(
        instruction: EditInstruction(text: "Update version to 2.0.0"),
        fileSnapshots: [file]
    )
    
    session.start()
    
    // JSON edit format (preferred for targeted edits)
    let jsonEdit = """
    ```json
    {
      "edits": [
        {
          "file": "config.json",
          "operation": "replace",
          "range": {
            "startLine": 3,
            "endLine": 3
          },
          "content": [
            "  \"version\": \"2.0.0\""
          ]
        }
      ]
    }
    ```
    """
    
    session.appendStreamingText(jsonEdit)
    session.completeStreaming()
    
    if case .proposed(let edits) = session.state {
        // Edits are ready for review
        print("Proposed \(edits.count) edit(s)")
    }
}

// MARK: - Example 3: Multi-file Edit

func exampleMultiFileEdit() {
    let files = [
        FileSnapshot(path: "src/model.swift", content: "struct User {}", language: "swift"),
        FileSnapshot(path: "src/view.swift", content: "struct UserView {}", language: "swift"),
        FileSnapshot(path: "src/controller.swift", content: "class UserController {}", language: "swift")
    ]
    
    let session = AIEditSession(
        instruction: EditInstruction(text: "Add ID property to User model and update all references"),
        fileSnapshots: files
    )
    
    session.start()
    
    // Simulate multi-file streaming response
    let multiFileResponse = """
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
    
    session.appendStreamingText(multiFileResponse)
    session.completeStreaming()
    
    if case .proposed(let edits) = session.state {
        print("Proposed edits for \(edits.count) files")
        
        // Selectively accept/reject
        let acceptedIds = Set(edits.prefix(1).map { $0.id })
        session.accept(editIds: acceptedIds)
    }
}

// MARK: - Example 4: Using Diff Engine Directly

func exampleDirectDiffEngine() {
    let engine = DiffEngine()
    
    let oldContent = """
    func greet(name: String) {
        print("Hello, \(name)")
    }
    """
    
    let newContent = """
    func greet(name: String) {
        print("Hello, \(name)!")
        print("Welcome!")
    }
    """
    
    let diff = engine.computeDiff(oldContent: oldContent, newContent: newContent)
    
    print("Diff statistics:")
    print("  Added: \(diff.addedLines) lines")
    print("  Removed: \(diff.removedLines) lines")
    print("  Unchanged: \(diff.unchangedLines) lines")
    print("  Hunks: \(diff.hunks.count)")
}

// MARK: - Example 5: State Machine

func exampleStateMachine() {
    let session = AIEditSession(
        instruction: EditInstruction(text: "Refactor code"),
        fileSnapshots: []
    )
    
    // Track all state transitions
    var states: [EditSessionState] = []
    session.stateChangeHandler = { state in
        states.append(state)
        print("→ \(state)")
    }
    
    // Valid transitions
    session.start()                    // idle → streaming
    session.appendStreamingText("...") // streaming → streaming
    session.completeStreaming()         // streaming → parsing → proposed
    
    if case .proposed(let edits) = session.state {
        session.acceptAll()             // proposed → accepted
    }
    
    print("\nState history:")
    for (index, state) in states.enumerated() {
        print("  \(index + 1). \(state)")
    }
}
