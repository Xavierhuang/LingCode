# 🔧 Critical Fix: AI Must Send Complete Files

## Problem

After implementing the "incremental changes" feature where AI was instructed to show only changed sections, **the AI started deleting code** because:

1. System prompts told AI: "Show ONLY the changed sections"
2. AI correctly followed instructions and sent snippets
3. File handling code did: `file.content.write(to: fileURL)` (replaces entire file)
4. **Result**: Original code got deleted, only the snippet remained

**User reported**: "why it just remove my code entirely now?"

---

## Root Cause

The mismatch between:
- **What we told the AI**: "Output only changed sections for brevity"
- **What the code does**: Replaces entire file with whatever AI sends

### The Conflict

```swift
// File handling (CursorStreamingView.swift:845)
try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
// ☝️ This REPLACES the entire file

// System prompt said:
"Show ONLY the changed sections with surrounding context"
// ☝️ AI sends only the changed function

// Result: Original file DELETED, replaced with just the snippet!
```

---

## Solution

**Reverted system prompts to ALWAYS require complete files.**

### Updated Prompts

#### Default System Prompt

**Before** (Lines 420-452):
```
INCREMENTAL CHANGES (VERY IMPORTANT):
When making small modifications to existing code:
1. **Show ONLY the changed sections with surrounding context**
2. Use clear markers to indicate what changed
3. NEVER rewrite entire files for small changes
```

**After** (Lines 420-457):
```
CRITICAL FILE OUTPUT RULE:
**ALWAYS output the COMPLETE file content, never just snippets.**

WHY: The system replaces entire files. Partial snippets will delete the rest of the file!

When modifying existing files:
1. Include ALL original code from the file
2. Make your specific changes within the complete file
3. Mark changes with comments like "// CHANGED:" or "// ADDED:"
4. The highlighting system will automatically show users what changed
```

#### Project Generation Prompt

**Before** (Lines 334-375):
```
When MODIFYING existing projects:
1. For small changes: Show ONLY the changed section with context
2. For medium changes: Show the modified function/class
3. For large changes: Show complete file
```

**After** (Lines 334-383):
```
When MODIFYING existing files:
**CRITICAL: Always output the COMPLETE file, not snippets!**
The system replaces entire files - partial code will delete the rest!
Include ALL original code + your changes.
```

---

## Why Complete Files Are Required

### Technical Reason
```swift
// Current file writing implementation
try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
```

This is a **full file replacement**, not a patch operation:
- No diff/patch logic
- No line-by-line merging
- No context-aware insertion
- Just: "replace entire file with this content"

### Alternative Approaches (NOT Implemented)

We could implement smart patching, but it's complex and error-prone:

```swift
// Hypothetical patch logic (not implemented)
if isSnippet(file.content) {
    let originalContent = try String(contentsOf: fileURL)
    let patchedContent = applyPatch(original: originalContent, snippet: file.content)
    try patchedContent.write(to: fileURL)
}
```

**Problems with patching**:
- How to detect if content is a snippet vs. complete file?
- How to find where snippet belongs in original?
- What if original file changed since AI read it?
- What if multiple changes in different locations?
- Ambiguous context matching (multiple similar functions)

**Decision**: Require complete files = Simple, reliable, no ambiguity.

---

## How Change Highlighting Works Now

1. **AI sends complete file** with changes
2. **System writes complete file** to disk
3. **System reads original** from disk (before writing)
4. **ChangeHighlighter compares** original vs. new content line-by-line
5. **Editor highlights** changed lines in yellow

### User Experience

**User sees**:
- Complete file in editor (nothing deleted!)
- Changed lines highlighted in yellow
- Can review all changes in context
- Original code still there

**AI workflow**:
- AI can explain concisely: "I modified line 15"
- But code block MUST be complete file
- Highlighting shows users exactly what changed

---

## Examples

### ✅ Correct (After Fix)

**AI Response**:
```
I modified the calculateTotal function to add logging.

`src/calculator.js`:
```javascript
// COMPLETE FILE
function calculateTotal(items) {
    let total = 0;
    for (const item of items) {
        total += item.price;
    }
    console.log('Total:', total); // ADDED
    return total;
}

function validateItems(items) {
    // All other original functions included
    return items.every(item => item.price > 0);
}

module.exports = { calculateTotal, validateItems };
```
```

**Result**:
- File written with ALL content
- User sees complete file with logging line highlighted
- ✅ Nothing deleted!

### ❌ Wrong (Before Fix)

**AI Response**:
```
I modified the calculateTotal function:

`src/calculator.js`:
```javascript
// In calculateTotal function:
function calculateTotal(items) {
    let total = 0;
    for (const item of items) {
        total += item.price;
    }
    console.log('Total:', total); // ADDED
    return total;
}
```
```

**Result**:
- File written with ONLY this function
- `validateItems()` and `module.exports` DELETED
- ❌ Code loss!

---

## Prevention Measures

### Clear Warnings in Prompts

Both prompts now include:

1. **Bold WARNING**:
   > **ALWAYS output the COMPLETE file content, never just snippets.**

2. **Explanation**:
   > WHY: The system replaces entire files. Partial snippets will delete the rest!

3. **Clear Example**:
   ```
   // COMPLETE FILE (not a snippet!)
   [all original code]
   [your changes]
   [all other original code]
   ```

4. **Explicit Prohibition**:
   > NEVER use placeholders like "..." or "// rest of code here"

5. **System Benefit Explanation**:
   > The highlighting system will automatically show users what changed

---

## Build Status

✅ **BUILD SUCCEEDED**

No compilation errors.

---

## Testing

### Test Case 1: Small Change
1. Have existing file with multiple functions
2. Ask AI: "Add logging to calculateTotal"
3. **Expected**: AI outputs complete file with all functions
4. **Verify**: All original functions still present after applying

### Test Case 2: Large Refactor
1. Have complex file
2. Ask AI: "Refactor this code"
3. **Expected**: AI outputs complete refactored file
4. **Verify**: No functions or code deleted unexpectedly

### Test Case 3: New File
1. Ask AI: "Create a new utility file"
2. **Expected**: AI outputs complete new file
3. **Verify**: File created successfully with all content

---

## Related Systems

### Change Highlighting (Still Works!)

The change highlighting feature we just implemented **still works perfectly**:

1. AI sends complete file (with changes marked by comments)
2. System compares with original file
3. Changed lines highlighted in yellow
4. User sees exactly what changed

**Key insight**: Change highlighting doesn't need snippets - it detects changes automatically by comparing complete files!

### File Operations Unchanged

No changes needed to:
- [CursorStreamingView.swift](LingCode/Views/CursorStreamingView.swift)
- [ComposerView.swift](LingCode/Views/ComposerView.swift)
- [EditorViewModel.swift](LingCode/ViewModels/EditorViewModel.swift)

These still work correctly because they now receive complete files.

---

## Summary

### Problem
❌ AI sent snippets → System replaced entire files → Code deleted

### Solution
✅ Updated prompts → AI sends complete files → Highlighting shows changes

### Result
✅ No code loss
✅ Change highlighting still works
✅ Simple, reliable implementation
✅ No complex patching logic needed

### Files Modified
- [AIStepParser.swift:420-460](LingCode/Services/AIStepParser.swift#L420-L460) - Default prompt
- [AIStepParser.swift:334-383](LingCode/Services/AIStepParser.swift#L334-L383) - Project prompt

---

**Last Updated:** December 31, 2025
**Status:** ✅ **FIXED**
**Build:** ✅ **SUCCESS**
**Impact:** 🛡️ **Prevents Code Loss**
