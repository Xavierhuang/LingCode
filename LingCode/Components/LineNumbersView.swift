//
//  LineNumbersView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct LineNumbersView: NSViewRepresentable {
    let lineCount: Int
    let fontSize: CGFloat
    let fontName: String
    var editorScrollView: NSScrollView?
    
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let lineNumbersView = LineNumbersNSView(
            lineCount: lineCount,
            fontSize: fontSize,
            fontName: fontName,
            editorScrollView: editorScrollView,
            colorScheme: colorScheme
        )
        
        scrollView.documentView = lineNumbersView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = gutterBackgroundColor
        scrollView.drawsBackground = true
        
        context.coordinator.lineNumbersView = lineNumbersView
        context.coordinator.scrollView = scrollView
        context.coordinator.editorScrollView = editorScrollView
        
        // Synchronize scrolling
        if let editorScrollView = editorScrollView {
            context.coordinator.synchronizeScrolling()
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let lineNumbersView = nsView.documentView as? LineNumbersNSView else { return }
        
        let needsUpdate = lineNumbersView.lineCount != lineCount ||
                          lineNumbersView.fontSize != fontSize ||
                          lineNumbersView.fontName != fontName ||
                          lineNumbersView.editorScrollView !== editorScrollView ||
                          lineNumbersView.colorScheme != colorScheme
        
        if needsUpdate {
            lineNumbersView.lineCount = lineCount
            lineNumbersView.fontSize = fontSize
            lineNumbersView.fontName = fontName
            lineNumbersView.editorScrollView = editorScrollView
            lineNumbersView.colorScheme = colorScheme
            lineNumbersView.updateFrameSize()
            lineNumbersView.needsLayout = true
            lineNumbersView.needsDisplay = true
        }
        
        nsView.backgroundColor = gutterBackgroundColor
        
        context.coordinator.editorScrollView = editorScrollView
        context.coordinator.synchronizeScrolling()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private var gutterBackgroundColor: NSColor {
        colorScheme == .dark
            ? NSColor(white: 0.15, alpha: 1.0)
            : NSColor(white: 0.93, alpha: 1.0)
    }
    
    class Coordinator: NSObject {
        weak var lineNumbersView: LineNumbersNSView?
        weak var scrollView: NSScrollView?
        weak var editorScrollView: NSScrollView?
        var scrollObserver: NSObjectProtocol?
        
        func synchronizeScrolling() {
            // Remove old observer
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            
            guard let editorScrollView = editorScrollView,
                  let scrollView = scrollView else { return }
            
            // Set up scroll synchronization
            editorScrollView.contentView.postsBoundsChangedNotifications = true
            
            // Observe editor scroll changes
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: editorScrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.syncScrollPosition()
            }
            
            // Initial sync
            syncScrollPosition()
        }
        
        private func syncScrollPosition() {
            guard let editorScrollView = editorScrollView,
                  let scrollView = scrollView else { return }
            
            let editorBounds = editorScrollView.contentView.bounds
            let lineNumbersBounds = scrollView.contentView.bounds
            
            if abs(lineNumbersBounds.origin.y - editorBounds.origin.y) > 0.5 {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: editorBounds.origin.y))
            }
            
            // Ensure the line numbers view is properly sized
            if let documentView = scrollView.documentView as? LineNumbersNSView {
                documentView.updateFrameSize()
            }
        }
        
        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

class LineNumbersNSView: NSView {
    var lineCount: Int
    var fontSize: CGFloat
    var fontName: String
    weak var editorScrollView: NSScrollView?
    var colorScheme: ColorScheme
    
    
    init(lineCount: Int, fontSize: CGFloat, fontName: String, editorScrollView: NSScrollView?, colorScheme: ColorScheme) {
        self.lineCount = lineCount
        self.fontSize = fontSize
        self.fontName = fontName
        self.editorScrollView = editorScrollView
        self.colorScheme = colorScheme
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isFlipped: Bool {
        return true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Fill background
        let backgroundColor = colorScheme == .dark
            ? NSColor(white: 0.15, alpha: 1.0)
            : NSColor(white: 0.93, alpha: 1.0)
        backgroundColor.setFill()
        dirtyRect.fill()
        
        guard lineCount > 0 else { return }
        
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHeight = self.lineHeight
        let lineNumberColor = colorScheme == .dark
            ? NSColor(white: 0.5, alpha: 1.0)
            : NSColor(white: 0.4, alpha: 1.0)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: lineNumberColor
        ]
        
        // Draw all line numbers (not just visible ones for simplicity)
        for lineNumber in 1...lineCount {
            let yPosition = CGFloat(lineNumber - 1) * lineHeight
            let lineRect = NSRect(x: 0, y: yPosition, width: bounds.width, height: lineHeight)
            
            if dirtyRect.intersects(lineRect) {
                let numberString = "\(lineNumber)"
                let attributedString = NSAttributedString(string: numberString, attributes: attributes)
                let stringSize = attributedString.size()
                
                let xPosition = bounds.width - stringSize.width - 8
                let yPositionCentered = yPosition + (lineHeight - stringSize.height) / 2
                
                attributedString.draw(at: NSPoint(x: xPosition, y: yPositionCentered))
            }
        }
    }
    
    override var intrinsicContentSize: NSSize {
        let lineHeight = self.lineHeight
        let totalHeight = CGFloat(max(1, lineCount)) * lineHeight
        // Ensure minimum width for line numbers
        let minWidth: CGFloat = 55
        return NSSize(width: minWidth, height: totalHeight)
    }
    
    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            updateFrameSize()
            needsLayout = true
            needsDisplay = true
        }
    }
    
    func updateFrameSize() {
        let lineHeight = self.lineHeight
        let totalHeight = CGFloat(max(1, lineCount)) * lineHeight
        let currentWidth = frame.width > 0 ? frame.width : 55
        setFrameSize(NSSize(width: currentWidth, height: totalHeight))
    }
    
    var lineHeight: CGFloat {
        // Try to get actual line height from editor's text view
        if let editorScrollView = editorScrollView,
           let textView = editorScrollView.documentView as? NSTextView,
           let layoutManager = textView.layoutManager {
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            if lineFragmentRect.height > 0 {
                return lineFragmentRect.height
            }
        }
        
        // Fallback to font metrics - NSTextView typically adds some extra spacing
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        // Use the same calculation that NSTextView uses internally
        let fontHeight = font.ascender - font.descender
        let lineSpacing = font.leading
        // NSTextView adds a small amount of extra spacing (typically 2-4 points)
        return fontHeight + lineSpacing + 2.0
    }
}
