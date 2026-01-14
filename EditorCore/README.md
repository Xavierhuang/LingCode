# EditorCore

A pure Swift module implementing a Cursor-style AI Edit Session engine. Designed for clean separation between AI-generated edits and editor implementation.

## Features

- ✅ Pure Swift - No SwiftUI, AppKit, or file system dependencies
- ✅ Streaming text support
- ✅ Multi-file edit proposals
- ✅ Unified diff generation
- ✅ State machine for session lifecycle
- ✅ Deterministic and testable
- ✅ Future-ready for AST integration

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture documentation.

## Core Types

- `AIEditSession` - Main orchestrator for edit sessions
- `EditSessionState` - State machine for session lifecycle
- `ProposedEdit` - Represents a single edit proposal
- `DiffEngine` - Computes unified diffs
- `FileSnapshot` - Immutable file state representation
- `StreamParser` - Parses streaming AI output

## Usage

```swift
import EditorCore

// Create file snapshots
let file = FileSnapshot(
    path: "src/main.swift",
    content: "print(\"Hello\")",
    language: "swift"
)

// Create session
let session = AIEditSession(
    instruction: EditInstruction(text: "Add error handling"),
    fileSnapshots: [file]
)

// Start and stream
session.start()
session.appendStreamingText("...")
session.completeStreaming()

// Access proposed edits
if case .proposed(let edits) = session.state {
    for edit in edits {
        // Preview diff, accept/reject
    }
}
```

## State Machine

```
idle → streaming → parsing → proposed → accepted/rejected
```

## Design Principles

1. **Immutability** - File snapshots and edits are immutable
2. **Pure Functions** - Diff computation is side-effect free
3. **Composability** - Components work independently
4. **Testability** - No UI or file system dependencies
5. **Future-Ready** - Architecture supports AST integration

## Integration

EditorCore is designed to be integrated into your existing SwiftUI app:

1. Create `AIEditSession` instances in your view model
2. Feed streaming text from your AI service
3. Display proposed edits in your UI
4. Call `accept()` or `reject()` based on user action
5. Apply accepted edits to your editor (outside EditorCore)

## License

MIT
