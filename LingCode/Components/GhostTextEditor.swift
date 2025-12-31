//
//  GhostTextEditor.swift
//  LingCode
//
//  Cursor-style ghost text editor with Tab to accept
//

import SwiftUI
import AppKit
import Combine

/// Code editor with ghost text suggestions (like Cursor/Copilot)
struct GhostTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    var fontSize: CGFloat = EditorConstants.defaultFontSize
    var fontName: String = EditorConstants.defaultFontName
    var language: String?
    var aiGeneratedRanges: [NSRange] = []
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((String, Int) -> Void)?
    
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
        
        context.coordinator.textView = textView
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange
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
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? GhostTextNSTextView else { return }
        
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
        
        textView.needsDisplay = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        guard let language = language else { return }
        let highlighted = SyntaxHighlighter.highlight(textView.string, language: language)

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
    
    class Coordinator: NSObject {
        weak var textView: GhostTextNSTextView?
        var onTextChange: ((String) -> Void)?
        var onSelectionChange: ((String, Int) -> Void)?
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
            
            InlineSuggestionService.shared.requestSuggestion(
                for: content,
                at: position,
                language: language,
                context: content
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

/// Custom NSTextView that renders ghost text
class GhostTextNSTextView: NSTextView {
    var ghostText: String?
    var ghostTextPosition: Int = 0
    weak var coordinator: GhostTextEditor.Coordinator?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw ghost text
        if let ghost = ghostText, !ghost.isEmpty {
            drawGhostText(ghost)
        }
    }
    
    private func drawGhostText(_ ghost: String) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let position = selectedRange().location
        
        // Get the rect for the current cursor position
        let charIndex = min(position, string.count)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        
        var effectiveRange = NSRange(location: 0, length: 0)
        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)
        
        let cursorRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 0), in: textContainer)
        
        // Draw ghost text in gray
        let ghostFont = font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let ghostColor = NSColor.gray.withAlphaComponent(0.6)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ghostFont,
            .foregroundColor: ghostColor
        ]
        
        let ghostString = NSAttributedString(string: ghost, attributes: attributes)
        
        // Calculate position - right after cursor
        let xOffset = cursorRect.maxX
        let yOffset = lineFragmentRect.minY
        
        ghostString.draw(at: NSPoint(x: xOffset, y: yOffset))
    }
    
    override func keyDown(with event: NSEvent) {
        // Tab key to accept suggestion
        if event.keyCode == 48 && ghostText != nil { // Tab key
            if coordinator?.acceptSuggestion() == true {
                return // Don't pass Tab to super
            }
        }
        
        // Escape to dismiss suggestion
        if event.keyCode == 53 { // Escape
            ghostText = nil
            InlineSuggestionService.shared.cancelSuggestion()
            needsDisplay = true
            return
        }
        
        super.keyDown(with: event)
    }
    
    override func insertNewline(_ sender: Any?) {
        // Clear ghost text on Enter
        ghostText = nil
        super.insertNewline(sender)
    }
}

