# Completion Gate Hardening

This document describes the hardening of the Swift-based AI IDE against silent failures and unsafe completions.

## Changes Made (Adapter/Coordinator Layer Only)

### 1. Hard Completion Gate

**Requirement**: Session may only complete if:
- HTTP 2xx AND responseLength > 0 AND parsedFiles.count > 0 AND proposedEdits.count > 0

**Implementation**:
- Created `SessionCompletionValidator` to enforce the completion gate
- Integrated into `InlineEditSession.completeStreaming()` to validate before allowing completion
- Enhanced `EditSafetyCoordinator.checkCompletionGate()` to check all conditions
- Updated `EditIntentCoordinator.parseAndValidate()` to use the validator

**Files**:
- `LingCode/Services/SessionCompletionValidator.swift` (NEW)
- `LingCode/Services/EditSafetyCoordinator.swift` (ENHANCED)
- `LingCode/Services/EditIntentCoordinator.swift` (ENHANCED)
- `LingCode/Services/EditorCoreAdapter.swift` (ENHANCED)

**Behavior**:
- If any condition fails, session transitions to `.error` state
- Error message explains which condition failed
- Session cannot complete until all conditions are met

### 2. Zero Files Parsing Abort

**Requirement**: Abort and show error if parsing produces zero files

**Implementation**:
- Already implemented in `EditIntentCoordinator.parseAndValidate()`
- Step 3 validates parsed results and aborts if `parsedFiles.isEmpty && parsedCommands.isEmpty`
- Returns `EditResult` with `isValid: false` and error message
- Pipeline does NOT proceed to apply stage

**Files**:
- `LingCode/Services/EditIntentCoordinator.swift` (lines 115-135)

**Behavior**:
- If parsing yields zero files, returns error: "No files or commands were parsed from the AI response. The response may be incomplete or in an unexpected format."
- Session does NOT complete
- User sees error state with retry option

### 3. Scope Validator for Rename/Text Change

**Requirement**: If intent is rename/text change and diff removes large portion, block or warn

**Implementation**:
- Already implemented in `EditSafetyCoordinator.validateEditScope()`
- For `.textReplacement` and `.symbolRename` intents:
  - Blocks if >50 lines deleted OR >30% of file deleted
  - Returns error: "Change exceeds requested scope. Text replacement should not delete large portions of code."
- For `.scopedEdit` (default):
  - Blocks if >200 lines deleted OR >20% of file deleted
- For `.fullFileRewrite`:
  - Allows all changes

**Files**:
- `LingCode/Services/EditSafetyCoordinator.swift` (lines 66-100)
- `LingCode/Services/EditIntentCoordinator.swift` (lines 160-172)

**Behavior**:
- Scope validation runs before any edit is applied
- Unsafe edits are rejected and not added to `validatedFiles`
- Error messages explain the scope violation
- User sees which files were blocked and why

### 4. No @Published State Mutations During View Updates

**Requirement**: Ensure no @Published state is mutated during SwiftUI view updates

**Implementation**:
- All state mutations happen in coordinator/adapter layer
- `EditIntentCoordinator` dispatches state updates asynchronously on MainActor AFTER view updates
- `StreamingUpdateCoordinator` throttles updates and dispatches on MainActor
- View mutations in `EditorView` are in async callbacks (onComplete, onError), not during view body evaluation

**Files**:
- `LingCode/Services/EditIntentCoordinator.swift` (lines 204-208)
- `LingCode/Services/StreamingUpdateCoordinator.swift` (all state updates)
- `LingCode/Views/EditorView.swift` (mutations only in async callbacks)

**Behavior**:
- State updates are scheduled asynchronously
- No mutations occur during SwiftUI view body evaluation
- All @Published properties are updated via coordinator/adapter layer

## Architecture

### Completion Gate Flow

1. **AI Response Received** → `AIService` validates HTTP status
2. **Content Parsed** → `EditIntentCoordinator.parseAndValidate()` checks:
   - Empty response guard
   - Parsed files count > 0
   - Scope validation for each file
3. **Proposals Generated** → `EditorCoreAdapter` creates proposals
4. **Completion Requested** → `InlineEditSession.completeStreaming()` validates:
   - HTTP 2xx
   - responseLength > 0
   - parsedFiles.count > 0
   - proposedEdits.count > 0
   - validationErrors.isEmpty
5. **Gate Passes** → Session completes
6. **Gate Fails** → Session transitions to `.error` state

### Safety Layers

1. **Pre-Parse**: Empty response guard, HTTP status check
2. **Post-Parse**: Zero files check, scope validation
3. **Pre-Complete**: Completion gate validation
4. **Pre-Apply**: Final validation before applying edits

## Constraints Met

✅ **Adapter/Coordinator Layer Only**: All changes in `LingCode/Services/`
✅ **No EditorCore Modifications**: No changes to EditorCore module
✅ **No UI Layout Changes**: No changes to view layouts
✅ **Minimal Changes**: Only added necessary validators and enhanced existing coordinators
✅ **Production-Safe**: All changes are defensive and fail-safe
✅ **Language-Agnostic**: Works for any codebase and any language

## Testing Scenarios

### Scenario 1: HTTP 200 with Empty Response
- **Expected**: Completion gate fails, session → `.error`
- **Message**: "AI service returned an empty response. Session cannot complete."

### Scenario 2: HTTP 200 with Zero Parsed Files
- **Expected**: Completion gate fails, session → `.error`
- **Message**: "No files were parsed from the AI response. Session cannot complete."

### Scenario 3: HTTP 200 with Zero Proposed Edits
- **Expected**: Completion gate fails, session → `.error`
- **Message**: "No edits were proposed. Session cannot complete."

### Scenario 4: Rename Intent with Large Deletion
- **Expected**: Scope validation fails, edit rejected
- **Message**: "Change exceeds requested scope. Text replacement should not delete large portions of code."

### Scenario 5: All Conditions Met
- **Expected**: Completion gate passes, session completes normally
