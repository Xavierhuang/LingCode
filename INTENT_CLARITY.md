# Intent Clarity - Stage 5 Implementation

## Overview

Added human-readable intent descriptions to inline edit proposals to improve UX clarity. Each edit proposal now displays a clear description of what the edit is intended to do.

## Implementation

### Step 1: Extended InlineEditProposal

**Location**: `LingCode/Services/EditorCoreAdapter.swift`

Added `intent: String` field to `InlineEditProposal`:
```swift
public struct InlineEditProposal: Equatable, Identifiable {
    // ... existing fields ...
    /// Human-readable intent description for this edit
    public let intent: String
}
```

### Step 2: Intent Derivation Logic

**Location**: `InlineEditSessionModel.deriveIntent()`

Intent is derived from existing data (no new AI calls):

1. **Primary Source**: Original user instruction
   - Removes common prefixes like "Edit the selected code according to this instruction:"
   - Simplifies to the core intent
   - Truncates to first sentence or 100 characters if too long

2. **Fallback Source**: Streaming text explanation
   - If instruction is too short/empty, extracts explanation from AI response
   - Takes text before first code block (```)
   - Uses first sentence or first 80 characters

3. **Final Fallback**: Generic message
   - "Edit code" if no intent can be derived

**Algorithm**:
```swift
1. Start with original user instruction
2. Remove instruction prefixes ("Edit:", "Change:", etc.)
3. If > 100 chars, take first sentence or first 100 chars
4. If still empty/short, extract from streaming text (before code blocks)
5. Fallback to "Edit code" if nothing found
```

### Step 3: Intent Storage and Observation

**Location**: `InlineEditSession` and `InlineEditSessionModel`

- `InlineEditSession` stores `userIntent` (original instruction)
- `InlineEditSessionModel` receives `userIntent` when updated
- When proposals are created, intent is derived using `deriveIntent()`
- Intent is combined with proposals using `combineLatest` to ensure streaming text is available

### Step 4: UI Display

**Location**: `LingCode/Views/InlineEditSessionView.swift`

Intent is displayed prominently above each diff:

- **Visual Design**:
  - Orange lightbulb icon (💡)
  - Orange-tinted background
  - Medium-weight subheadline font
  - Positioned at the top of each `EditProposalCard`

- **Layout**:
  ```
  [💡 Intent description]
  [File header with stats]
  [Diff preview]
  ```

## Example

**User Instruction**: "Add error handling to the calculate function"

**Derived Intent**: "Add error handling to the calculate function"

**Display**:
```
💡 Add error handling to the calculate function
📄 utils.swift  +5 -2
[Diff preview...]
```

## Data Flow

```
User enters instruction
    ↓
EditorView.startInlineEditSession(instruction: "Add error handling")
    ↓
EditorCoreAdapter.startInlineEditSession(
    instruction: fullInstruction,  // Full prompt with context
    userIntent: instruction,        // Original user instruction
    files: [fileState]
)
    ↓
InlineEditSession created with userIntent stored
    ↓
AI streams response
    ↓
Proposals created → deriveIntent() called for each
    ↓
Intent displayed in UI above each diff
```

## Benefits

1. **Clear Communication**: Users immediately see what each edit is supposed to do
2. **Better Context**: Intent helps users understand why changes were made
3. **No Performance Cost**: Intent derived from existing data, no new AI calls
4. **UX Improvement**: Makes the diff preview more informative and user-friendly

## Technical Details

- **No EditorCore Changes**: All changes are in the adapter layer
- **Reuses Existing Data**: Intent derived from instruction and streaming text
- **Reactive Updates**: Intent updates as streaming text changes (via Combine)
- **Fallback Safety**: Always provides some intent, never empty (falls back to "Edit code")

## Future Enhancements

- Could extract more sophisticated intent from AI's explanation
- Could show different intents for different files in multi-file edits
- Could allow users to edit/refine the intent description
