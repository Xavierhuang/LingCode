# EditorCore Security Audit Findings

## Summary
Audit of public API surface (`EditSessionCoordinator`, `EditSessionHandle`, `EditSessionModel`, `EditProposal`, `EditToApply`) for potential bypasses, invalid state transitions, and missing guards.

## Findings

### ✅ Already Safe
- **Access Control**: `EditSessionHandleImpl` is `@MainActor class` (not `public`), preventing direct access to internals
- **Transaction System**: All accept/reject operations go through `AIEditSession` which enforces transaction boundaries
- **State Transitions**: `AIEditSession.transition()` validates all state transitions via `isValidTransition()`
- **Internal Methods**: `getTransactionHistory()` is `internal`, preventing external access

### ⚠️ Issues Found

#### Issue 1: Missing State Validation in EditSessionHandleImpl
**Location**: `EditSessionCoordinatorImpl.swift:98-121`

**Problem**: Methods `acceptAll()`, `accept()`, `rejectAll()`, `reject()`, and `undo()` don't validate state before calling internal methods. While `AIEditSession` guards silently fail, the wrapper should validate to prevent invalid operations.

**Risk**: UI can call operations in invalid states (e.g., `acceptAll()` during streaming), leading to silent failures and user confusion.

**Suggested Fix**:
```swift
func acceptAll() -> [EditToApply] {
    // Add state validation
    guard model.status == .ready else {
        return [] // Or throw/log error
    }
    guard let snapshot = internalSession.acceptAll() else {
        return []
    }
    return extractEditsToApply(from: snapshot)
}
```

**Compile-time Protection**: Add `@MainActor` assertion or precondition to ensure state is checked.

---

#### Issue 2: Undo Allowed in Invalid States
**Location**: `EditSessionCoordinatorImpl.swift:123-149`

**Problem**: `undo()` doesn't check if session is in a valid state. Should only work when `.applied` or `.committed`.

**Risk**: Undo can be called during streaming/parsing, returning `nil` without clear indication of why.

**Suggested Fix**:
```swift
func undo() -> [EditToApply]? {
    // Validate state - undo only works after apply
    guard model.status == .applied else {
        return nil
    }
    // ... rest of implementation
}
```

**Compile-time Protection**: Use enum case matching to ensure state is `.applied` before proceeding.

---

#### Issue 3: Silent Failures on Invalid Accept/Reject
**Location**: `EditSessionCoordinatorImpl.swift:98-121`

**Problem**: When `acceptAll()` or `accept()` is called during `.streaming` or `.parsing`, it returns empty array without indicating failure.

**Risk**: UI cannot distinguish between "no edits" and "operation failed due to invalid state".

**Suggested Fix**:
```swift
func acceptAll() -> [EditToApply] {
    guard model.status == .ready else {
        // Log or set error state
        model.errorMessage = "Cannot accept edits: session not ready"
        return []
    }
    // ... rest of implementation
}
```

**Alternative**: Return `Result<[EditToApply], EditSessionError>` instead of empty array, but this would change the public API.

---

## Recommended Actions

1. **Add state validation guards** to all `EditSessionHandleImpl` methods (Issue 1)
2. **Add state check to `undo()`** to only allow when `.applied` (Issue 2)
3. **Improve error reporting** for invalid operations (Issue 3) - consider adding `errorMessage` to model or using Result type

## Notes

- All issues are **defensive improvements** - the current implementation is functionally correct but lacks user feedback
- No security vulnerabilities found - all operations are properly guarded internally
- No architecture changes needed - these are minimal additions to existing methods
