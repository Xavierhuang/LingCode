# EditorCore Integration for ⌘K Inline Edits

## Overview

EditorCore has been integrated into the LingCode editor to replace the ⌘K / inline AI edit flow. This integration maintains strict separation between editor state and AI logic, ensuring that:

1. **No editor state mutation during streaming or preview** - Editor content is only modified after explicit user acceptance
2. **All edits are transactional and reversible** - Edits are grouped into atomic transactions with undo support
3. **acceptAll() is the only commit point** - Editor content is never mutated until the user explicitly accepts edits

## Architecture

### Integration Boundary

The integration uses a clean adapter pattern:

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Editor                       │
│  (EditorView, EditorViewModel, Document)                │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ applyEdits([EditToApply])
                     │ (ONLY mutation point)
                     ▼
┌─────────────────────────────────────────────────────────┐
│              EditorCoreAdapter                          │
│  - Manages EditSessionCoordinator                       │
│  - Provides applyEdits() adapter function              │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ EditSessionHandle
                     │ EditSessionModel (observable)
                     ▼
┌─────────────────────────────────────────────────────────┐
│                    EditorCore                            │
│  (AIEditSession, StreamParser, DiffEngine, etc.)        │
└─────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. EditorCoreAdapter (`LingCode/Services/EditorCoreAdapter.swift`)

- **Purpose**: Manages `EditSessionCoordinator` lifecycle
- **Responsibilities**:
  - Create and manage edit sessions
  - Provide `applyEdits()` adapter function on `EditorViewModel`
  - Bridge between editor and EditorCore

#### 2. applyEdits() Function (`EditorViewModel.applyEdits()`)

- **Location**: `EditorCoreAdapter.swift` (extension on `EditorViewModel`)
- **Purpose**: The ONLY function that mutates editor content from EditorCore
- **Behavior**:
  - Applies edits atomically to documents
  - Preserves cursor/scroll position
  - Does NOT trigger additional AI logic
  - Marks documents as AI-generated for highlighting

#### 3. InlineEditSessionView (`LingCode/Views/InlineEditSessionView.swift`)

- **Purpose**: UI component that observes `EditSessionModel` and shows diff preview
- **Features**:
  - Shows streaming text during generation
  - Displays diff preview when ready (without mutating editor)
  - Provides Accept/Reject/Cancel buttons
  - Shows status indicators (streaming, ready, applied, rejected, error)

#### 4. EditorView Integration (`LingCode/Views/EditorView.swift`)

- **Changes**: Replaced `applyInlineEdit()` with EditorCore flow
- **Flow**:
  1. User presses ⌘K → Shows instruction input
  2. User enters instruction → Starts EditorCore session
  3. AI streams response → EditorCore parses into proposed edits
  4. UI shows diff preview (no editor mutation)
  5. User accepts → `applyEdits()` is called → Editor content updated
  6. User rejects → Session rejected, no editor mutation

## State Isolation

### Editor State Isolation

The editor state (`EditorState`, `Document`) is completely isolated from AI logic:

1. **During Streaming**: Editor content is never modified. Only `EditSessionModel.streamingText` is updated.

2. **During Preview**: Editor content is never modified. Only `EditSessionModel.proposedEdits` is observed for display.

3. **After Accept**: Only `applyEdits()` mutates editor content. This function:
   - Is called synchronously after `acceptAll()`
   - Applies all edits atomically
   - Does not trigger any AI logic
   - Preserves cursor/scroll position

4. **After Reject**: Editor content is never modified. Session is simply rejected.

### Transaction Safety

All edits go through EditorCore's transaction system:

- **Proposed Edits**: Parsed from AI stream, validated, but not applied
- **Transaction Ready**: Edits are grouped into a transaction, validated
- **Committed**: Only after `acceptAll()`, edits are committed and returned as `EditToApply`
- **Reversible**: Undo support via `session.undo()` (returns `EditToApply` to restore original)

## Usage Flow

### ⌘K Inline Edit Flow

```
1. User presses ⌘K
   └─> EditorView shows InlineEditOverlay (instruction input)

2. User enters instruction and submits
   └─> EditorView.startInlineEditSession()
       └─> EditorCoreAdapter.startInlineEditSession()
           └─> EditSessionCoordinator.startEditSession()
               └─> Creates EditSessionHandle with EditSessionModel

3. AI streams response
   └─> EditorView.streamAIResponse()
       └─> AIService.streamMessage()
           └─> session.appendStreamingText(chunk)
               └─> EditSessionModel.streamingText updated (UI observes)

4. AI completes
   └─> session.completeStreaming()
       └─> EditorCore parses edits
           └─> EditSessionModel.proposedEdits updated (UI observes)
           └─> EditSessionModel.status = .ready

5. UI shows diff preview
   └─> InlineEditSessionView observes EditSessionModel
       └─> Shows EditProposalCard for each proposed edit
       └─> NO editor mutation

6a. User accepts
    └─> EditorView.acceptEdits()
        └─> session.acceptAll()
            └─> Returns [EditToApply]
        └─> viewModel.applyEdits(editsToApply)
            └─> Editor content updated atomically
            └─> Documents marked as AI-generated

6b. User rejects
    └─> EditorView.rejectEdits()
        └─> session.rejectAll()
            └─> EditSessionModel.status = .rejected
            └─> NO editor mutation
```

## Key Invariants

1. **Editor content is never mutated during streaming or preview**
   - Only `EditSessionModel` is updated
   - Editor observes model for display only

2. **acceptAll() is the only commit point**
   - `applyEdits()` is only called after `acceptAll()`
   - No other code path mutates editor from EditorCore

3. **All edits are transactional**
   - Edits are grouped into transactions
   - Transactions are validated before commit
   - Undo support via transaction history

4. **Editor state is isolated from AI logic**
   - Editor does not know about AI internals
   - Editor only knows about `EditToApply` (final result)
   - EditorCore does not know about editor internals

## Files Modified

1. **LingCode/Services/EditorCoreAdapter.swift** (NEW)
   - Adapter layer for EditorCore integration
   - `applyEdits()` function

2. **LingCode/Views/InlineEditSessionView.swift** (NEW)
   - UI component for edit session
   - Observes `EditSessionModel` and shows diff preview

3. **LingCode/Views/EditorView.swift** (MODIFIED)
   - Replaced `applyInlineEdit()` with EditorCore flow
   - Added `startInlineEditSession()`, `acceptEdits()`, `rejectEdits()`

## Testing

The integration maintains all EditorCore invariants:

- ✅ No editor mutation during streaming
- ✅ No editor mutation during preview
- ✅ Edits only applied after acceptAll()
- ✅ Transaction safety
- ✅ Undo support
- ✅ State isolation

## Future Enhancements

- Add undo/redo UI integration
- Add partial accept/reject (accept specific edits)
- Add diff view improvements
- Add keyboard shortcuts for accept/reject
