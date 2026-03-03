//
//  DiffCodeView.swift
//  LingCode
//
//  Read-only main-editor view that shows red (removed) / green (added) line diff when the agent has changed a file.
//

import SwiftUI
import AppKit

/// Layout manager that draws full-line red/green backgrounds for diff lines (full width of line).
final class DiffLayoutManager: NSLayoutManager {
    var removedRanges: [NSRange] = []
    var addedRanges: [NSRange] = []

    private func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location < b.location + b.length && b.location < a.location + a.length
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textContainer = textContainers.first else { return }
        let usedWidth = usedRect(for: textContainer).width
        let fillWidth = usedWidth > 0 ? usedWidth : 8000
        let redColor = NSColor.systemRed.withAlphaComponent(0.25)
        let greenColor = NSColor.systemGreen.withAlphaComponent(0.25)

        var glyphIndex = glyphsToShow.location
        while glyphIndex < glyphsToShow.location + glyphsToShow.length {
            var effectiveGlyphRange = NSRange(location: 0, length: 0)
            let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveGlyphRange)
            let effectiveCharRange = characterRange(forGlyphRange: effectiveGlyphRange, actualGlyphRange: nil)

            let isRemoved = removedRanges.contains { intersects($0, effectiveCharRange) }
            let isAdded = addedRanges.contains { intersects($0, effectiveCharRange) }
            if isRemoved || isAdded {
                var fullLineRect = lineRect
                fullLineRect.origin.x = origin.x
                fullLineRect.origin.y = origin.y + lineRect.origin.y
                fullLineRect.size.width = fillWidth
                (isRemoved ? redColor : greenColor).setFill()
                NSBezierPath.fill(fullLineRect)
            }
            glyphIndex = effectiveGlyphRange.location + effectiveGlyphRange.length
        }
    }
}

/// NSView that holds the diff container (left) and the hunk buttons column (right) so they scroll together.
final class DiffScrollDocumentView: NSView {
    let diffContainer: NSView
    let buttonsHostingView: NSHostingView<DiffHunkButtonsColumnView>?

    init(diffContainer: NSView, buttonsView: DiffHunkButtonsColumnView?) {
        self.diffContainer = diffContainer
        self.buttonsHostingView = buttonsView.map { NSHostingView(rootView: $0) }
        super.init(frame: .zero)
        addSubview(diffContainer)
        if let host = buttonsHostingView { addSubview(host) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        diffContainer.needsLayout = true
        diffContainer.layout()
        let diffWidth = diffContainer.frame.width
        let h = diffContainer.frame.height
        let buttonWidth: CGFloat = 128
        if let host = buttonsHostingView {
            host.frame = NSRect(x: 0, y: 0, width: buttonWidth, height: h)
            diffContainer.frame = NSRect(x: buttonWidth, y: 0, width: diffWidth, height: h)
        }
        frame = NSRect(x: frame.origin.x, y: frame.origin.y, width: diffWidth + (buttonsHostingView != nil ? buttonWidth : 0), height: h)
    }
}

struct DiffCodeView: NSViewRepresentable {
    let original: String
    let modified: String
    var fontSize: CGFloat = EditorConstants.defaultFontSize
    var fontName: String = EditorConstants.defaultFontName
    var language: String?
    var hunks: [DiffHunk] = []
    var onHunkUndo: ((Int) -> Void)?
    var onHunkKeep: ((Int) -> Void)?

    @Environment(\.colorScheme) var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let (displayString, removedRanges, addedRanges) = ChangeHighlighter.buildRedGreenDiffDisplay(original: original, modified: modified)

        let scrollView = NSScrollView()
        let storage = NSTextStorage(string: "")
        let layoutManager = DiffLayoutManager()
        layoutManager.removedRanges = removedRanges
        layoutManager.addedRanges = addedRanges
        storage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 0, height: 0)

        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.textColor = .editorText
        textView.backgroundColor = .editorBackground
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.height]

        let lineCount = max(1, displayString.components(separatedBy: .newlines).count)
        let lineNumbersView = LineNumbersNSView(
            lineCount: lineCount,
            fontSize: fontSize,
            fontName: fontName,
            editorScrollView: scrollView,
            colorScheme: colorScheme
        )
        let containerView = EditorContainerView(textView: textView, lineNumbersView: lineNumbersView, scrollView: scrollView)
        scrollView.hasVerticalScroller = true

        let lineHeight = fontSize * 1.4
        let documentView: NSView
        if !hunks.isEmpty, let onUndo = onHunkUndo, let onKeep = onHunkKeep {
            let columnView = DiffHunkButtonsColumnView(hunks: hunks, lineHeight: lineHeight, totalLines: lineCount, onHunkUndo: onUndo, onHunkKeep: onKeep)
            documentView = DiffScrollDocumentView(diffContainer: containerView, buttonsView: columnView)
        } else {
            documentView = containerView
        }
        scrollView.documentView = documentView

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: displayString)
        applyDiffHighlighting(to: textView, removedRanges: removedRanges, addedRanges: addedRanges)
        context.coordinator.removedRanges = removedRanges
        context.coordinator.addedRanges = addedRanges
        context.coordinator.diffLayoutManager = layoutManager
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let (displayString, removedRanges, addedRanges) = ChangeHighlighter.buildRedGreenDiffDisplay(original: original, modified: modified)
        let containerView: EditorContainerView
        if let wrapper = nsView.documentView as? DiffScrollDocumentView {
            containerView = wrapper.diffContainer as! EditorContainerView
        } else if let cv = nsView.documentView as? EditorContainerView {
            containerView = cv
        } else {
            return
        }
        let textView = containerView.textView
        if let lm = context.coordinator.diffLayoutManager {
            lm.removedRanges = removedRanges
            lm.addedRanges = addedRanges
        }
        if textView.string != displayString {
            textView.string = displayString
            applyDiffHighlighting(to: textView, removedRanges: removedRanges, addedRanges: addedRanges)
        }
        context.coordinator.removedRanges = removedRanges
        context.coordinator.addedRanges = addedRanges
        let lineCount = max(1, displayString.components(separatedBy: .newlines).count)
        containerView.lineNumbersView.lineCount = lineCount
        containerView.lineNumbersView.fontSize = fontSize
        containerView.lineNumbersView.fontName = fontName
        containerView.lineNumbersView.colorScheme = colorScheme
        containerView.lineNumbersView.updateFrameSize()
        containerView.needsLayout = true
        containerView.needsDisplay = true
        if nsView.documentView is DiffScrollDocumentView {
            nsView.documentView?.needsLayout = true
            nsView.documentView?.layout()
            if let host = (nsView.documentView as? DiffScrollDocumentView)?.buttonsHostingView,
               !hunks.isEmpty, let onUndo = onHunkUndo, let onKeep = onHunkKeep,
               let lm = context.coordinator.diffLayoutManager, let tc = textView.textContainer {
                lm.ensureLayout(for: tc)
                var range = NSRange(location: 0, length: 0)
                let lineRect = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: &range)
                let resolvedLineHeight = lineRect.height > 0 ? lineRect.height : (fontSize * 1.4)
                let topOffset = lineRect.origin.y
                let lineYPositions = Self.lineYPositionsForHunks(hunks, displayString: displayString, layoutManager: lm, textContainer: tc)
                host.rootView = DiffHunkButtonsColumnView(hunks: hunks, lineHeight: resolvedLineHeight, totalLines: lineCount, topOffset: topOffset, lineYPositions: lineYPositions, onHunkUndo: onUndo, onHunkKeep: onKeep)
            }
        }
    }

    private func applyDiffHighlighting(to textView: NSTextView, removedRanges: [NSRange], addedRanges: [NSRange]) {
        let theme = ThemeService.shared.currentTheme
        let highlighted = SyntaxHighlighter.highlight(textView.string, language: language, theme: theme)
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        if let font = textView.font {
            mutable.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutable.length))
        }
        let lineHeight = (textView.font?.pointSize ?? fontSize) * 1.4
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutable.length))
        textView.textStorage?.setAttributedString(mutable)
    }

    private static func characterRangeForLine(_ lineIndex: Int, in displayString: String) -> NSRange? {
        let ns = displayString as NSString
        if lineIndex < 0 || ns.length == 0 { return nil }
        var location = 0
        for _ in 0..<lineIndex {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: location, length: ns.length - location))
            if r.location == NSNotFound { return nil }
            location = r.location + r.length
        }
        let rest = NSRange(location: location, length: ns.length - location)
        let lineEnd = ns.range(of: "\n", options: [], range: rest)
        let length: Int
        if lineEnd.location == NSNotFound {
            length = ns.length - location
        } else {
            length = lineEnd.location + lineEnd.length - location
        }
        return NSRange(location: location, length: length)
    }

    private static func lineYPositionsForHunks(_ hunks: [DiffHunk], displayString: String, layoutManager: NSLayoutManager, textContainer: NSTextContainer) -> [CGFloat]? {
        var result: [CGFloat] = []
        for hunk in hunks {
            guard let charRange = characterRangeForLine(hunk.displayLineStart, in: displayString),
                  charRange.length > 0 else { return nil }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            if glyphRange.length > 0 {
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                result.append(rect.minY)
            } else {
                return nil
            }
        }
        return result.count == hunks.count ? result : nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var removedRanges: [NSRange] = []
        var addedRanges: [NSRange] = []
        weak var diffLayoutManager: DiffLayoutManager?
    }
}
