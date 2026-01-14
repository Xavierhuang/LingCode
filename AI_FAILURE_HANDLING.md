# AI Failure Handling and Completion State Correctness

## Core Invariant

**The IDE must NEVER show "Response Complete" unless ALL of the following are true:**
1. The AI request succeeded (HTTP 2xx)
2. The response body is non-empty
3. Parsed output contains at least one valid edit, proposal, or execution plan
4. At least one change was applied OR explicitly proposed

## Implementation

### 1. Network Failure Handling

**Location**: `LingCode/Services/AIService.swift` - `StreamingDelegate.urlSession(_:dataTask:didReceive:completionHandler:)`

- **Non-2xx responses** (including 429, 529, overloaded_error) are treated as **HARD FAILURES**
- Do NOT proceed to parsing or apply phases
- Surface user-visible error: "AI service temporarily unavailable. Please retry."
- Specific error messages:
  - 429: "Rate limit exceeded"
  - 529/503: "Service overloaded"
  - Other non-2xx: "HTTP {statusCode}"

### 2. Empty Response Guard

**Location**: `LingCode/Services/AIService.swift` - `StreamingDelegate.urlSession(_:task:didCompleteWithError:)`

- If AI response text length == 0:
  - Abort pipeline immediately
  - Do NOT parse
  - Do NOT mark session complete
  - Transition session to error state with message: "AI service returned an empty response. Please retry."

### 3. Completion Gate

**Location**: `LingCode/Views/CompletionSummaryView.swift` - `hasValidCompletionState()`

- "Response Complete" is gated behind verification
- Requires at least one parsed edit or proposal
- Zero edits result in view not being shown (returns `EmptyView()`)
- Conditions checked:
  - `hasParsedOutput`: At least one parsed file/command/action
  - `hasProposedChanges`: At least one file/command with changes

### 4. Retry Semantics

**Location**: `LingCode/Views/EditorView.swift` - `retryEditSession(_:)`

- Allows retry using the same execution plan or prompt
- Do NOT reuse partial or empty AI responses
- Creates a completely new session with fresh AI request
- Preserves execution plan for deterministic retry

### 5. Telemetry / Logging

**Location**: Multiple files with `print()` statements for telemetry

Failure types are logged separately:
- **Network/model failure**: HTTP status code, error domain, error message
- **Empty response**: Response length, chunk count
- **Parse failure**: Parse error details (handled by parsing layer)
- **No-op result**: Execution outcome validation (handled by ExecutionOutcomeValidator)

Log format:
```
❌ NETWORK FAILURE: HTTP {statusCode} - {errorMessage}
❌ EMPTY RESPONSE: No chunks received or empty text
   Response length: {length}
   Has chunks: {bool}
❌ AI REQUEST FAILURE:
   Error code: {code}
   Error domain: {domain}
   Error message: {message}
   Failure category: {category}
🔄 RETRY: Restarted edit session with same execution plan
```

## Error States

### Network Failure
- **State**: `.error(message)` in `InlineEditSessionModel`
- **UI**: Error view with retry button
- **Action**: User can retry with same execution plan

### Empty Response
- **State**: `.error("AI service returned an empty response. Please retry.")`
- **UI**: Error view with retry button
- **Action**: User can retry with same execution plan

### Parse Failure
- **State**: Handled by parsing layer (may result in no proposals)
- **UI**: No "Response Complete" shown (completion gate prevents it)
- **Action**: User can retry or modify request

### No-Op Result
- **State**: `ExecutionOutcome.noOp(explanation:)`
- **UI**: "No changes were applied" message in applied view
- **Action**: User can retry or modify request

## User Experience

1. **Network failures** show clear error message with retry option
2. **Empty responses** are caught before parsing, preventing false completion
3. **Completion gate** ensures "Response Complete" only shows when valid
4. **Retry** preserves execution plan for deterministic retry
5. **Telemetry** helps diagnose issues without exposing to users

## Testing Checklist

- [ ] Non-2xx responses show error, not completion
- [ ] Empty responses show error, not completion
- [ ] Responses with no parsed edits don't show "Response Complete"
- [ ] Retry works with same execution plan
- [ ] Retry doesn't reuse old response
- [ ] Telemetry logs all failure types correctly
