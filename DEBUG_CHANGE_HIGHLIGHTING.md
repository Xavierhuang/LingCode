# 🐛 Debug: Change Highlighting Not Showing on Auto-Open

## Issue

User reports: "the changes don't show up unless i click on the name in the chat"

**Behavior**:
- ✅ Works when clicking file card in chat
- ❌ Doesn't work on auto-open (first file)

---

## Investigation

### Code Flow

1. **AI generates file** → Parsed into `StreamingFileInfo`
2. **Auto-open triggered** (line 95):
   ```swift
   .onChange(of: parsedFiles.count) { oldCount, newCount in
       if oldCount == 0 && newCount == 1, let firstFile = parsedFiles.first {
           openFile(firstFile)  // Auto-open
       }
   }
   ```

3. **openFile() executes**:
   ```swift
   // Read original from disk
   let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil

   // Write new content to disk
   try file.content.write(to: fileURL, atomically: true, encoding: .utf8)

   // Open with highlighting
   editorViewModel.openFile(at: fileURL, originalContent: originalContent)
   ```

4. **EditorViewModel.openFile()**:
   ```swift
   // For new documents
   let document = Document(...)
   if let original = originalContent {
       document.markAsAIGenerated(originalContent: original)
   }
   ```

---

## Possible Issues

### Theory 1: Timing Issue
**Hypothesis**: File hasn't been written when auto-open fires

**Evidence Against**: The code writes the file BEFORE calling openFile(), so this shouldn't be the issue.

### Theory 2: Empty Original Content
**Hypothesis**: `originalContent` is empty or nil, so no ranges are calculated

**Debugging**: Added logging to `Document.markAsAIGenerated()`:
```swift
print("🎨 Document.markAsAIGenerated: Found \(aiGeneratedRanges.count) changed ranges")
for (index, range) in aiGeneratedRanges.prefix(3).enumerated() {
    print("   Range \(index): location=\(range.location), length=\(range.length)")
}
```

**What to check**:
- Is `markAsAIGenerated()` being called?
- How many ranges are found?
- Are ranges valid (non-zero length)?

### Theory 3: @Published Not Triggering Update
**Hypothesis**: `aiGeneratedRanges` changes but SwiftUI doesn't re-render editor

**Evidence**: `aiGeneratedRanges` is `@Published` in Document, and Document is `@ObservableObject`

**Possible issue**: The binding from EditorView → GhostTextEditor might not be updating

### Theory 4: File Already Open
**Hypothesis**: File is already open when auto-open fires, so it hits the "already open" path

**Code path** (EditorViewModel:155-162):
```swift
if let original = originalContent {
    // Read current content from disk
    if let diskContent = try? String(contentsOf: standardizedURL, encoding: .utf8) {
        existingDocument.content = diskContent
        existingDocument.markAsAIGenerated(originalContent: original)
        print("🎨 Applied AI change highlighting to open file")
    }
}
```

**What happens if file is NOT already open**: Should create new document (lines 174-188)

---

## Testing Steps

1. **Start fresh** - Close all files
2. **Ask AI** to modify an existing file
3. **Watch console logs** for:
   ```
   📄 File already open, activating: [path]
   OR
   ✅ Opened file: [path]

   🎨 Applied AI change highlighting to new document
   OR
   🎨 Applied AI change highlighting to open file

   🎨 Document.markAsAIGenerated: Found X changed ranges
   ```

4. **Check if highlighting appears** immediately on auto-open

5. **Click file card** in chat and see if highlighting appears then

---

## Expected Logs (If Working)

```
📂 Updating existing file: /path/to/file.swift
✅ Opened file: /path/to/file.swift
🎨 Applied AI change highlighting to new document
🎨 Document.markAsAIGenerated: Found 3 changed ranges
   Range 0: location=150, length=45
   Range 1: location=220, length=32
   Range 2: location=280, length=18
```

---

## Potential Fixes

### Fix 1: Force View Update
Ensure `objectWillChange.send()` is called after marking as AI-generated:

```swift
func markAsAIGenerated(originalContent: String?) {
    self.originalContent = originalContent
    self.aiGeneratedRanges = ChangeHighlighter.detectChangedRanges(
        original: originalContent ?? "",
        modified: content
    )
    objectWillChange.send()  // Force update
}
```

### Fix 2: Delay Auto-Open
Add small delay to ensure file is fully written:

```swift
if oldCount == 0 && newCount == 1, let firstFile = parsedFiles.first {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        openFile(firstFile)
    }
}
```

### Fix 3: Check File Content Matches
Verify disk content matches what we expect:

```swift
// After writing file
let diskContent = try? String(contentsOf: fileURL, encoding: .utf8)
if diskContent != file.content {
    print("⚠️ Disk content doesn't match file.content!")
}
```

---

## Next Steps

1. Run app with debug logging
2. Test auto-open scenario
3. Check console logs
4. Compare with "click file card" scenario logs
5. Identify difference in code paths
6. Apply appropriate fix

---

**Status:** 🔍 **INVESTIGATING**
**Last Updated:** December 31, 2025
