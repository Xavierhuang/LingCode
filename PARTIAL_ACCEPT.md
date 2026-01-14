# Partial Accept - Stage 6 Implementation

## Overview

Added per-proposal selection support for inline edits, allowing users to selectively accept or reject individual proposals while maintaining atomic application guarantees.

## Implementation

### Step 1: Selection State Management

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditSessionModel`

Added selection state management:
- `@Published var proposalSelection: [UUID: Bool]` - Maps proposal IDs to selection state
- Defaults to `true` (selected) when new proposals are added
- Preserves selection state when proposals are updated

**Methods**:
- `isSelected(proposalId:)` - Check if a proposal is selected (defaults to true)
- `toggleSelection(proposalId:)` - Toggle selection for a proposal
- `selectAll()` - Select all proposals
- `deselectAll()` - Deselect all proposals
- `selectedProposalIds` - Get set of selected proposal IDs

### Step 2: Partial Accept Support

**Location**: `LingCode/Services/EditorCoreAdapter.swift` - `InlineEditSession`

Added `acceptSelected(selectedIds:)` method:
```swift
func acceptSelected(selectedIds: Set<UUID>) -> [InlineEditToApply] {
    // If all are selected, use acceptAll for simplicity
    if selectedIds == allIds {
        return acceptAll()
    }
    
    // Otherwise, accept only selected proposals
    // EditorCore ensures atomic application via transaction system
    return coreHandle.accept(editIds: selectedIds).map { InlineEditToApply(from: $0) }
}
```

**Key Points**:
- Uses EditorCore's existing `accept(editIds:)` API
- All selected proposals are applied atomically in one transaction
- Maintains undo/redo guarantees

### Step 3: UI Selection Controls

**Location**: `LingCode/Views/InlineEditSessionView.swift`

**EditProposalCard**:
- Added checkbox button (square/checkmark.square.fill)
- Shows selection state visually
- Toggle on click

**Action Bar**:
- "Select All" / "Deselect All" buttons
- Selection count display ("X of Y selected")
- Accept button shows count when partial: "Accept 2" vs "Accept All"
- Accept button disabled when no proposals selected

### Step 4: Accept Logic Update

**Location**: `LingCode/Views/EditorView.swift` - `acceptEdits(from:)`

Updated to use partial accept:
```swift
private func acceptEdits(from session: InlineEditSession) {
    let selectedIds = session.model.selectedProposalIds
    
    guard !selectedIds.isEmpty else {
        return // No proposals selected
    }
    
    // Accept only selected proposals (atomic via EditorCore transaction)
    let editsToApply = session.acceptSelected(selectedIds: selectedIds)
    
    viewModel.applyEdits(editsToApply)
    cancelEditSession()
}
```

## How Selection is Preserved

### 1. **Default Selection**
- New proposals default to `true` (selected)
- Set when proposals are first created from EditorCore

### 2. **State Preservation**
- Selection state stored in `proposalSelection: [UUID: Bool]` dictionary
- When proposals update (e.g., during streaming), existing selection is preserved
- Only new proposals get default selection

### 3. **Cleanup**
- Selection state removed for proposals that no longer exist
- Prevents memory leaks and stale state

### 4. **Observation Pattern**
```swift
coreModel.$proposedEdits
    .combineLatest(coreModel.$streamingText)
    .sink { [weak self] proposals, streamingText in
        // Create new proposals with intent
        let newProposals = ...
        
        // Preserve selection for existing proposals
        for proposal in newProposals {
            if self.proposalSelection[proposal.id] == nil {
                self.proposalSelection[proposal.id] = true // Default
            }
        }
        
        // Remove stale selections
        self.proposalSelection = self.proposalSelection.filter { newIds.contains($0.key) }
        
        self.proposedEdits = newProposals
    }
```

## How Selection is Applied Safely

### 1. **Atomic Application**

**EditorCore Guarantee**:
- `accept(editIds:)` creates a single transaction containing all selected proposals
- Transaction is applied atomically (all-or-nothing)
- If any proposal fails, entire transaction is rolled back

**Flow**:
```
User selects proposals → acceptSelected(selectedIds) 
    → coreHandle.accept(editIds: selectedIds)
    → AIEditSession.accept(editIds:)
    → prepareTransaction(editIds:) [creates single transaction]
    → commitTransaction() [applies atomically]
    → Returns EditToApply[] for all selected proposals
```

### 2. **Undo Guarantees**

**Transaction History**:
- Each `accept()` call creates one transaction
- Transaction contains snapshot of affected files before changes
- `undo()` restores all files in the transaction atomically

**Example**:
```
User accepts 3 selected proposals:
  → Transaction created with all 3 edits
  → All 3 applied atomically
  → Undo restores all 3 atomically
```

### 3. **Reject Behavior**

**Reject All**:
- Discards all proposals (selected or not)
- No changes applied to editor
- Session closed

**Reject Selected** (not implemented):
- Could be added in future
- Would use `reject(editIds:)` from EditorCore

### 4. **State Validation**

**Before Accept**:
- Checks `selectedIds.isEmpty` - prevents accepting nothing
- Validates proposals exist in session
- EditorCore validates state internally

**After Accept**:
- All selected proposals applied
- Transaction committed
- Session closed
- Undo available for entire transaction

## Safety Guarantees

### ✅ Atomic Application
- All selected proposals applied in one transaction
- No partial application possible
- EditorCore enforces this at the core level

### ✅ Undo Safety
- Entire transaction can be undone
- All files restored to pre-transaction state
- No orphaned changes

### ✅ State Consistency
- Selection state preserved across proposal updates
- No stale selections
- Cleanup on proposal removal

### ✅ No EditorCore Changes
- Uses existing `accept(editIds:)` API
- No modifications to EditorCore
- All logic in adapter layer

## Example Flow

1. **User requests edit**: "Add error handling to calculate function"
2. **AI generates 3 proposals**:
   - Proposal 1: `utils.swift` (selected ✓)
   - Proposal 2: `helpers.swift` (selected ✓)
   - Proposal 3: `tests.swift` (deselected ✗)
3. **User toggles selection**: Deselects Proposal 2
4. **User clicks "Accept 1"**:
   - Only Proposal 1 is accepted
   - Single transaction created with Proposal 1
   - Applied atomically to `utils.swift`
   - Undo available for entire transaction
5. **Result**: Only `utils.swift` is modified

## Benefits

1. **User Control**: Users can selectively apply edits
2. **Atomic Safety**: All selected edits applied together
3. **Undo Support**: Entire transaction can be undone
4. **No Breaking Changes**: Existing accept all still works
5. **Clean Architecture**: All logic in adapter, no EditorCore changes
