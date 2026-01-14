# EditorCore Integration Architecture Invariants

## Overview

This document defines the architectural invariants for EditorCore integration. These invariants must be maintained to ensure clean separation between EditorCore (pure logic) and the SwiftUI editor (UI layer).

## Core Invariants

### INVARIANT 1: Single Integration Point

**Rule**: `EditorCoreAdapter` is the ONLY bridge between EditorCore and the editor.

**Enforcement**:
- Only `EditorCoreAdapter` should import `EditorCore`
- All EditorCore interactions must go through `EditorCoreAdapter`
- No other class should directly use EditorCore types

**Current Status**: ⚠️ **PARTIALLY VIOLATED**
- `EditorView.swift` imports EditorCore and uses `EditSessionHandle`, `FileState`
- `InlineEditSessionView.swift` imports EditorCore and uses `EditSessionModel`, `EditProposal`

**Fix Required**: Refactor views to use adapter-provided wrapper types instead of EditorCore types directly.

---

### INVARIANT 2: No EditorCore Types in Views

**Rule**: SwiftUI views must NOT import EditorCore or use EditorCore types directly.

**Enforcement**:
- Views should only receive data through `EditorCoreAdapter`'s public interface
- EditorCore types should be wrapped in adapter-provided types
- Views should not know about EditorCore internals

**Current Status**: ❌ **VIOLATED**
- `EditorView.swift` imports EditorCore
- `InlineEditSessionView.swift` imports EditorCore and uses `EditSessionModel`, `EditProposal`

**Fix Required**: Create wrapper types in `EditorCoreAdapter` for views to use.

---

### INVARIANT 3: Single Mutation Point

**Rule**: `EditorViewModel.applyEdits()` is the ONLY function that mutates editor content from EditorCore.

**Enforcement**:
- No other code path should modify editor state based on EditorCore output
- All edits must go through `applyEdits()`
- `applyEdits()` must be called only after `acceptAll()`

**Current Status**: ✅ **SATISFIED**
- Only `EditorView.acceptEdits()` calls `viewModel.applyEdits()`
- No other code path mutates editor from EditorCore

---

### INVARIANT 4: Transaction Safety

**Rule**: All edits are transactional and reversible. Editor content is never mutated during streaming or preview.

**Enforcement**:
- During streaming: Only `EditSessionModel.streamingText` is updated
- During preview: Only `EditSessionModel.proposedEdits` is observed (no mutation)
- After accept: Only `applyEdits()` mutates editor content
- After reject: No editor mutation occurs

**Current Status**: ✅ **SATISFIED**
- Editor content is never modified during streaming or preview
- Edits are only applied after explicit user acceptance

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                         │
│  (EditorView, InlineEditSessionView)                     │
│  ⚠️ Currently imports EditorCore (should not)            │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ Uses EditorCoreAdapter
                     │ (should not use EditorCore types)
                     ▼
┌─────────────────────────────────────────────────────────┐
│              EditorCoreAdapter                          │
│  ✅ SINGLE BRIDGE - Only class that imports EditorCore  │
│  - Manages EditSessionCoordinator                       │
│  - Provides applyEdits() adapter function               │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ Uses EditorCore public API
                     │ (EditSessionCoordinator, EditSessionHandle, etc.)
                     ▼
┌─────────────────────────────────────────────────────────┐
│                    EditorCore                            │
│  (AIEditSession, StreamParser, DiffEngine, etc.)        │
│  Pure logic - no UI, no file system, no editor mutation │
└─────────────────────────────────────────────────────────┘
```

## Known Violations

### Violation 1: EditorView imports EditorCore

**Location**: `LingCode/Views/EditorView.swift`

**Issue**: Directly uses `EditSessionHandle` and `FileState` from EditorCore

**Impact**: Medium - violates separation of concerns

**Fix**: Create wrapper types in `EditorCoreAdapter`:
```swift
// In EditorCoreAdapter
struct EditSessionWrapper {
    let model: EditSessionModel  // Expose only what views need
    func accept() -> [EditToApply]
    func reject()
    // ... other needed methods
}
```

### Violation 2: InlineEditSessionView imports EditorCore

**Location**: `LingCode/Views/InlineEditSessionView.swift`

**Issue**: Directly uses `EditSessionModel` and `EditProposal` from EditorCore

**Impact**: Medium - violates separation of concerns

**Fix**: Same as Violation 1 - use adapter-provided wrapper types

## Assertions

The following assertions are added to enforce invariants:

1. **EditorCoreAdapter.startInlineEditSession()**: Asserts MainActor
2. **EditorViewModel.applyEdits()**: Asserts MainActor and validates edits

## Future Refactoring

To fully satisfy all invariants:

1. Create wrapper types in `EditorCoreAdapter`:
   - `EditSessionWrapper` (wraps `EditSessionHandle`)
   - `EditProposalWrapper` (wraps `EditProposal`)
   - `EditSessionModelWrapper` (wraps `EditSessionModel`)

2. Remove EditorCore imports from views

3. Update views to use wrapper types

4. Add compile-time checks (if possible) to prevent EditorCore imports in Views directory
