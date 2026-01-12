# Changelog

## [Latest] - 2025-01-XX

### Major Upgrades

#### 1. **Fixed Sendable Conformance Issues**
   - Resolved `Sendable` protocol conformance errors in `CursorStreamingView` and `StreamingInputView`
   - Added `@preconcurrency` import for `UniformTypeIdentifiers` to handle `NSItemProvider` Sendable requirements
   - Fixed async closure isolation boundaries for image drop handlers

#### 2. **Line Number Synchronization Fix**
   - **Complete rewrite of `LineNumbersView`**: Converted from SwiftUI view to `NSViewRepresentable` for better control
   - **Synchronized scrolling**: Line numbers now scroll in perfect sync with the code editor
   - **Accurate line height calculation**: Uses actual line height from `NSTextView`'s layout manager instead of manual calculation
   - **Real-time updates**: Line numbers update correctly when document content changes
   - **Proper frame sizing**: Line numbers view now properly sizes itself based on content

#### 3. **Code Editor Improvements**
   - Enhanced `GhostTextEditor` to expose scroll view for synchronization
   - Updated `CodeEditor` to support scroll view synchronization
   - Improved `EditorView` to pass scroll view references to line numbers
   - Fixed `SplitEditorView` to maintain line number synchronization in split panes

### Technical Details

#### Files Modified:
- `LingCode/Views/CursorStreamingView.swift` - Fixed Sendable conformance
- `LingCode/Views/StreamingInputView.swift` - Fixed Sendable conformance and async closures
- `LingCode/Components/LineNumbersView.swift` - Complete rewrite with NSViewRepresentable
- `LingCode/Views/EditorView.swift` - Added scroll view synchronization
- `LingCode/Components/GhostTextEditor.swift` - Added scroll view callback
- `LingCode/Components/CodeEditor.swift` - Added scroll view callback
- `LingCode/Views/SplitEditorView.swift` - Added scroll view synchronization

#### Key Improvements:
- **Better performance**: Direct NSView implementation reduces SwiftUI overhead
- **Perfect alignment**: Line numbers now match code lines exactly
- **Smooth scrolling**: Synchronized scroll views provide seamless experience
- **Theme support**: Line numbers respect dark/light mode changes
- **Memory efficiency**: Proper weak references prevent retain cycles

### Bug Fixes
- Fixed line numbers not displaying after refactoring
- Fixed line number misalignment with code content
- Fixed scroll synchronization issues between line numbers and editor
- Fixed Sendable conformance warnings in Swift 6 concurrency

### Breaking Changes
- None - all changes are backward compatible

