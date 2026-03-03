//
//  PTYTerminalView.swift
//  LingCode
//
//  SwiftTerm-based terminal UI: wrapper, multi-tab, and sheet content.
//

import SwiftUI

struct PTYTerminalViewWrapper: View {
    @Binding var isVisible: Bool
    let workingDirectory: URL?
    @Binding var commandToSend: String?

    @State private var isRunning: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            LingCodeTerminalView(
                workingDirectory: workingDirectory,
                isRunning: $isRunning,
                commandToSend: $commandToSend
            )
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)

            HStack(spacing: DesignSystem.Spacing.md) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(isRunning ? "Running" : "Stopped")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("UTF-8")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("zsh")
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
    }
}

struct SheetTerminalContent: View {
    @ObservedObject var manager: TerminalSessionManager
    @Binding var isVisible: Bool
    let workingDirectory: URL?

    var body: some View {
        Group {
            if let _ = manager.activeSession {
                PTYTerminalViewWrapper(
                    isVisible: $isVisible,
                    workingDirectory: workingDirectory,
                    commandToSend: $manager.commandToSend
                )
            } else {
                ProgressView("Opening terminal...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            manager.ensureOneTerminal(workingDirectory: workingDirectory)
        }
    }
}

struct MultiTerminalView: View {
    @ObservedObject var manager: TerminalSessionManager
    @Binding var isVisible: Bool
    let workingDirectory: URL?

    var body: some View {
        HStack(spacing: 0) {
            terminalContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(width: 1)

            terminalList
                .frame(width: 180)
                .background(DesignSystem.Colors.secondaryBackground)
        }
        .background(Color.black)
        .onAppear {
            manager.ensureOneTerminal(workingDirectory: workingDirectory)
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if manager.sessions.isEmpty {
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("No terminal")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Button("New Terminal") {
                    manager.addTerminal(workingDirectory: workingDirectory)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else {
            ZStack {
                ForEach(manager.sessions) { session in
                    PTYTerminalViewWrapper(
                        isVisible: $isVisible,
                        workingDirectory: workingDirectory,
                        commandToSend: manager.activeSessionId == session.id ? $manager.commandToSend : .constant(nil)
                    )
                    .id(session.id)
                    .opacity(manager.activeSessionId == session.id ? 1 : 0)
                    .allowsHitTesting(manager.activeSessionId == session.id)
                }
            }
        }
    }

    private var terminalList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("Terminals")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer(minLength: 0)
                Button(action: {
                    manager.addTerminal(workingDirectory: workingDirectory)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("New Terminal")
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(manager.sessions) { session in
                        Button(action: { manager.selectSession(id: session.id) }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                Text(session.name)
                                    .font(DesignSystem.Typography.caption1)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(manager.activeSessionId == session.id ? DesignSystem.Colors.sidebarSelected : Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}
