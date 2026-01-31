//
//  StreamingHeaderView.swift
//  LingCode
//
//  Header view for streaming interface
//

import SwiftUI

struct StreamingHeaderView: View {
    @ObservedObject var viewModel: AIViewModel
    var projectURL: URL? = nil
    var editorViewModel: EditorViewModel? = nil

    private var rulesFileName: String? {
        guard viewModel.projectMode, let url = projectURL else { return nil }
        return SpecPromptAssemblyService.loadedRulesFileName(workspaceRootURL: url)
    }

    private var isLocalMode: Bool {
        LocalOnlyService.shared.isLocalModeEnabled
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
                .help("AI Assistant")

            if let name = rulesFileName {
                Text(name)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.secondaryBackground.opacity(0.8))
                    .cornerRadius(4)
                    .help("Workspace rules loaded from this file")
            }

            Text(isLocalMode ? "Local" : "Cloud")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(isLocalMode ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isLocalMode ? DesignSystem.Colors.success : Color.clear).opacity(0.15))
                .cornerRadius(4)
                .help(isLocalMode ? "Using local model (Ollama)" : "Using cloud API")
            
            Spacer()
            
            // Codebase index status
            CodebaseIndexStatusView(editorViewModel: editorViewModel)
            
            // Performance dashboard button (NEW - Better than Cursor)
            Button(action: {
                // Trigger via notification or binding
                NotificationCenter.default.post(name: NSNotification.Name("ShowPerformanceDashboard"), object: nil)
            }) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Performance Dashboard")
            
            // Status indicator
            HStack(spacing: DesignSystem.Spacing.sm) {
                if viewModel.isLoading {
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.info)
                            .frame(width: 6, height: 6)
                            .shadow(color: DesignSystem.Colors.info.opacity(0.5), radius: 3)
                        
                        Circle()
                            .stroke(DesignSystem.Colors.info.opacity(0.4), lineWidth: 2)
                            .frame(width: 12, height: 12)
                            .scaleEffect(viewModel.isLoading ? 1.8 : 1.0)
                            .opacity(viewModel.isLoading ? 0.0 : 0.6)
                            .animation(
                                Animation.easeOut(duration: 1.2)
                                    .repeatForever(autoreverses: false),
                                value: viewModel.isLoading
                            )
                    }
                    Text("Working...")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        ))
                } else {
                    Circle()
                        .fill(DesignSystem.Colors.success)
                        .frame(width: 6, height: 6)
                        .shadow(color: DesignSystem.Colors.success.opacity(0.4), radius: 2)
                    Text("Ready")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .animation(DesignSystem.Animation.smooth, value: viewModel.isLoading)
            
            // Stop button (when loading)
            if viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    Text("Stop")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.error)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(DesignSystem.Colors.error.opacity(0.1))
                )
                .scaleEffect(viewModel.isLoading ? 1.0 : 0.95)
                .animation(DesignSystem.Animation.quick, value: viewModel.isLoading)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.secondaryBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

