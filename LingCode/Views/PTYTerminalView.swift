//
//  PTYTerminalView.swift
//  LingCode
//
//  PTY-based terminal view with real shell integration
//  Cursor-style terminal with inline input and status bar
//

import SwiftUI
import AppKit
import Combine

struct PTYTerminalView: NSViewRepresentable {
    @Binding var isVisible: Bool
    let workingDirectory: URL?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0) // Terminal green
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.insertionPointColor = NSColor.green
        textView.allowsUndo = false
        
        let textContainer = textView.textContainer!
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.black
        scrollView.documentView = textView
        
        let ptyService = PTYTerminalService.shared
        context.coordinator.textView = textView
        context.coordinator.ptyService = ptyService
        context.coordinator.workingDirectory = workingDirectory
        context.coordinator.setupKeyboardHandling()
        
        // Start PTY shell
        ptyService.startShell(workingDirectory: workingDirectory)
        
        // Capture coordinator for sink closure (coordinator is a class, can be weak)
        let coordinator = context.coordinator
        
        // Observe output
        var lastOutputLength = 0
        ptyService.$output
            .sink { [weak textView, weak coordinator] output in
                DispatchQueue.main.async {
                    guard let textView = textView, let coordinator = coordinator else { return }
                    
                    let currentText = textView.string
                    let outputLength = output.count
                    
                    // Only update if output has actually changed
                    if output != currentText {
                        let wasAtEnd = textView.selectedRange().location >= currentText.count - 1
                        
                        // Update the text
                        textView.string = output
                        
                        // Update input start index if output grew (new prompt)
                        if outputLength > lastOutputLength {
                            // Check if this looks like a new prompt (ends with $ or >)
                            if output.hasSuffix("$ ") || output.hasSuffix("> ") || output.hasSuffix("% ") {
                                coordinator.inputStartIndex = outputLength
                            }
                        }
                        
                        // Scroll to end and restore cursor position
                        textView.scrollToEndOfDocument(nil)
                        if wasAtEnd {
                            textView.setSelectedRange(NSRange(location: outputLength, length: 0))
                        }
                        
                        lastOutputLength = outputLength
                    }
                }
            }
            .store(in: &coordinator.cancellables)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.workingDirectory = workingDirectory
        
        // Update terminal size
        if let textView = nsView.documentView as? NSTextView,
           let frame = textView.enclosingScrollView?.contentSize {
            let rows = UInt16(frame.height / 14) // Approximate row height
            let cols = UInt16(frame.width / 8)  // Approximate column width
            PTYTerminalService.shared.setSize(rows: rows, cols: cols)
        }
        
        // Ensure text view can receive focus when visible
        if isVisible, let textView = nsView.documentView as? NSTextView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var ptyService: PTYTerminalService?
        var workingDirectory: URL?
        var cancellables = Set<AnyCancellable>()
        var inputStartIndex: Int = 0
        
        override init() {
            super.init()
        }
        
        func setupKeyboardHandling() {
            guard let textView = textView else { return }
            textView.delegate = self
        }
        
        // MARK: - NSTextViewDelegate
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Return key - send newline to PTY
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let currentText = textView.string
                let cursorPos = textView.selectedRange().location
                
                // Get the current input line (from last prompt to cursor)
                if cursorPos >= inputStartIndex && cursorPos <= currentText.count {
                    let inputLine = (currentText as NSString).substring(with: NSRange(location: inputStartIndex, length: cursorPos - inputStartIndex))
                    // Send the line to PTY (it will add newline and execute)
                    ptyService?.sendInput(inputLine)
                } else {
                    // Just send newline
                    ptyService?.sendRawInput("\n")
                }
                
                // Don't insert newline here - PTY will echo it back
                return true
            }
            
            return false
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let currentText = textView.string
            let cursorPos = affectedCharRange.location
            
            // Only allow editing in the input area (after inputStartIndex)
            if cursorPos < inputStartIndex {
                // Move cursor to input start if trying to edit before it
                DispatchQueue.main.async {
                    textView.setSelectedRange(NSRange(location: self.inputStartIndex, length: 0))
                }
                return false
            }
            
            // Allow the change to happen in the text view (for immediate feedback)
            // Also send to PTY so it can process it
            if let replacement = replacementString {
                if replacement == "\n" || replacement == "\r" {
                    // Return is handled by doCommandBy
                    return false
                }
                
                // Send character to PTY (shell will echo it back, which will update the view)
                ptyService?.sendRawInput(replacement)
            } else {
                // Deletion - send backspace to PTY
                if affectedCharRange.length > 0 {
                    ptyService?.sendRawInput("\u{7F}") // Backspace character
                }
            }
            
            // Allow the text change - PTY output will sync it
            return true
        }
        
        deinit {
            cancellables.removeAll()
        }
    }
}

// SwiftUI wrapper for PTY terminal with Cursor-style design
struct PTYTerminalViewWrapper: View {
    @Binding var isVisible: Bool
    let workingDirectory: URL?
    @StateObject private var ptyService = PTYTerminalService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output area (handles input inline)
            PTYTerminalView(isVisible: $isVisible, workingDirectory: workingDirectory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Status bar (Cursor-style)
            HStack(spacing: DesignSystem.Spacing.md) {
                // Ready indicator
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Ready")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                // File encoding info
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("UTF-8")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text("LF")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text("Spaces: 4")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.secondaryBackground)
            .frame(height: 22)
        }
        .background(Color.black)
        .onAppear {
            if !ptyService.isRunning {
                ptyService.startShell(workingDirectory: workingDirectory)
            }
        }
    }
}

