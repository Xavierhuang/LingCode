//
//  CodeEditorWithLineNumbers.swift
//  LingCode
//
//  Combined code editor with line numbers in a single scroll view
//  FIXED: GhostTextEditorWithLineNumbers now uses async updates to prevent Tab crashes.
//

import SwiftUI
import AppKit

// MARK: - Container View (Preserved)

/// Container view that holds both line numbers and text view in a single scroll view
class EditorContainerView: NSView {
    let lineNumbersView: LineNumbersNSView
    let textView: NSTextView
    let scrollView: NSScrollView
    let gutterWidth: CGFloat = 55
    
    init(textView: NSTextView, lineNumbersView: LineNumbersNSView, scrollView: NSScrollView) {
        self.textView = textView
        self.lineNumbersView = lineNumbersView
        self.scrollView = scrollView
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        addSubview(lineNumbersView)
        addSubview(textView)
        
        lineNumbersView.editorScrollView = scrollView
        
        lineNumbersView.translatesAutoresizingMaskIntoConstraints = true
        textView.translatesAutoresizingMaskIntoConstraints = true
        translatesAutoresizingMaskIntoConstraints = true
        
        lineNumbersView.autoresizingMask = [.height]
        textView.autoresizingMask = [.width, .height]
        
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidChange), name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
    }
    
    @objc private func textDidChange() { needsLayout = true }
    @objc private func textStorageDidChange() { needsLayout = true }
    
    deinit { NotificationCenter.default.removeObserver(self) }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override var isFlipped: Bool { return true }
    private var isLayouting = false
    
    override func layout() {
        guard !isLayouting else { return }
        isLayouting = true
        defer { isLayouting = false }
        
        super.layout()
        
        guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else { return }
        layoutManager.ensureLayout(for: textContainer)
        
        let text = textView.string
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        lineNumbersView.lineCount = lineCount
        
        let usedRect = layoutManager.usedRect(for: textContainer)
        let actualContentHeight = max(usedRect.height < 100 ? 100 : usedRect.height, scrollView.contentView.bounds.height)
        let textViewWidth = max(scrollView.contentView.bounds.width - gutterWidth, usedRect.width)
        
        lineNumbersView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: actualContentHeight)
        textView.frame = NSRect(x: gutterWidth, y: 0, width: textViewWidth, height: actualContentHeight)
        
        frame = NSRect(x: frame.origin.x, y: frame.origin.y, width: gutterWidth + textViewWidth, height: actualContentHeight)
        lineNumbersView.needsDisplay = true
    }
}

// MARK: - Standard Code Editor (Preserved)

struct CodeEditorWithLineNumbers: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    var fontSize: CGFloat = EditorConstants.defaultFontSize
    var fontName: String = EditorConstants.defaultFontName
    var language: String?
    var aiGeneratedRanges: [NSRange] = []
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((String, Int) -> Void)?
    var onAutocompleteRequest: ((Int) -> Void)?
    var onScrollViewCreated: ((NSScrollView) -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.textColor = .editorText
        textView.backgroundColor = .editorBackground
        textView.insertionPointColor = .editorText
        
        let textContainer = textView.textContainer!
        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.height]
        
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        let lineNumbersView = LineNumbersNSView(
            lineCount: lineCount,
            fontSize: fontSize,
            fontName: fontName,
            editorScrollView: scrollView,
            colorScheme: colorScheme
        )
        
        let containerView = EditorContainerView(textView: textView, lineNumbersView: lineNumbersView, scrollView: scrollView)
        
        scrollView.hasVerticalScroller = true
        scrollView.documentView = containerView
        
        context.coordinator.setup(textView: textView, lineNumbersView: lineNumbersView, containerView: containerView)
        context.coordinator.update(onTextChange: onTextChange, onSelectionChange: onSelectionChange, isModifiedBinding: Binding(get: { isModified }, set: { isModified = $0 }))
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.textDidChange(_:)), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.selectionDidChange(_:)), name: NSTextView.didChangeSelectionNotification, object: textView)
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 48 && !event.modifierFlags.contains(.command) {
                if let onAutocomplete = onAutocompleteRequest {
                    onAutocomplete(textView.selectedRange().location)
                }
            }
            return event
        }
        
        textView.string = text
        applySyntaxHighlighting(to: textView, language: language)
        onScrollViewCreated?(scrollView)
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let containerView = nsView.documentView as? EditorContainerView else { return }
        let textView = containerView.textView
        
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count { textView.setSelectedRange(selectedRange) }
        }
        
        applySyntaxHighlighting(to: textView, language: language)
        
        // Update Layout
        containerView.lineNumbersView.lineCount = max(1, text.components(separatedBy: .newlines).count)
        containerView.lineNumbersView.fontSize = fontSize
        containerView.lineNumbersView.fontName = fontName
        containerView.lineNumbersView.colorScheme = colorScheme
        containerView.lineNumbersView.updateFrameSize()
        containerView.needsLayout = true
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        let theme = ThemeService.shared.currentTheme
        let highlighted = SyntaxHighlighter.highlight(textView.string, language: language, theme: theme)
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        if let font = textView.font {
            mutable.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutable.length))
        }
        
        if !aiGeneratedRanges.isEmpty {
            ChangeHighlighter.applyHighlighting(to: mutable, ranges: aiGeneratedRanges, baseFont: textView.font!, theme: theme)
        }
        textView.textStorage?.setAttributedString(mutable)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject {
        weak var textView: NSTextView?
        weak var lineNumbersView: LineNumbersNSView?
        weak var containerView: EditorContainerView?
        var onTextChange: ((String) -> Void)?
        var onSelectionChange: ((String, Int) -> Void)?
        var isModifiedBinding: Binding<Bool>?
        
        func setup(textView: NSTextView, lineNumbersView: LineNumbersNSView, containerView: EditorContainerView) {
            self.textView = textView
            self.lineNumbersView = lineNumbersView
            self.containerView = containerView
        }
        
        func update(onTextChange: ((String) -> Void)?, onSelectionChange: ((String, Int) -> Void)?, isModifiedBinding: Binding<Bool>?) {
            self.onTextChange = onTextChange
            self.onSelectionChange = onSelectionChange
            self.isModifiedBinding = isModifiedBinding
        }
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            onTextChange?(textView.string)
            isModifiedBinding?.wrappedValue = true
            
            if let containerView = containerView {
                containerView.lineNumbersView.lineCount = max(1, textView.string.components(separatedBy: .newlines).count)
                containerView.needsLayout = true
            }
        }
        
        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let content = textView.string as NSString
            let selectedText = content.substring(with: range)
            onSelectionChange?(selectedText, range.location)
        }
    }
}

// MARK: - Ghost Text Editor Wrapper (FIXED)

struct GhostTextEditorWithLineNumbers: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    var fontSize: CGFloat = EditorConstants.defaultFontSize
    var fontName: String = EditorConstants.defaultFontName
    var language: String?
    var aiGeneratedRanges: [NSRange] = []
    var diagnostics: [EditorDiagnostic] = []
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((String, Int) -> Void)?
    var onAutocompleteRequest: ((Int) -> Void)?
    var onScrollViewCreated: ((NSScrollView) -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = GhostTextNSTextView() // Use Custom Class
        
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.textColor
        
        let textContainer = textView.textContainer!
        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.height]
        
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        let lineNumbersView = LineNumbersNSView(
            lineCount: lineCount,
            fontSize: fontSize,
            fontName: fontName,
            editorScrollView: scrollView,
            colorScheme: colorScheme
        )
        
        let containerView = EditorContainerView(
            textView: textView,
            lineNumbersView: lineNumbersView,
            scrollView: scrollView
        )
        
        let diagnosticsOverlay = DiagnosticsOverlayView(frame: textView.bounds)
        diagnosticsOverlay.textView = textView
        diagnosticsOverlay.updateDiagnostics(diagnostics)
        diagnosticsOverlay.autoresizingMask = [.width, .height]
        textView.addSubview(diagnosticsOverlay)
        
        scrollView.hasVerticalScroller = true
        scrollView.documentView = containerView
        
        // Setup Coordinator
        context.coordinator.setup(
            textView: textView,
            lineNumbersView: lineNumbersView,
            containerView: containerView,
            diagnosticsOverlay: diagnosticsOverlay
        )
        context.coordinator.update(
            onTextChange: onTextChange,
            onSelectionChange: onSelectionChange,
            onAutocompleteRequest: onAutocompleteRequest,
            isModifiedBinding: Binding(get: { isModified }, set: { isModified = $0 }),
            language: language
        )
        
        textView.coordinator = context.coordinator
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.textDidChange(_:)), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.selectionDidChange(_:)), name: NSTextView.didChangeSelectionNotification, object: textView)
        
        textView.string = text
        applySyntaxHighlighting(to: textView, language: language)
        onScrollViewCreated?(scrollView)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let containerView = nsView.documentView as? EditorContainerView,
              let textView = containerView.textView as? GhostTextNSTextView else { return }
        
        context.coordinator.update(
            onTextChange: onTextChange,
            onSelectionChange: onSelectionChange,
            onAutocompleteRequest: onAutocompleteRequest,
            isModifiedBinding: Binding(get: { isModified }, set: { isModified = $0 }),
            language: language
        )
        
        context.coordinator.diagnosticsOverlay?.updateDiagnostics(diagnostics)
        
        // 🔒 LOCK CHECK: Fix for Tab bug
        if !context.coordinator.isLocalUpdate {
            if textView.string != text {
                let selectedRange = textView.selectedRange()
                textView.string = text
                if selectedRange.location <= text.count {
                    textView.setSelectedRange(selectedRange)
                }
                applySyntaxHighlighting(to: textView, language: language)
            }
        }
        
        // Safe updates for layout
        let lineCount = max(1, textView.string.components(separatedBy: .newlines).count)
        containerView.lineNumbersView.lineCount = lineCount
        containerView.lineNumbersView.fontSize = fontSize
        containerView.lineNumbersView.fontName = fontName
        containerView.lineNumbersView.colorScheme = colorScheme
        containerView.lineNumbersView.updateFrameSize()
        containerView.lineNumbersView.needsDisplay = true
        containerView.needsLayout = true
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        let theme = ThemeService.shared.currentTheme
        let highlighted = SyntaxHighlighter.highlight(textView.string, language: language, theme: theme)
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        
        if !aiGeneratedRanges.isEmpty {
            ChangeHighlighter.applyHighlighting(to: mutable, ranges: aiGeneratedRanges, baseFont: textView.font!, theme: theme)
        }
        textView.textStorage?.setAttributedString(mutable)
    }
    
    class Coordinator: NSObject, GhostTextCoordinator {
        weak var textView: GhostTextNSTextView?
        weak var lineNumbersView: LineNumbersNSView?
        weak var containerView: EditorContainerView?
        weak var diagnosticsOverlay: DiagnosticsOverlayView?
        var onTextChange: ((String) -> Void)?
        var onSelectionChange: ((String, Int) -> Void)?
        var onAutocompleteRequest: ((Int) -> Void)?
        var isModifiedBinding: Binding<Bool>?
        var language: String?
        
        var isLocalUpdate = false
        private var debounceTimer: Timer?
        
        func setup(textView: GhostTextNSTextView, lineNumbersView: LineNumbersNSView, containerView: EditorContainerView, diagnosticsOverlay: DiagnosticsOverlayView) {
            self.textView = textView
            self.lineNumbersView = lineNumbersView
            self.containerView = containerView
            self.diagnosticsOverlay = diagnosticsOverlay
        }
        
        func update(onTextChange: ((String) -> Void)?, onSelectionChange: ((String, Int) -> Void)?, onAutocompleteRequest: ((Int) -> Void)?, isModifiedBinding: Binding<Bool>?, language: String?) {
            self.onTextChange = onTextChange
            self.onSelectionChange = onSelectionChange
            self.onAutocompleteRequest = onAutocompleteRequest
            self.isModifiedBinding = isModifiedBinding
            self.language = language
        }
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let newText = textView.string
            
            // 🔒 Engage Lock
            isLocalUpdate = true
            textView.ghostText = nil
            
            // 🟢 ASYNC UPDATE (Fixes the crash)
            DispatchQueue.main.async { [weak self] in
                self?.isModifiedBinding?.wrappedValue = true
                self?.onTextChange?(newText)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.isLocalUpdate = false
                }
            }
            
            if let containerView = containerView {
                containerView.lineNumbersView.lineCount = max(1, newText.components(separatedBy: .newlines).count)
                containerView.needsLayout = true
            }
            
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.requestSuggestion()
            }
        }
        
        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let content = textView.string as NSString
            let selectedText = content.substring(with: range)
            onSelectionChange?(selectedText, range.location)
        }
        
        func requestSuggestion() {
            guard let textView = textView else { return }
            let content = textView.string
            let lines = content.components(separatedBy: .newlines)
            let lineNumber = content.prefix(textView.selectedRange().location).components(separatedBy: .newlines).count
            let last200Lines = Array(lines.suffix(200)).joined(separator: "\n")
            
            let context = AutocompleteContext(
                fileContent: content,
                cursorPosition: lineNumber,
                last200Lines: last200Lines,
                language: language ?? "swift"
            )
            
            InlineAutocompleteService.shared.requestSuggestion(
                context: context,
                onSuggestion: { suggestion in
                    if let suggestion = suggestion {
                        textView.ghostText = suggestion.currentText
                    }
                },
                onCancel: {}
            )
        }
        
        func acceptSuggestion() -> Bool {
            guard let textView = textView, let ghostText = textView.ghostText else { return false }
            
            // 🔒 Lock + Native Insert
            isLocalUpdate = true
            textView.insertText(ghostText, replacementRange: NSRange(location: NSNotFound, length: 0))
            textView.ghostText = nil
            return true
        }
    }
}