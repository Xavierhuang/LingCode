//
//  LingCodeTerminalView.swift
//  LingCode
//
//  SwiftTerm-based terminal: ANSI, grid, bracketed paste, vim/nano, PTY.
//

import SwiftUI
import SwiftTerm

struct LingCodeTerminalView: NSViewRepresentable {
    let workingDirectory: URL?
    @Binding var isRunning: Bool
    @Binding var commandToSend: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator

        terminalView.startProcess(executable: "/bin/zsh", args: ["-i", "-l"])

        if let wdPath = workingDirectory?.path, !wdPath.isEmpty {
            let escaped = wdPath.replacingOccurrences(of: "'", with: "'\\''")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                terminalView.send(txt: "cd '\(escaped)'\n")
            }
        }

        DispatchQueue.main.async {
            isRunning = true
        }

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if let cmd = commandToSend, !cmd.isEmpty {
            let text = cmd.hasSuffix("\n") ? cmd : cmd + "\n"
            nsView.send(txt: text)
            commandToSend = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isRunning: $isRunning)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        @Binding var isRunning: Bool

        init(isRunning: Binding<Bool>) {
            _isRunning = isRunning
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
}
