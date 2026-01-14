# Execution Planning Layer - Core Invariant

## Overview

The Execution Planning layer is a language-agnostic system that translates user prompts into explicit, deterministic execution plans before any edit session is started. This ensures safe, inspectable, and predictable code modifications.

## Core Invariant

**"User prompts are always translated into explicit execution plans before edits occur."**

This invariant ensures that:
1. All edit operations are deterministic and inspectable
2. Safety guards can be applied before execution
3. Outcomes can be validated after execution
4. The UI truthfully reflects what actually happened

## Architecture

### Components

1. **ExecutionPlan** (`LingCode/Services/ExecutionPlan.swift`)
   - Structured representation of an edit operation
   - Contains: operation type, search targets, replacement content, scope, safety constraints
   - Serializable and inspectable

2. **ExecutionPlanner** (`LingCode/Services/ExecutionPlanner.swift`)
   - Translates user prompts into explicit execution plans
   - Normalizes common patterns (e.g., "change X to Y" → replace operation)
   - Language-agnostic and works for any codebase

3. **ExecutionOutcomeValidator** (`LingCode/Services/ExecutionOutcomeValidator.swift`)
   - Validates execution outcomes after edits are applied
   - Detects if changes were actually made
   - Provides safety guard estimation before execution

### Integration Points

- **EditorCoreAdapter.startInlineEditSession()**: Creates execution plan before starting edit session
- **EditorView.acceptEdits()**: Validates outcome after applying edits
- **InlineEditSessionView**: Displays appropriate UI based on execution outcome

## Key Features

### 1. Intent → Plan Translation

User prompts are normalized into structured plans:

- "change X to Y" → `replace` operation
- "rename X to Y" → `rename` operation
- "replace X with Y" → `replace` operation
- "add X" → `insert` operation
- "remove X" → `delete` operation

The planner does NOT rely on AI inference. It uses deterministic pattern matching.

### 2. Deterministic Plan Execution

EditorCore receives explicit instructions describing WHAT to change, not vague human prompts. The plan includes:
- Operation type (replace/insert/delete/rename)
- Search target(s) with matching options
- Replacement content
- Scope (entire project / current file / selected text / specific files)
- Safety constraints

### 3. Outcome Validation

After execution:
- Detects whether any changes were actually made
- If zero changes occurred:
  - Does NOT show "Response Complete"
  - Surfaces a user-visible explanation (e.g., "No matches found")

### 4. Safety Guards

Before execution:
- Estimates diff size (files, lines)
- Rejects or narrows scope automatically if too large
- Prevents syntax-breaking edits where possible

### 5. UI Truthfulness Invariant

**The IDE may only show "Complete" if at least one edit was applied.**

Otherwise, it shows:
- A failure message with explanation
- A no-op explanation if no changes were made

## Usage

### Creating an Execution Plan

```swift
let planner = ExecutionPlanner.shared
let context = ExecutionPlanner.PlanningContext(
    selectedText: selectedText,
    currentFilePath: currentFilePath,
    allFilePaths: allFilePaths,
    limitToCurrentFile: false
)
let plan = planner.createPlan(from: userPrompt, context: context)
```

### Validating Execution Outcome

```swift
let validator = ExecutionOutcomeValidator.shared
let outcome = validator.validateOutcome(
    editsToApply: editsToApply,
    filesBefore: filesBefore,
    filesAfter: filesAfter
)

if !outcome.changesApplied {
    // Show no-op explanation to user
    showMessage(outcome.noOpExplanation ?? "No changes were made")
}
```

## Constraints

- **Do NOT modify EditorCore**: All logic lives in the IDE/adapter layer
- **Do NOT add content-specific rules**: Must work for any codebase and any language
- **Do NOT hardcode file types**: Language-agnostic by design

## Benefits

1. **Deterministic**: Plans are explicit and reproducible
2. **Safe**: Safety guards prevent dangerous operations
3. **Inspectable**: Plans can be serialized and examined
4. **Truthful**: UI accurately reflects what happened
5. **Language-agnostic**: Works for any codebase and any language

## Future Enhancements

- Plan serialization for debugging
- Plan history and replay
- Plan templates for common operations
- Advanced safety guards (syntax validation, dependency analysis)
