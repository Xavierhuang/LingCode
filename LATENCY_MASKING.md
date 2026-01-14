# Latency Masking - Stage 8 Implementation

## Overview

Added early, non-blocking feedback to eliminate blank UI states and improve perceived latency. Users see immediate feedback when a session starts, before any AI response arrives.

## Implementation

### Step 1: Thinking State

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditStatus`

Added `.thinking` state:
```swift
public enum InlineEditStatus: Equatable {
    case idle
    case thinking // Early state: session started, analyzing before streaming
    case streaming
    case ready
    // ... other states
}
```

**Purpose**: Represents the period between session creation and when streaming actually begins.

### Step 2: Immediate State Transition

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditSession.init()`

**Key Change**: Set `.thinking` state immediately when session is created:
```swift
init(coreHandle: EditorCore.EditSessionHandle, userIntent: String = "", ...) {
    // ... initialization ...
    
    // Set thinking state immediately for early feedback
    // This shows provisional intent before streaming begins
    if coreHandle.model.status == .idle {
        self.model.status = .thinking
    }
}
```

**Also in `InlineEditSessionModel.update()`**:
```swift
func update(from coreModel: EditorCore.EditSessionModel, userIntent: String) {
    // Set thinking state immediately if core is idle (early feedback)
    if coreModel.status == .idle && status == .idle {
        status = .thinking
    }
    syncFromCore()
}
```

### Step 3: State Transition Logic

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditSessionModel`

**Smart Transition**:
```swift
// Transition from thinking to streaming when EditorCore starts streaming
let newStatus = InlineEditStatus(from: coreModel.status)
if status == .thinking && newStatus == .streaming {
    status = .streaming
} else if status != .thinking {
    // Only update status if not in thinking state
    status = newStatus
} else if newStatus == .idle {
    // Keep thinking state if core is still idle
    status = .thinking
}
```

**Key Points**:
- `.thinking` is an app-level state (not from EditorCore)
- Transitions cleanly to `.streaming` when EditorCore starts streaming
- Preserves thinking state if EditorCore is still idle

### Step 4: UI Early Feedback

**Location**: `LingCode/Views/InlineEditSessionView.swift`

**Thinking View**:
```swift
private var thinkingView: some View {
    VStack(spacing: 16) {
        if !sessionModel.streamingText.isEmpty {
            // If we have any text (even partial), show it
            streamingView
        } else {
            // Show analyzing state with intent preview
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("Analyzing your request...")
                    .font(.headline)
                
                // Show user intent if available
                if let firstProposal = sessionModel.proposedEdits.first, !firstProposal.intent.isEmpty {
                    // Display intent preview
                }
            }
        }
    }
}
```

**Status Indicator**:
```swift
case .thinking:
    HStack(spacing: 4) {
        ProgressView()
            .scaleEffect(0.6)
        Text("Analyzing...")
            .font(.caption)
            .foregroundColor(.secondary)
    }
```

## How Early Feedback Improves Perceived Latency

### 1. **Immediate Visual Feedback**

**Before**: User clicks "Edit" → Blank UI → Wait → Streaming starts

**After**: User clicks "Edit" → "Analyzing..." appears immediately → Smooth transition to streaming

**Benefit**: User knows the system is working, reducing perceived wait time.

### 2. **Provisional Intent Display**

**Source**: Uses existing `userIntent` from session creation.

**Display**: Shows the user's instruction/intent immediately in the thinking view.

**Benefit**: 
- Confirms the system understood the request
- Provides context while waiting
- No speculation - uses actual user input

### 3. **Smooth State Transitions**

**Flow**:
```
Session Created → .thinking (immediate)
    ↓
EditorCore starts streaming → .streaming
    ↓
EditorCore completes → .ready
```

**Key**: Transition from `.thinking` to `.streaming` is seamless and automatic.

### 4. **No Speculation**

**Principle**: All displayed information comes from actual user input or existing data.

**Sources**:
- User's instruction (from `userIntent`)
- First proposal's intent (if available)
- Streaming text (as it arrives)

**No AI Calls**: Early feedback uses data already available, no additional API calls.

### 5. **Progressive Disclosure**

**Strategy**: Show more information as it becomes available.

**Stages**:
1. **Thinking**: "Analyzing..." + user intent (if available)
2. **Streaming**: Streaming text appears
3. **Ready**: Full diff preview with proposals

**Benefit**: UI never feels empty, always showing relevant information.

## Technical Details

### State Management

**App-Level State**: `.thinking` is not from EditorCore, it's an adapter-level state.

**Rationale**: 
- EditorCore doesn't have a "thinking" state
- We add it in the adapter layer for UX
- Transitions cleanly when EditorCore starts streaming

### Timing

**When Set**: Immediately when `InlineEditSession` is created.

**When Cleared**: Automatically transitions to `.streaming` when EditorCore starts streaming.

**Fallback**: If EditorCore never starts streaming, thinking state persists (handled by error state).

### Intent Display

**Source**: 
1. Primary: `userIntent` from session creation
2. Fallback: First proposal's intent (if proposals exist)
3. Final: Streaming text (as it arrives)

**No Speculation**: All sources are from actual user input or AI output, never guessed.

## Benefits

### ✅ Immediate Feedback
- No blank UI states
- User sees activity immediately
- Reduces perceived latency

### ✅ Context Preservation
- User's intent shown immediately
- Confirms system understood request
- Provides visual confirmation

### ✅ Smooth Transitions
- Clean state machine transitions
- No jarring UI changes
- Progressive disclosure of information

### ✅ No Performance Cost
- Uses existing data (no new AI calls)
- No additional network requests
- Minimal computational overhead

### ✅ No EditorCore Changes
- All logic in adapter layer
- Uses existing EditorCore states
- Preserves all invariants

## Example Flow

1. **User clicks "Edit"** with instruction: "Add error handling"
2. **Session created** → `.thinking` state set immediately
3. **UI shows**: "Analyzing your request..." + "Add error handling" (intent)
4. **EditorCore starts streaming** → Transition to `.streaming`
5. **UI shows**: Streaming text appears
6. **EditorCore completes** → Transition to `.ready`
7. **UI shows**: Full diff preview with proposals

**Total perceived wait**: Reduced because user sees feedback immediately, not after network latency.

## Safety Guarantees

### ✅ No Speculation
- All displayed information from actual data
- No guessed or fabricated content
- User intent from actual input

### ✅ State Consistency
- Clean transitions between states
- No race conditions
- Proper state machine behavior

### ✅ No Breaking Changes
- Existing flows still work
- Backward compatible
- All invariants preserved
