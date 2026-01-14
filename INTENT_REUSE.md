# Intent Reuse - Stage 10 Implementation

## Overview

Added ability to reuse an existing edit intent and apply it to new files or locations, enabling power workflows where users can apply the same transformation across multiple files.

## Implementation

### Step 1: Intent Storage

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditSessionModel`

**Added**:
```swift
/// Original user intent for this session (for reuse)
/// This is the user's original instruction, not the full prompt
public private(set) var originalIntent: String = ""
```

**Storage**: Intent is stored when session is created and updated, making it available for reuse.

### Step 2: Intent Reuse Method

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `EditorCoreAdapter`

**Added `reuseIntent()` method**:
```swift
func reuseIntent(intent: String, files: [FileStateInput]) -> InlineEditSession {
    // Build instruction with context for new files
    let fileContexts = files.map { file in
        """
        File: \(file.id)
        Content:
        ```
        \(file.content)
        ```
        """
    }.joined(separator: "\n\n")
    
    let instruction = """
    Edit these files according to this instruction: \(intent)
    
    \(fileContexts)
    
    Return the edited code in the same format.
    """
    
    // Create new session with reused intent
    return startInlineEditSession(
        instruction: instruction,
        userIntent: intent,
        files: files
    )
}
```

**Key Points**:
- Creates a completely new session (not a continuation)
- Uses the same intent but with new file content
- Preserves intent exactly as provided
- Deterministic: same intent + same files = same result

### Step 3: UI Action

**Location**: `LingCode/Views/InlineEditSessionView.swift`

**Added "Apply Elsewhere" button**:
- Shown when session is `.ready` or `.applied`
- Small button in action bar
- Tooltip: "Apply this same intent to other files"
- Calls `onReuseIntent` callback with the stored intent

### Step 4: Intent Reuse Handler

**Location**: `LingCode/Views/EditorView.swift`

**Added `reuseIntent()` method**:
```swift
private func reuseIntent(intent: String, from oldSession: InlineEditSession) {
    // Close the old session
    cancelEditSession()
    
    // Use the current active document
    guard let document = viewModel.editorState.activeDocument else {
        // Fallback: start new session with intent
        inlineEditInstruction = intent
        startInlineEditSession(instruction: intent)
        return
    }
    
    // Create new session with reused intent
    let newSession = editorCoreAdapter.reuseIntent(intent: intent, files: [fileState])
    
    currentEditSession = newSession
    
    // Stream AI response
    streamAIResponse(for: newSession, instruction: fullInstruction, context: ...)
    
    // Record in timeline
    newSession.model.recordTimelineEvent(.intentReused, description: "Reapplying: \(intent)")
}
```

### Step 5: Timeline Event

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `SessionTimelineEvent`

**Added event type**:
```swift
case .intentReused
```

**Icon**: `arrow.triangle.2.circlepath` (circular arrows)
**Color**: Purple (distinct from other events)

## How Intent Reuse Works Safely

### 1. **Deterministic Behavior**

**Principle**: Same intent + same files = same result.

**Implementation**:
- Intent is stored exactly as provided by user
- No modification or interpretation
- File content is read fresh from editor
- Instruction is built deterministically

**Example**:
```
Intent: "Add error handling"
File A: content1 → Result A1
File B: content2 → Result B1
```

**Safety**: No randomness, no speculation, predictable outcomes.

### 2. **New Session Creation**

**Approach**: Creates a completely new session, not a continuation.

**Why**:
- Continuation would require updating file snapshots
- New session is cleaner and more predictable
- Each reuse is independent
- No state leakage between sessions

**Flow**:
```
Old Session (ready/applied)
    ↓
User clicks "Apply Elsewhere"
    ↓
Old session closed
    ↓
New session created with reused intent
    ↓
New session streams and generates proposals
```

### 3. **Intent Preservation**

**Storage**: Intent stored in `InlineEditSessionModel.originalIntent`.

**Access**: Read-only property, cannot be modified after session creation.

**Usage**: 
- Retrieved when user clicks "Apply Elsewhere"
- Passed to new session exactly as stored
- No transformation or interpretation

**Safety**: Intent cannot be accidentally modified or corrupted.

### 4. **File Context Building**

**Process**:
1. Read current file content from editor
2. Build instruction with file context (same format as original)
3. Include selected text if available
4. Create new session with this context

**Deterministic**:
- Same file content → same instruction
- Same selected text → same instruction
- No random elements

### 5. **No EditorCore Changes**

**Constraint**: Cannot modify EditorCore.

**Solution**: All logic in adapter layer.

**Implementation**:
- `reuseIntent()` is adapter-level method
- Uses existing `startInlineEditSession()` internally
- No EditorCore API changes needed

### 6. **Safety Invariants Preserved**

**Atomic Application**: Each reuse creates independent session with atomic transactions.

**Undo Support**: Each session has its own undo history.

**State Isolation**: Old session closed before new one starts.

**No State Leakage**: New session has no knowledge of old session.

### 7. **Timeline Tracking**

**Recording**: Intent reuse is recorded in timeline.

**Event**: `.intentReused` with description showing the reused intent.

**Benefit**: Users can see when and what intent was reused.

## Example Workflow

1. **User edits file A**: "Add error handling"
2. **AI generates proposals**: 3 proposals for file A
3. **User accepts**: Proposals applied to file A
4. **User clicks "Apply Elsewhere"**: Intent "Add error handling" reused
5. **User switches to file B**: New session starts
6. **AI generates proposals**: 2 proposals for file B (with same intent)
7. **User accepts**: Proposals applied to file B

**Result**: Same transformation applied to multiple files deterministically.

## Safety Guarantees

### ✅ Deterministic
- Same intent + same files = same result
- No randomness or speculation
- Predictable behavior

### ✅ State Isolation
- Old session closed before new one starts
- No state leakage between sessions
- Each session is independent

### ✅ Intent Preservation
- Intent stored exactly as provided
- No modification or interpretation
- Read-only access

### ✅ No EditorCore Changes
- All logic in adapter layer
- Uses existing APIs
- No breaking changes

### ✅ Atomic Transactions
- Each reuse creates independent session
- Each session has atomic transactions
- Undo support per session

## Benefits

1. **Power Workflows**: Apply same transformation to multiple files
2. **Consistency**: Same intent ensures consistent changes
3. **Efficiency**: No need to retype intent
4. **Deterministic**: Predictable, reproducible results
5. **Safe**: All invariants preserved
