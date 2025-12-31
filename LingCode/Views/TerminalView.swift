//
//  TerminalView.swift
//  LingCode
//
//  Real PTY-based terminal with shell integration
//

import SwiftUI
import AppKit
import Combine

struct TerminalView: NSViewRepresentable {
    @Binding var isVisible: Bool
    let workingDirectory: URL?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor.green
        textView.isAutomaticQuoteSubstitutionEnabled = false

        let textContainer = textView.textContainer!
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.workingDirectory = workingDirectory

        // Setup PTY terminal
        context.coordinator.setupTerminal()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.workingDirectory = workingDirectory
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var workingDirectory: URL?
        private var ptyService = PTYTerminalService.shared
        private var cancellables = Set<AnyCancellable>()
        private var currentInputStart: Int = 0

        func setupTerminal() {
            guard let textView = textView else { return }

            // Set delegate to intercept key events
            textView.delegate = self

            // Start PTY shell
            ptyService.startShell(workingDirectory: workingDirectory)

            // Observe output changes
            ptyService.$output
                .receive(on: DispatchQueue.main)
                .sink { [weak self] output in
                    self?.updateTerminalOutput(output)
                }
                .store(in: &cancellables)
        }

        private func updateTerminalOutput(_ output: String) {
            guard let textView = textView else { return }

            // Update text view with PTY output
            textView.string = output

            // Scroll to bottom
            textView.scrollToEndOfDocument(nil)

            // Update input start position
            currentInputStart = output.count
        }

        // MARK: - NSTextViewDelegate

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Return key
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let content = textView.string

                // Get the current line input (everything after currentInputStart)
                if currentInputStart < content.count {
                    let inputRange = content.index(content.startIndex, offsetBy: currentInputStart)..<content.endIndex
                    let input = String(content[inputRange])

                    // Send input to PTY
                    ptyService.sendInput(input)

                    // Update input start position
                    currentInputStart = content.count + 1
                }

                return true
            }

            return false
        }

        deinit {
            // Stop PTY when view is destroyed
            ptyService.stop()
        }
    }
}








