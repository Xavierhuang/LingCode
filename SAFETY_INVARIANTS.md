# System-Level Safety Invariants

This document describes the safety invariants implemented to ensure AI-generated code edits are applied safely and correctly.

## Core Safety Invariants

### 1. Execution Intent Classification

**Invariant**: Default intent is `scopedEdit`. Full-file rewrites are ONLY allowed if user explicitly requests rewrite/refactor/regenerate.

**Implementation**:
- `IntentClassifier` classifies user prompts into intent types:
  - `.textReplacement` - Simple string replacements (blocks full-file rewrites)
  - `.symbolRename` - Symbol renames (blocks full-file rewrites)
  - `.scopedEdit` - Bounded scoped edits (DEFAULT)
  - `.fullFileRewrite` - Full-file rewrite (explicit only)

**Rules**:
- If user request does NOT explicitly ask for rewrite/refactor/regenerate, full-file output is rejected
- Large diffs are illegal unless intent == fullFileRewrite

**Files**:
- `LingCode/Services/IntentClassifier.swift`
- `LingCode/Services/EditSafetyCoordinator.swift`

### 2. Hard Completion Gate

**Invariant**: The IDE must NOT show "Response Complete" unless ALL are true:
1. HTTP status is 2xx
2. Response body is non-empty
3. At least one parsed edit exists
4. Each edit passes scope validation
5. No safety rule was violated

**Otherwise**:
- Transition session to `.error`
- Show a user-visible error message
- Do NOT parse or apply

**Implementation**:
- `EditSafetyCoordinator.checkCompletionGate()` validates all conditions
- `EditIntentCoordinator.parseAndValidate()` enforces the gate
- `CompletionSummaryView` only renders when gate passes

**Files**:
- `LingCode/Services/EditSafetyCoordinator.swift`
- `LingCode/Services/EditIntentCoordinator.swift`
- `LingCode/Views/CompletionSummaryView.swift`

### 3. Diff Safety Validator

**Invariant**: Before apply, validate that:
- If >20% of file OR >200 lines deleted AND intent != fullFileRewrite → abort
- Surface error: "Change exceeds requested scope"

**Implementation**:
- `EditSafetyCoordinator.validateEditScope()` checks line counts and percentages
- `DiffSafetyGuard.validateEdit()` performs additional safety checks
- Both validators run before any edit is applied

**Files**:
- `LingCode/Services/EditSafetyCoordinator.swift`
- `LingCode/Services/DiffSafetyGuard.swift`

### 4. State Mutation Outside Views

**Invariant**: SwiftUI state is never mutated during view updates.

**Implementation**:
- All parsing, validation, and state updates happen in `EditIntentCoordinator`
- State updates are dispatched asynchronously on MainActor AFTER view updates
- Views only observe state via `@Published` properties

**Files**:
- `LingCode/Services/EditIntentCoordinator.swift`
- `LingCode/Services/StreamingUpdateCoordinator.swift`
- `LingCode/Views/CursorStreamingView.swift`

### 5. Network Failure & Empty Response Handling

**Invariant**: If AI request returns non-2xx OR empty content, abort immediately.

**Implementation**:
- `AIService.StreamingDelegate` checks HTTP status codes in `didReceive response`
- Non-2xx responses trigger `onError` immediately (do not proceed to parsing)
- Empty responses are detected and trigger `onError` (do not proceed to parsing)
- `EditIntentCoordinator.parseAndValidate()` has empty response guard

**Files**:
- `LingCode/Services/AIService.swift`
- `LingCode/Services/EditIntentCoordinator.swift`
- `LingCode/Views/EditorView.swift`

### 6. Structured Completion Summary

**Invariant**: When successful, show:
- Files changed
- Lines added/removed per file
- Edit type (rename, scoped edit, etc.)
- Confirmation that scope rules passed

**Implementation**:
- `CompletionSummaryBuilder` generates deterministic summaries
- `CompletionSummaryView` displays the summary
- Summary only appears when completion gate passes

**Files**:
- `LingCode/Services/CompletionSummaryBuilder.swift`
- `LingCode/Views/CompletionSummaryView.swift`

## Architecture Notes

### Coordinator Pattern

All AI parsing, validation, and state updates are coordinated through:
1. `EditIntentCoordinator` - Central coordinator for parsing and validation
2. `EditSafetyCoordinator` - System-level safety checks
3. `StreamingUpdateCoordinator` - Throttles streaming updates

### Safety Layers

1. **Pre-AI**: Intent classification determines allowed edit scope
2. **During Parsing**: Empty response guard, HTTP status check
3. **Post-Parsing**: Scope validation, diff safety checks
4. **Pre-Apply**: Completion gate validation
5. **Post-Apply**: Outcome validation

### Error Handling

- Network failures (non-2xx) → Immediate abort, show retry option
- Empty responses → Immediate abort, show retry option
- Parse failures (0 files) → Abort pipeline, show error state
- Scope violations → Reject unsafe edits, show error message
- Completion gate failures → Do not show "Response Complete"

## Constraints

- Do NOT modify EditorCore
- Prefer adapter/coordinator layers
- Preserve existing behavior where safe
- Minimal diffs, no rewrites unless necessary
- Production-ready Swift code only
- Works for ANY codebase and ANY language
