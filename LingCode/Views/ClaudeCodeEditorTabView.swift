//
//  ClaudeCodeEditorTabView.swift
//  LingCode
//
//  Runs the real `claude` CLI inside a SwiftTerm terminal — like Cursor's Claude Code tab.
//

import SwiftUI
import SwiftTerm

// MARK: - Terminal wrapper that launches the claude CLI

struct ClaudeCodeTerminalView: NSViewRepresentable {
    let workingDirectory: URL?
    let claudePath: String
    @Binding var isRunning: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: .zero)
        tv.processDelegate = context.coordinator

        // cd to the project directory first, then launch claude
        let args: [String]
        if let wdPath = workingDirectory?.path, !wdPath.isEmpty {
            // Use a login interactive zsh that cds and execs claude so the
            // environment ($PATH, nvm, rbenv, etc.) is fully loaded.
            args = ["-i", "-l", "-c", "cd '\(wdPath.replacingOccurrences(of: "'", with: "'\\''"))' && '\(claudePath)'"]
            tv.startProcess(executable: "/bin/zsh", args: args)
        } else {
            tv.startProcess(executable: claudePath, args: [])
        }

        DispatchQueue.main.async { isRunning = true }
        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(isRunning: $isRunning) }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        @Binding var isRunning: Bool
        init(isRunning: Binding<Bool>) { _isRunning = isRunning }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
}

// MARK: - Main tab view

struct ClaudeCodeEditorTabView: View {
    @ObservedObject var viewModel: EditorViewModel

    @State private var isRunning: Bool = false
    @State private var claudePath: String? = nil
    @State private var searchComplete: Bool = false

    private let candidatePaths: [String] = [
        "/Users/\(NSUserName())/.local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/bin/claude",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text("Claude Code")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text("—")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text(viewModel.rootFolderURL?.lastPathComponent ?? "No folder")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(isRunning ? "Running" : "Stopped")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.secondaryBackground)

            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1)

            if !searchComplete {
                // Still detecting
                Color.black.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let path = claudePath {
                // Launch the real claude CLI
                ClaudeCodeTerminalView(
                    workingDirectory: viewModel.rootFolderURL,
                    claudePath: path,
                    isRunning: $isRunning
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                notInstalledView
            }
        }
        .background(Color.black)
        .onAppear { detectClaude() }
    }

    // MARK: - Not installed fallback

    private var notInstalledView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            Text("Claude Code not found")
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Text("Install the Claude Code CLI to use it here:")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Text("npm install -g @anthropic-ai/claude-code")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.green)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
            Button("Open Installation Docs") {
                NSWorkspace.shared.open(URL(string: "https://docs.anthropic.com/en/docs/claude-code")!)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.primaryBackground)
    }

    // MARK: - Detection

    private func detectClaude() {
        Task.detached(priority: .userInitiated) {
            // 1. Check well-known paths
            for path in candidatePaths {
                if FileManager.default.isExecutableFile(atPath: path) {
                    await MainActor.run {
                        claudePath = path
                        searchComplete = true
                    }
                    return
                }
            }
            // 2. Fall back to `which claude` via a login shell
            if let found = shellWhich("claude") {
                await MainActor.run {
                    claudePath = found
                    searchComplete = true
                }
                return
            }
            await MainActor.run { searchComplete = true }
        }
    }

    private func shellWhich(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i", "-l", "-c", "which \(command)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (result?.isEmpty == false) ? result : nil
        } catch {
            return nil
        }
    }
}
