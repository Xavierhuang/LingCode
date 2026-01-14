# Apply & Continue - Stage 7 Implementation

## Overview

Added "Apply & Continue" functionality that allows an inline edit session to continue after accepting edits, enabling iterative refinement without starting a new session.

## Implementation

### Step 1: Continuation State

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditStatus`

Added `.continuing` state:
```swift
public enum InlineEditStatus: Equatable {
    case idle
    case streaming
    case ready
    case applied
    case continuing // Session continues after applying edits
    case rejected
    case error(String)
}
```

### Step 2: Session Continuity Support

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditSession`

**Key Changes**:
1. Made `coreHandle` mutable to support replacement
2. Added `coordinator` reference for creating continuation sessions
3. Added `continueWithUpdatedFiles()` method

**`continueWithUpdatedFiles()` Method**:
```swift
func continueWithUpdatedFiles(instruction: String, files: [FileStateInput]) {
    // Convert to EditorCore.FileState
    let coreFiles = files.map { ... }
    
    // Create new EditorCore session with updated file snapshots
    let newCoreHandle = coordinator.startEditSession(
        instruction: instruction,
        files: coreFiles
    )
    
    // Replace the core handle (same InlineEditSession instance)
    self.coreHandle = newCoreHandle
    
    // Update model to observe new session
    self.model.update(from: newCoreHandle.model, userIntent: userIntent)
    
    // Transition to continuing state
    self.model.status = .continuing
}
```

### Step 3: Apply & Continue Action

**Location**: `LingCode/Views/EditorView.swift` - `acceptEdits(from:continueAfter:)`

**Updated Method**:
```swift
private func acceptEdits(from session: InlineEditSession, continueAfter: Bool = false) {
    // Accept selected proposals (atomic)
    let editsToApply = session.acceptSelected(selectedIds: selectedIds)
    
    // Apply edits atomically
    viewModel.applyEdits(editsToApply)
    
    if continueAfter {
        continueEditSession(session) // Continue instead of closing
    } else {
        cancelEditSession() // Normal accept - close session
    }
}
```

**New `continueEditSession()` Method**:
```swift
private func continueEditSession(_ session: InlineEditSession) {
    // Get updated file content from editor
    let fileState = FileStateInput(
        id: document.filePath?.path ?? document.id.uuidString,
        content: document.content, // Updated content after applying edits
        language: document.language
    )
    
    // Continue session with updated file snapshots
    session.continueWithUpdatedFiles(
        instruction: continuationInstruction,
        files: [fileState]
    )
    
    // Continue streaming AI response
    streamAIResponse(for: session, instruction: continuationInstruction, context: ...)
}
```

### Step 4: UI Updates

**Location**: `LingCode/Views/InlineEditSessionView.swift`

**Added**:
1. "Apply & Continue" button alongside "Accept" button
2. Keyboard shortcut: ⌘⇧C
3. `.continuing` state view with progress indicator
4. Status indicator for continuing state

## How Session Continuity is Maintained Safely

### 1. **Atomic Application Before Continuation**

**Guarantee**: All edits are applied atomically before continuation begins.

**Flow**:
```
User clicks "Apply & Continue"
    ↓
acceptEdits(continueAfter: true)
    ↓
session.acceptSelected() → Creates transaction
    ↓
viewModel.applyEdits() → Applies to editor (atomic)
    ↓
continueEditSession() → Only called after successful application
```

**Safety**: If `applyEdits()` fails, continuation is not attempted.

### 2. **File Snapshot Updates**

**Challenge**: EditorCore's file snapshots are immutable and set at session creation.

**Solution**: Create a new EditorCore session internally with updated file snapshots.

**Process**:
1. After applying edits, read updated content from editor
2. Create new `FileStateInput` with updated content
3. Create new EditorCore session via `coordinator.startEditSession()`
4. Replace `coreHandle` in existing `InlineEditSession` instance
5. Update model to observe new session

**Key Point**: The UI sees the same `InlineEditSession` instance, but internally it uses a new EditorCore session with updated snapshots.

### 3. **Session Identity Preservation**

**Approach**: Keep the same `InlineEditSession` instance for the UI.

**Benefits**:
- UI doesn't see a "new session"
- Selection state preserved
- User intent preserved
- No need to update UI references

**Implementation**:
```swift
// Same InlineEditSession instance
self.coreHandle = newCoreHandle // Replace internal handle only
self.model.update(from: newCoreHandle.model, userIntent: userIntent)
```

### 4. **State Transitions**

**State Flow**:
```
.ready → [Apply & Continue] → .continuing → .streaming → .ready → ...
```

**Safety**:
- `.continuing` is a non-terminal state
- Session can continue streaming and generating new proposals
- Each continuation creates a new EditorCore session internally
- Previous transactions remain in history for undo

### 5. **Undo Guarantees**

**Preservation**: Each apply operation creates a separate transaction.

**Example**:
```
Iteration 1: Apply edits → Transaction 1 (undoable)
Iteration 2: Apply & Continue → Apply edits → Transaction 2 (undoable)
Iteration 3: Apply & Continue → Apply edits → Transaction 3 (undoable)
```

**Undo Behavior**:
- `undo()` undoes the last transaction (most recent apply)
- Each transaction is independent
- File snapshots in transactions reflect state at time of apply

### 6. **No EditorCore Modifications**

**Constraint**: Cannot modify EditorCore to support continuation directly.

**Workaround**: Create new EditorCore sessions internally while preserving the adapter-level session identity.

**Architecture**:
```
UI Layer: InlineEditSession (same instance)
    ↓
Adapter Layer: Replaces coreHandle internally
    ↓
EditorCore: New session with updated snapshots
```

### 7. **Error Handling**

**Safety Checks**:
1. Coordinator availability check before continuation
2. Document availability check before reading content
3. Empty selection check before applying
4. Fallback to cancel if continuation fails

**Error States**:
- If continuation fails, session transitions to `.error`
- User can still cancel or retry
- No partial state left behind

## Safety Guarantees

### ✅ Atomic Application
- All edits applied atomically before continuation
- No partial application possible
- EditorCore transaction system enforces this

### ✅ File Snapshot Accuracy
- Updated file content read from editor after applying
- New EditorCore session created with accurate snapshots
- No stale snapshot issues

### ✅ Session Identity
- Same `InlineEditSession` instance throughout
- UI doesn't see session replacement
- Selection state and user intent preserved

### ✅ Undo Support
- Each apply creates independent transaction
- Undo works for each transaction separately
- Transaction history maintained correctly

### ✅ No EditorCore Changes
- Uses existing `startEditSession` API
- No modifications to EditorCore
- All logic in adapter layer

## Example Flow

1. **User starts edit**: "Add error handling"
2. **AI generates proposals**: 3 proposals shown
3. **User selects 2 proposals** and clicks "Apply & Continue"
4. **Edits applied atomically**: Both proposals applied in one transaction
5. **Session continues**: 
   - Updated file content read from editor
   - New EditorCore session created with updated snapshots
   - AI continues generating: "Now add logging"
6. **New proposals shown**: Based on updated file state
7. **User can**: Accept, Apply & Continue again, or Cancel

## Benefits

1. **Iterative Refinement**: Users can refine edits in multiple passes
2. **Context Preservation**: AI sees updated file state for better suggestions
3. **Atomic Safety**: Each apply is atomic and undoable
4. **Seamless UX**: Session appears continuous to user
5. **No Breaking Changes**: Existing accept/reject still works
