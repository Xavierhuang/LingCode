//
//  PTYTerminalView.swift
//  LingCode
//
//  PTY-based terminal view with real shell integration
//

import SwiftUI
import AppKit
import Combine

struct PTYTerminalView: NSViewRepresentable {
    @Binding var isVisible: Bool
    let workingDirectory: URL?
    
    @StateObject private var ptyService = PTYTerminalService.shared
    
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
        context.coordinator.ptyService = ptyService
        context.coordinator.workingDirectory = workingDirectory
        
        // Start PTY shell
        ptyService.startShell(workingDirectory: workingDirectory)
        
        // Observe output
        ptyService.$output
            .sink { output in
                DispatchQueue.main.async {
                    textView.string = output
                    textView.scrollToEndOfDocument(nil)
                }
            }
            .store(in: &context.coordinator.cancellables)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.workingDirectory = workingDirectory
        
        // Update terminal size
        if let textView = nsView.documentView as? NSTextView,
           let frame = textView.enclosingScrollView?.contentSize {
            let rows = UInt16(frame.height / 14) // Approximate row height
            let cols = UInt16(frame.width / 8)  // Approximate column width
            ptyService.setSize(rows: rows, cols: cols)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        weak var textView: NSTextView?
        var ptyService: PTYTerminalService?
        var workingDirectory: URL?
        var cancellables = Set<AnyCancellable>()
        
        override init() {
            super.init()
        }
        
        deinit {
            cancellables.removeAll()
        }
    }
}

// SwiftUI wrapper for PTY terminal
struct PTYTerminalViewWrapper: View {
    @Binding var isVisible: Bool
    let workingDirectory: URL?
    @StateObject private var ptyService = PTYTerminalService.shared
    @State private var input: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            PTYTerminalView(isVisible: $isVisible, workingDirectory: workingDirectory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Input area
            HStack {
                Text("$")
                    .foregroundColor(.green)
                    .font(.system(.body, design: .monospaced))
                
                TextField("Enter command...", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .onSubmit {
                        sendCommand()
                    }
                
                if ptyService.isRunning {
                    Button(action: { ptyService.stop() }) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color.black)
        }
        .background(Color.black)
        .onAppear {
            if !ptyService.isRunning {
                ptyService.startShell(workingDirectory: workingDirectory)
            }
        }
        .onDisappear {
            // Don't stop on disappear, keep terminal running
        }
    }
    
    private func sendCommand() {
        guard !input.isEmpty else { return }
        ptyService.sendInput(input)
        input = ""
    }
}

