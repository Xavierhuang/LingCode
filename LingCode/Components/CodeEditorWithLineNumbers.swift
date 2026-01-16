//
//  CodeEditorWithLineNumbers.swift
//  LingCode
//
//  Combined code editor with line numbers in a single scroll view
//

import SwiftUI
import AppKit

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
        // Initialize with minimum size to avoid constraint conflicts
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // Add both views as subviews
        addSubview(lineNumbersView)
        addSubview(textView)
        
        // Configure line numbers view
        lineNumbersView.editorScrollView = scrollView
        
        // Use autoresizing masks instead of constraints to avoid conflicts
        // This allows manual frame setting without constraint conflicts
        lineNumbersView.translatesAutoresizingMaskIntoConstraints = true
        textView.translatesAutoresizingMaskIntoConstraints = true
        translatesAutoresizingMaskIntoConstraints = true
        
        // Set autoresizing masks for layout
        lineNumbersView.autoresizingMask = [.height]
        textView.autoresizingMask = [.width, .height]
        
        // Observe text changes to update layout
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        
        // Observe text storage changes to ensure layout updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textStorageDidChange),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
    }
    
    @objc private func textDidChange() {
        needsLayout = true
    }
    
    @objc private func textStorageDidChange() {
        needsLayout = true
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isFlipped: Bool {
        return true
    }
    
    private var isLayouting = false // Prevent recursive layout calls
    
    override func layout() {
        // Prevent infinite layout loops
        guard !isLayouting else { return }
        isLayouting = true
        defer { isLayouting = false }
        
        super.layout()
        
        // Update line numbers view size based on text view content
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }
        
        // Force layout calculation to get accurate content size
        layoutManager.ensureLayout(for: textContainer)
        
        // Calculate line count from actual text content
        let text = textView.string
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        lineNumbersView.lineCount = lineCount
        
        // Get actual content height from layout manager
        let usedRect = layoutManager.usedRect(for: textContainer)
        var actualContentHeight = usedRect.height
        
        // If content is empty or very small, ensure minimum height
        if actualContentHeight < 100 {
            actualContentHeight = 100
        }
        
        // Ensure minimum height is at least visible area for proper scrolling
        let visibleHeight = scrollView.contentView.bounds.height
        let contentHeight = max(actualContentHeight, visibleHeight)
        
        // Get text view's natural width
        let textViewWidth = max(scrollView.contentView.bounds.width - gutterWidth, usedRect.width)
        
        // Update frames using autoresizing masks (no constraints)
        // Position line numbers on the left
        lineNumbersView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: contentHeight)
        
        // Position text view on the right
        textView.frame = NSRect(x: gutterWidth, y: 0, width: textViewWidth, height: contentHeight)
        
        // Update container size
        let containerWidth = gutterWidth + textViewWidth
        frame = NSRect(x: frame.origin.x, y: frame.origin.y, width: containerWidth, height: contentHeight)
        
        // Mark for display if needed
        lineNumbersView.needsDisplay = true
    }
}

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
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
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
        
        // Calculate line count
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        
        // Create line numbers view
        let lineNumbersView = LineNumbersNSView(
            lineCount: lineCount,
            fontSize: fontSize,
            fontName: fontName,
            editorScrollView: scrollView,
            colorScheme: colorScheme
        )
        
        // Create container view
        let containerView = EditorContainerView(
            textView: textView,
            lineNumbersView: lineNumbersView,
            scrollView: scrollView
        )
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = containerView
        
        context.coordinator.textView = textView
        context.coordinator.lineNumbersView = lineNumbersView
        context.coordinator.containerView = containerView
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.isModifiedBinding = Binding(
            get: { isModified },
            set: { isModified = $0 }
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        
        // Handle Tab key for autocomplete
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 48 && event.modifierFlags.contains(.command) == false {
                // Tab key pressed
                if let onAutocomplete = onAutocompleteRequest {
                    let position = textView.selectedRange().location
                    onAutocomplete(position)
                }
            }
            return event
        }
        
        textView.string = text
        applySyntaxHighlighting(to: textView, language: language)
        
        // Notify about scroll view creation
        onScrollViewCreated?(scrollView)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let containerView = nsView.documentView as? EditorContainerView else { return }
        let textView = containerView.textView
        
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
        
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        
        let theme = ThemeService.shared.currentTheme
        textView.textColor = theme.foreground
        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.cursor
        
        // Update line count
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        containerView.lineNumbersView.lineCount = lineCount
        containerView.lineNumbersView.fontSize = fontSize
        containerView.lineNumbersView.fontName = fontName
        containerView.lineNumbersView.colorScheme = colorScheme
        containerView.lineNumbersView.updateFrameSize()
        containerView.lineNumbersView.needsDisplay = true
        
        applySyntaxHighlighting(to: textView, language: language)
        
        // Update container layout
        containerView.needsLayout = true
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        let text = textView.string
        let theme = ThemeService.shared.currentTheme
        let highlighted = SyntaxHighlighter.highlight(text, language: language, theme: theme)

        let selectedRange = textView.selectedRange()

        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)
        mutableHighlighted.addAttribute(NSAttributedString.Key.font, value: font, range: NSRange(location: 0, length: mutableHighlighted.length))

        // Apply AI-generated change highlighting if present
        if !aiGeneratedRanges.isEmpty {
            let theme = ThemeService.shared.currentTheme
            ChangeHighlighter.applyHighlighting(
                to: mutableHighlighted,
                ranges: aiGeneratedRanges,
                baseFont: font,
                theme: theme
            )
        }

        textView.textStorage?.setAttributedString(mutableHighlighted)

        if selectedRange.location <= text.count {
            textView.setSelectedRange(selectedRange)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        weak var textView: NSTextView?
        weak var lineNumbersView: LineNumbersNSView?
        weak var containerView: EditorContainerView?
        var onTextChange: ((String) -> Void)?
        var onSelectionChange: ((String, Int) -> Void)?
        var isModifiedBinding: Binding<Bool>?
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let newText = textView.string
            onTextChange?(newText)
            isModifiedBinding?.wrappedValue = true
            
            // Update line numbers
            if let containerView = containerView {
                let lineCount = max(1, newText.components(separatedBy: .newlines).count)
                containerView.lineNumbersView.lineCount = lineCount
                containerView.lineNumbersView.updateFrameSize()
                containerView.needsLayout = true
            }
        }
        
        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            let selectedText = (textView.string as NSString).substring(with: selectedRange)
            onSelectionChange?(selectedText, selectedRange.location)
        }
    }
}

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
        let textView = GhostTextNSTextView()
        
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
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
        
        // Calculate line count
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        
        // Create line numbers view
        let lineNumbersView = LineNumbersNSView(
            lineCount: lineCount,
            fontSize: fontSize,
            fontName: fontName,
            editorScrollView: scrollView,
            colorScheme: colorScheme
        )
        
        // Create container view
        let containerView = EditorContainerView(
            textView: textView,
            lineNumbersView: lineNumbersView,
            scrollView: scrollView
        )
        
        // Create diagnostics overlay - add directly to textView, not containerView
        // This ensures it stays perfectly synced with text scrolling and typing
        let diagnosticsOverlay = DiagnosticsOverlayView(frame: textView.bounds)
        diagnosticsOverlay.textView = textView
        diagnosticsOverlay.updateDiagnostics(diagnostics)
        diagnosticsOverlay.autoresizingMask = [.width, .height] // Ensure it resizes with the text view
        textView.addSubview(diagnosticsOverlay)
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = containerView
        
        context.coordinator.textView = textView
        context.coordinator.lineNumbersView = lineNumbersView
        context.coordinator.containerView = containerView
        context.coordinator.diagnosticsOverlay = diagnosticsOverlay
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onAutocompleteRequest = onAutocompleteRequest
        context.coordinator.language = language
        context.coordinator.isModifiedBinding = Binding(
            get: { isModified },
            set: { isModified = $0 }
        )
        
        textView.coordinator = context.coordinator
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        
        textView.string = text
        applySyntaxHighlighting(to: textView, language: language)
        
        // Notify about scroll view creation
        onScrollViewCreated?(scrollView)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let containerView = nsView.documentView as? EditorContainerView,
              let textView = containerView.textView as? GhostTextNSTextView else { return }
        
        // Update diagnostics overlay
        context.coordinator.diagnosticsOverlay?.updateDiagnostics(diagnostics)
        
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
            applySyntaxHighlighting(to: textView, language: language)
        }
        
        // Update ghost text from suggestion service
        let suggestionService = InlineSuggestionService.shared
        if let suggestion = suggestionService.currentSuggestion {
            textView.ghostText = suggestion.text
            textView.ghostTextPosition = suggestion.insertPosition
        } else {
            textView.ghostText = nil
        }
        
        // Update line count
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        containerView.lineNumbersView.lineCount = lineCount
        containerView.lineNumbersView.fontSize = fontSize
        containerView.lineNumbersView.fontName = fontName
        containerView.lineNumbersView.colorScheme = colorScheme
        containerView.lineNumbersView.updateFrameSize()
        containerView.lineNumbersView.needsDisplay = true
        
        textView.needsDisplay = true
        containerView.needsLayout = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        guard let language = language else { return }
        let theme = ThemeService.shared.currentTheme
        let highlighted = SyntaxHighlighter.highlight(textView.string, language: language, theme: theme)

        let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)

        // Apply AI-generated change highlighting if present
        if !aiGeneratedRanges.isEmpty {
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let theme = ThemeService.shared.currentTheme
            ChangeHighlighter.applyHighlighting(
                to: mutableHighlighted,
                ranges: aiGeneratedRanges,
                baseFont: font,
                theme: theme
            )
        }

        if let textStorage = textView.textStorage {
            textStorage.setAttributedString(mutableHighlighted)
        }
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
        
        private var debounceTimer: Timer?
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let newText = textView.string
            
            isModifiedBinding?.wrappedValue = true
            onTextChange?(newText)
            
            // Clear ghost text when user types
            textView.ghostText = nil
            
            // Update line numbers
            if let containerView = containerView {
                let lineCount = max(1, newText.components(separatedBy: .newlines).count)
                containerView.lineNumbersView.lineCount = lineCount
                containerView.lineNumbersView.updateFrameSize()
                containerView.needsLayout = true
            }
            
            // Request new suggestion after debounce
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.requestSuggestion()
            }
        }
        
        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            let selectedText = (textView.string as NSString).substring(with: selectedRange)
            onSelectionChange?(selectedText, selectedRange.location)
        }
        
        func requestSuggestion() {
            guard let textView = textView else { return }
            let position = textView.selectedRange().location
            let content = textView.string
            
            // Use new inline autocomplete service with optimized context
            let lines = content.components(separatedBy: .newlines)
            let lineNumber = content.prefix(position).components(separatedBy: .newlines).count
            let last200Lines = Array(lines.suffix(200)).joined(separator: "\n")
            
            let context = AutocompleteContext(
                fileContent: content,
                cursorPosition: lineNumber,
                last200Lines: last200Lines,
                language: language ?? "swift"
            )
            
            // Check power-saving settings
            let powerSettings = PerformanceOptimizer.shared.getPowerSavingSettings()
            if powerSettings.reduceAutocompleteFrequency {
                // Skip autocomplete in power-saving mode
                return
            }
            
            InlineAutocompleteService.shared.requestSuggestion(
                context: context,
                onSuggestion: { suggestion in
                    if let suggestion = suggestion {
                        textView.ghostText = suggestion.currentText
                    }
                },
                onCancel: {
                    // Canceled - do nothing
                }
            )
        }
        
        func acceptSuggestion() -> Bool {
            guard let textView = textView,
                  let ghostText = textView.ghostText else { return false }
            
            // Insert ghost text at current position
            let position = textView.selectedRange().location
            let currentText = textView.string
            let beforeCursor = String(currentText.prefix(position))
            let afterCursor = String(currentText.suffix(currentText.count - position))
            
            textView.string = beforeCursor + ghostText + afterCursor
            textView.setSelectedRange(NSRange(location: position + ghostText.count, length: 0))
            textView.ghostText = nil
            
            InlineSuggestionService.shared.currentSuggestion = nil
            
            return true
        }
    }
}
