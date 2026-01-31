//
//  StatusBarView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct StatusBarView: View {
    @ObservedObject var editorState: EditorState
    let fontSize: CGFloat
    var editorViewModel: EditorViewModel? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            if let document = editorState.activeDocument {
                HStack(spacing: DesignSystem.Spacing.lg) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Text("Ln \(editorState.cursorPosition > 0 ? lineNumber(for: editorState.cursorPosition, in: document.content) : 1), Col \(columnNumber(for: editorState.cursorPosition, in: document.content))")
                            .font(DesignSystem.Typography.code)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        // Usage indicator
                        UsageIndicatorView()
                    }
                    
                    if !editorState.selectedText.isEmpty {
                        Text("\(editorState.selectedText.count) selected")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Text(document.language?.uppercased() ?? "PLAIN TEXT")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.small)
                }
            } else {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(DesignSystem.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Ready")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()

            RunningCommandsIndicator()

            CodebaseIndexStatusView(editorViewModel: editorViewModel)
                .animation(DesignSystem.Animation.smooth, value: editorState.activeDocument?.filePath)

            HStack(spacing: DesignSystem.Spacing.md) {
                Text("UTF-8")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("LF")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("Spaces: \(EditorConstants.tabSize)")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.secondaryBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private func lineNumber(for position: Int, in text: String) -> Int {
        let beforeCursor = String(text.prefix(position))
        return beforeCursor.components(separatedBy: .newlines).count
    }
    
    private func columnNumber(for position: Int, in text: String) -> Int {
        let beforeCursor = String(text.prefix(position))
        if let lastNewline = beforeCursor.lastIndex(of: "\n") {
            let lineStart = beforeCursor.index(after: lastNewline)
            return text.distance(from: lineStart, to: beforeCursor.endIndex) + 1
        }
        return position + 1
    }
}

// MARK: - Running commands / background jobs indicator
/// Shows when a terminal command or background job is running so users know validation may be delayed.
private struct RunningCommandsIndicator: View {
    @ObservedObject private var terminal = TerminalExecutionService.shared

    var body: some View {
        Group {
            if terminal.isExecuting {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                    Text("Command running")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .help("A terminal command is running. Validation may be blocked until it finishes.")
            } else if terminal.isBackgroundRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignSystem.Colors.textTertiary)
                        .frame(width: 5, height: 5)
                    Text("1 background job")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .help("A background command is running. Validation may be delayed.")
            }
        }
    }
}




