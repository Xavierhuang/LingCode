# EditorCore Integration Guide

## Integration Boundary

EditorCore provides a **single protocol** and **single observable model** for integration with SwiftUI editors.

## Protocol: `EditSessionCoordinator`

The editor interacts with EditorCore through this single protocol:

```swift
public protocol EditSessionCoordinator {
    func startEditSession(
        instruction: String,
        files: [FileState]
    ) -> EditSessionHandle
    
    var activeSession: EditSessionHandle? { get }
}
```

## Observable Model: `EditSessionModel`

The UI observes a single `ObservableObject`:

```swift
@MainActor
public class EditSessionModel: ObservableObject {
    @Published var status: EditSessionStatus
    @Published var streamingText: String
    @Published var proposedEdits: [EditProposal]
    @Published var errorMessage: String?
}
```

## Integration Flow

```
┌─────────────────┐
│  SwiftUI Editor │
└────────┬────────┘
         │
         │ 1. startEditSession()
         ▼
┌─────────────────────────┐
│ EditSessionCoordinator  │
└────────┬─────────────────┘
         │
         │ 2. Returns EditSessionHandle
         ▼
┌─────────────────────────┐
│   EditSessionHandle     │
│   - appendStreamingText()│
│   - acceptAll()          │
│   - model: EditSessionModel │
└────────┬─────────────────┘
         │
         │ 3. UI observes model
         ▼
┌─────────────────────────┐
│   EditSessionModel      │
│   (ObservableObject)    │
└─────────────────────────┘
```

## Usage Example

### 1. Initialize Coordinator

```swift
let coordinator = DefaultEditSessionCoordinator()
```

### 2. Start Edit Session

```swift
let currentFiles = [
    FileState(id: "file.swift", content: "...", language: "swift")
]

let session = coordinator.startEditSession(
    instruction: "Add error handling",
    files: currentFiles
)
```

### 3. Feed Streaming Text

```swift
// From your AI service
session.appendStreamingText("...")
session.completeStreaming()
```

### 4. Observe UI Updates

```swift
// In SwiftUI
@ObservedObject var model = session.model

// Model automatically updates:
// - model.status
// - model.streamingText
// - model.proposedEdits
```

### 5. Accept/Reject Edits

```swift
// Accept all
let editsToApply = session.acceptAll()

// Apply to editor
for edit in editsToApply {
    editor.openFile(edit.filePath)
    editor.replaceContent(edit.newContent)
}
```

## What EditorCore Hides

The editor **does not need to know about**:
- ❌ `AIEditSession` (internal)
- ❌ `EditTransaction` (internal)
- ❌ `EditSessionState` (internal state machine)
- ❌ `TransactionHistory` (internal)
- ❌ `DiffEngine` (internal)
- ❌ `StreamParser` (internal)

## What EditorCore Exposes

The editor **only sees**:
- ✅ `EditSessionCoordinator` (protocol)
- ✅ `EditSessionHandle` (protocol)
- ✅ `EditSessionModel` (observable)
- ✅ `EditProposal` (UI data)
- ✅ `EditToApply` (final edit instruction)

## Data Flow

1. **Editor → EditorCore**: 
   - `startEditSession(instruction:files:)`
   - `appendStreamingText(_:)`
   - `acceptAll()` / `rejectAll()`

2. **EditorCore → Editor**:
   - `EditSessionModel` updates (via `@Published`)
   - `EditToApply` array (from `acceptAll()`)

## Benefits

1. **Clean Separation**: Editor doesn't know about AI internals
2. **Simple API**: Single protocol, single model
3. **Observable**: SwiftUI-friendly `@Published` properties
4. **Type-Safe**: Strongly typed interfaces
5. **Testable**: Easy to mock `EditSessionCoordinator`

## Implementation Notes

- `EditSessionModel` is `@MainActor` for thread safety
- All UI updates happen on main thread
- Editor applies edits to actual files (EditorCore never touches files)
- Undo/redo supported via `undo()` method
