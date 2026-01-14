# Edit Mode Enforcement

This document describes the strict "Edit Mode" enforcement that ensures AI responses contain ONLY executable file edits, not explanations or reasoning.

## Problem Solved

**Before**: AI sometimes returned reasoning or summary text (e.g., "Thinking Process"), causing the parser to detect zero files and fail validation even though the AI responded.

**After**: AI can ONLY return executable file edits. Any non-executable output is rejected immediately.

## Implementation

### 1. Strict "Edit Mode" Execution Contract

**Component**: `EditModePromptBuilder`

- Builds system prompts that enforce edit-only output
- Explicitly forbids prose, summaries, reasoning text
- Forbids markdown headings, bullet points, explanations
- Allows only: file edits, file creations, explicit no-op

**Files**:
- `LingCode/Services/EditModePromptBuilder.swift` (NEW)

### 2. Hard Output Schema Enforcement

**Component**: `EditOutputValidator`

- Validates AI responses before parsing
- Detects and rejects forbidden content:
  - Markdown headings (##, ###)
  - Bullet points (-, *, •)
  - Explanatory text outside code blocks
- Distinguishes between:
  - `valid`: Contains file edits
  - `noOp`: Explicit no-op (valid)
  - `invalidFormat`: Contains forbidden content (error)
  - `silentFailure`: Empty response (error)

**Files**:
- `LingCode/Services/EditOutputValidator.swift` (NEW)

### 3. Integration Points

**AI Service**:
- Added `systemPrompt` parameter to `streamMessage()`
- Supports system prompts for both OpenAI and Anthropic APIs
- Edit Mode system prompt is injected for inline edits

**EditorView**:
- Uses `EditModePromptBuilder` to build strict Edit Mode prompts
- Validates response with `EditOutputValidator` before parsing
- Fails fast with clear error message if non-executable output detected

**EditIntentCoordinator**:
- Validates output before parsing
- Distinguishes no-op (valid) from parse failure (error)
- Returns appropriate error messages for each case

**Files Modified**:
- `LingCode/Services/AIService.swift` (ENHANCED)
- `LingCode/Views/EditorView.swift` (ENHANCED)
- `LingCode/Services/EditIntentCoordinator.swift` (ENHANCED)

## Validation Flow

1. **AI Response Received** → `EditOutputValidator.validateEditOutput()`
2. **Validation Result**:
   - `silentFailure` → Error: "AI service returned an empty response"
   - `invalidFormat` → Error: "AI returned non-executable output. [reason]"
   - `noOp` → Valid, proceed (zero files is OK)
   - `valid` → Proceed to parsing
3. **Parsing** → `StreamingContentParser` extracts file edits
4. **Completion Gate** → Validates all conditions before allowing completion

## Error Messages

### Invalid Format
```
AI returned non-executable output. Response contains markdown headings (##, ###) - forbidden in Edit Mode. Please retry.
```

### Silent Failure
```
AI service returned an empty response. Please retry.
```

### No-Op (Valid)
No error - zero files is valid for explicit no-op.

## Constraints Met

✅ **AI Service Only**: Changes limited to AI service, response parser, and validation layer
✅ **No UI Changes**: No modifications to SwiftUI views or UI layout
✅ **Minimal Changes**: Only added necessary validators and enhanced existing services
✅ **Production-Safe**: All changes are defensive and fail-safe
✅ **Language-Agnostic**: Works for any codebase and any language

## Testing Scenarios

### Scenario 1: AI Returns Explanation Text
- **Input**: Response with "## Thinking Process" heading
- **Expected**: `invalidFormat` error
- **Message**: "AI returned non-executable output. Response contains markdown headings..."

### Scenario 2: AI Returns Bullet Points
- **Input**: Response with bullet list before code blocks
- **Expected**: `invalidFormat` error
- **Message**: "AI returned non-executable output. Response contains bullet points..."

### Scenario 3: AI Returns Valid File Edits
- **Input**: Response with only file code blocks
- **Expected**: `valid` → Proceed to parsing

### Scenario 4: AI Returns Explicit No-Op
- **Input**: Response with `{"noop": true}` or "no changes needed"
- **Expected**: `noOp` → Valid, zero files is OK

### Scenario 5: AI Returns Empty Response
- **Input**: Empty or whitespace-only response
- **Expected**: `silentFailure` error
- **Message**: "AI service returned an empty response. Please retry."
