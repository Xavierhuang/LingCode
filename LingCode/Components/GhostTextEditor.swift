//
//  GhostTextEditor.swift
//  LingCode
//
//  DEBUG DIAGNOSTIC VERSION
//  Use this to identify if the View is resetting or if SwiftUI is overwriting data.
//

import SwiftUI
import AppKit
import Combine

struct GhostTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    var fontSize: CGFloat
    var fontName: String
    var language: String?
    var aiGeneratedRanges: [NSRange]
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((String, Int) -> Void)?
    var onScrollViewCreated: ((NSScrollView) -> Void)?
    
    // Debug ID to track View lifecycle
    let viewID = UUID().uuidString.prefix(4)
    
    init(text: Binding<String>, isModified: Binding<Bool>, fontSize: CGFloat = 12, fontName: String = "Monaco", language: String? = nil, aiGeneratedRanges: [NSRange] = [], onTextChange: ((String) -> Void)? = nil, onSelectionChange: ((String, Int) -> Void)? = nil, onScrollViewCreated: ((NSScrollView) -> Void)? = nil) {
        self._text = text
        self._isModified = isModified
        self.fontSize = fontSize
        self.fontName = fontName
        self.language = language
        self.aiGeneratedRanges = aiGeneratedRanges
        self.onTextChange = onTextChange
        self.onSelectionChange = onSelectionChange
        self.onScrollViewCreated = onScrollViewCreated
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        print("[\(viewID)] 🏗️ makeNSView - Creating new TextView")
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
        
        // Layout setup
        let textContainer = textView.textContainer!
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        
        // Link Coordinator
        context.coordinator.textView = textView
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.language = language
        context.coordinator.isModifiedBinding = Binding(
            get: { isModified },
            set: { isModified = $0 }
        )
        textView.coordinator = context.coordinator
        
        // Set initial state
        textView.string = text
        
        // Observers
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
        
        applySyntaxHighlighting(to: textView, language: language)
        onScrollViewCreated?(scrollView)
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? GhostTextNSTextView else { return }
        
        // Update closures
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.language = language
        context.coordinator.isModifiedBinding = Binding(get: { isModified }, set: { isModified = $0 })
        
        // 🕵️ DIAGNOSTIC LOG
        let localContent = textView.string
        let bindingContent = text
        let isLockActive = context.coordinator.isLocalUpdate
        
        if localContent != bindingContent {
            print("[\(viewID)] 🔄 updateNSView CONFLICT:")
            print("   - Local Text:  '\(localContent.suffix(20).replacingOccurrences(of: "\n", with: "\\n"))'")
            print("   - Binding Text: '\(bindingContent.suffix(20).replacingOccurrences(of: "\n", with: "\\n"))'")
            print("   - Lock Active:  \(isLockActive)")
            
            if isLockActive {
                print("   - 🛡️ BLOCKED: Ignoring SwiftUI update to preserve local typing.")
                return
            } else {
                print("   - ⚠️ OVERWRITE: SwiftUI is reverting the text!")
            }
        }
        
        if !context.coordinator.isLocalUpdate && textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
            // Re-apply highlighting
            applySyntaxHighlighting(to: textView, language: language)
        }
        
        textView.needsDisplay = true
    }
    
    func makeCoordinator() -> Coordinator {
        print("[\(viewID)] 🧩 makeCoordinator - New Coordinator")
        return Coordinator()
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        guard let language = language else { return }
        let theme = ThemeService.shared.currentTheme
        let highlighted = SyntaxHighlighter.highlight(textView.string, language: language, theme: theme)
        let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)

        if !aiGeneratedRanges.isEmpty {
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let theme = ThemeService.shared.currentTheme
            ChangeHighlighter.applyHighlighting(to: mutableHighlighted, ranges: aiGeneratedRanges, baseFont: font, theme: theme)
        }

        if let textStorage = textView.textStorage {
            textStorage.setAttributedString(mutableHighlighted)
        }
    }
    
    class Coordinator: NSObject, GhostTextCoordinator {
        weak var textView: GhostTextNSTextView?
        var onTextChange: ((String) -> Void)?
        var onSelectionChange: ((String, Int) -> Void)?
        var isModifiedBinding: Binding<Bool>?
        var language: String?
        
        // Lock flag
        var isLocalUpdate = false
        private var debounceTimer: Timer?
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let newText = textView.string
            
            print("⚡️ textDidChange triggered. Length: \(newText.count)")
            
            // Activate Lock
            isLocalUpdate = true
            textView.ghostText = nil
            
            DispatchQueue.main.async {
                self.isModifiedBinding?.wrappedValue = true
                self.onTextChange?(newText)
                
                // Release lock after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔓 Lock released")
                    self.isLocalUpdate = false
                }
            }
            
            // Re-trigger suggestions
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
            
            let lines = content.components(separatedBy: .newlines)
            let lineNumber = content.prefix(position).components(separatedBy: .newlines).count
            let last200Lines = Array(lines.suffix(200)).joined(separator: "\n")
            
            let context = AutocompleteContext(
                fileContent: content,
                cursorPosition: lineNumber,
                last200Lines: last200Lines,
                language: language ?? "swift"
            )
            
            print("🧠 Requesting Suggestion...")
            
            let powerSettings = PerformanceOptimizer.shared.getPowerSavingSettings()
            if powerSettings.reduceAutocompleteFrequency { return }
            
            InlineAutocompleteService.shared.requestSuggestion(
                context: context,
                onSuggestion: { suggestion in
                    if let suggestion = suggestion {
                        print("✨ Suggestion Received: '\(suggestion.currentText)'")
                        textView.ghostText = suggestion.currentText
                    }
                },
                onCancel: {}
            )
        }
        
        func acceptSuggestion() -> Bool {
            guard let textView = textView, let ghostText = textView.ghostText else { return false }
            print("🚀 Tab Pressed. Inserting: '\(ghostText)'")
            
            isLocalUpdate = true
            textView.insertText(ghostText, replacementRange: NSRange(location: NSNotFound, length: 0))
            textView.ghostText = nil
            return true
        }
    }
}

protocol GhostTextCoordinator: AnyObject {
    func acceptSuggestion() -> Bool
}

class GhostTextNSTextView: NSTextView {
    var ghostText: String? { didSet { needsDisplay = true } }
    weak var coordinator: GhostTextCoordinator?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let ghost = ghostText, !ghost.isEmpty {
            drawGhostText(ghost)
        }
    }
    
    private func drawGhostText(_ ghost: String) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let position = selectedRange().location
        let charIndex = min(position, string.count)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        var effectiveRange = NSRange(location: 0, length: 0)
        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)
        let cursorRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 0), in: textContainer)
        let font = self.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let ghostColor = NSColor.systemGray.withAlphaComponent(0.6)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ghostColor]
        let ghostString = NSAttributedString(string: ghost, attributes: attributes)
        ghostString.draw(at: NSPoint(x: cursorRect.maxX, y: lineFragmentRect.minY))
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && ghostText != nil { // Tab
            if coordinator?.acceptSuggestion() == true { return }
        }
        if event.keyCode == 53 { // Escape
            ghostText = nil
            InlineAutocompleteService.shared.cancel()
            return
        }
        super.keyDown(with: event)
    }
    
    override func insertNewline(_ sender: Any?) {
        ghostText = nil
        super.insertNewline(sender)
    }
    
    override func mouseDown(with event: NSEvent) {
        ghostText = nil
        super.mouseDown(with: event)
    }
}
