//
//  ContextVisualizationView.swift
//  LingCode
//
//  Shows what context is being used in AI requests
//

import SwiftUI

struct ContextVisualizationView: View {
    @ObservedObject var contextOrchestrator = ContextOrchestrator.shared
    @State private var isExpanded: Bool = true

    var body: some View {
        if !contextOrchestrator.currentContextSources.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "eye")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            
                            Text("Context (\(contextOrchestrator.currentContextSources.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        // Token count
                        if contextOrchestrator.totalTokenUsage > 0 {
                            Text("\(contextOrchestrator.totalTokenUsage) tokens")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
                
                // Context sources
                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(contextOrchestrator.currentContextSources) { source in
                            ContextSourceRow(source: source)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(DesignSystem.Animation.smooth, value: contextOrchestrator.currentContextSources.map(\.id))
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    )
                    .clipShape(
                        .rect(
                            bottomLeadingRadius: 6,
                            bottomTrailingRadius: 6
                        )
                    )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }
}

struct ContextSourceRow: View {
    let source: ContextSource
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: iconForType(source.type))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorForType(source.type))
                .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let path = source.path {
                    Text(path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Metadata
                HStack(spacing: 8) {
                    if let score = source.relevanceScore {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.orange)
                    }
                    
                    if let tokens = source.tokenCount {
                        Text("\(tokens) tokens")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.6) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
    }
    
    private func iconForType(_ type: ContextSource.ContextType) -> String {
        switch type {
        case .activeFile: return "doc.text"
        case .selectedText: return "text.selection"
        case .codebaseSearch: return "magnifyingglass"
        case .fileMention: return "at"
        case .folderMention: return "folder"
        case .terminalOutput: return "terminal"
        case .webSearch: return "globe"
        case .diagnostics: return "exclamationmark.triangle"
        case .gitDiff: return "arrow.triangle.2.circlepath"
        case .workspaceRules: return "book"
        case .codebaseOverview: return "chart.bar"
        }
    }
    
    private func colorForType(_ type: ContextSource.ContextType) -> Color {
        switch type {
        case .activeFile: return .blue
        case .selectedText: return .green
        case .codebaseSearch: return .purple
        case .fileMention: return .orange
        case .folderMention: return .yellow
        case .terminalOutput: return .red
        case .webSearch: return .cyan
        case .diagnostics: return .red
        case .gitDiff: return .blue
        case .workspaceRules: return .indigo
        case .codebaseOverview: return .teal
        }
    }
}
