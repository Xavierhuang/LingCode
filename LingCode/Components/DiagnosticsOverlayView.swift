//
//  DiagnosticsOverlayView.swift
//  LingCode
//
//  Renders diagnostics (red squiggles) over the text view
//

import AppKit

/// Overlay view that draws diagnostics (error/warning underlines) on top of text view
class DiagnosticsOverlayView: NSView {
    weak var textView: NSTextView?
    var diagnostics: [EditorDiagnostic] = []
    
    // CRITICAL FIX 1: Match NSTextView's top-down coordinate system
    override var isFlipped: Bool {
        return true
    }
    
    // CRITICAL FIX 2: Allow mouse clicks to pass through to the text view
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to tell the system "I don't handle clicks, check the view underneath me"
        return nil
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        
        let context = NSGraphicsContext.current?.cgContext
        context?.setLineWidth(1.0) // 1.0 looks cleaner for text underlines than 2.0
        
        // Draw diagnostics as wavy underlines
        for diagnostic in diagnostics {
            let range = diagnostic.range
            
            // Safety Check: Bounds
            guard range.location != NSNotFound,
                  range.location + range.length <= textView.string.count else {
                continue
            }
            
            // Optimization: Only process if potentially visible
            // (A rough check based on glyph range is fast enough)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let containerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            // Skip if the diagnostic is completely outside the area we are redrawing
            if !containerRect.intersects(dirtyRect) {
                continue
            }
            
            // Draw wavy underline for each line fragment
            var effectiveRange = NSRange(location: 0, length: 0)
            var remainingRange = glyphRange
            
            while remainingRange.length > 0 {
                let lineFragmentRect = layoutManager.lineFragmentRect(
                    forGlyphAt: remainingRange.location,
                    effectiveRange: &effectiveRange,
                    withoutAdditionalLayout: false
                )
                
                let intersection = NSIntersectionRange(remainingRange, effectiveRange)
                if intersection.length > 0 {
                    let boundingRect = layoutManager.boundingRect(
                        forGlyphRange: intersection,
                        in: textContainer
                    )
                    
                    // Apply offset from lineFragment if needed (usually 0 for simple text views)
                    let finalRect = boundingRect.offsetBy(dx: lineFragmentRect.minX, dy: lineFragmentRect.minY)
                    
                    // Draw wavy underline
                    drawWavyUnderline(
                        in: finalRect,
                        color: diagnostic.severity.nsColor
                    )
                }
                
                // Advance to next line fragment
                let nextLocation = NSMaxRange(effectiveRange)
                let consumedLength = nextLocation - remainingRange.location
                
                if consumedLength > 0 {
                    remainingRange = NSRange(
                        location: nextLocation,
                        length: remainingRange.length - consumedLength
                    )
                } else {
                    // Safety break to prevent infinite loops if layout manager fails
                    break
                }
            }
        }
    }
    
    /// Draw a wavy underline (like VS Code/Cursor)
    private func drawWavyUnderline(in rect: NSRect, color: NSColor) {
        color.setStroke()
        
        let path = NSBezierPath()
        path.lineWidth = 1.5 // Slightly thinner is usually more readable
        
        // Position at the bottom of the text, but ensure it doesn't clip
        // 'maxY' in a flipped view is the BOTTOM of the rect.
        let y = rect.maxY - 1.0 
        
        // Wave parameters
        let waveHeight: CGFloat = 2.5
        let waveLength: CGFloat = 4.0
        
        var x = rect.minX
        path.move(to: NSPoint(x: x, y: y))
        
        while x < rect.maxX {
            let nextX = min(x + waveLength, rect.maxX)
            let midX = (x + nextX) / 2
            
            // Create a simple sine-like wave
            // Toggle up/down based on the step
            path.curve(
                to: NSPoint(x: nextX, y: y),
                controlPoint1: NSPoint(x: (x + midX) / 2, y: y + waveHeight),
                controlPoint2: NSPoint(x: (midX + nextX) / 2, y: y - waveHeight)
            )
            
            x = nextX
        }
        
        path.stroke()
    }
    
    func updateDiagnostics(_ newDiagnostics: [EditorDiagnostic]) {
        diagnostics = newDiagnostics
        needsDisplay = true
    }
}

extension EditorDiagnostic.DiagnosticSeverity {
    var nsColor: NSColor {
        switch self {
        case .error:
            return NSColor.systemRed
        case .warning:
            return NSColor.systemOrange
        case .information:
            return NSColor.systemBlue
        case .hint:
            return NSColor.systemGray.withAlphaComponent(0.6)
        }
    }
}
