//
//  CodeEditor.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
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
        guard let textView = nsView.documentView as? NSTextView else { return }
        
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
        
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
        
        applySyntaxHighlighting(to: textView, language: language)
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView, language: String?) {
        let text = textView.string
        let highlighted = SyntaxHighlighter.highlight(text, language: language)

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
        var onTextChange: ((String) -> Void)?
        var onSelectionChange: ((String, Int) -> Void)?
        var isModifiedBinding: Binding<Bool>?
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let newText = textView.string
            onTextChange?(newText)
            isModifiedBinding?.wrappedValue = true
            
            // Re-apply syntax highlighting
            DispatchQueue.main.async {
                // Highlighting will be applied in updateNSView
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

