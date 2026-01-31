//
//  CodebaseIndexStatusView.swift
//  LingCode
//
//  Status indicator for codebase indexing
//

import SwiftUI

struct CodebaseIndexStatusView: View {
    @StateObject private var indexService = CodebaseIndexService.shared
    @State private var showDetails = false
    var editorViewModel: EditorViewModel?
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if indexService.isIndexing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Indexing...")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            } else if indexService.lastIndexDate != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.success)
                    .font(.caption)
                Text("\(indexService.indexedFileCount) files")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignSystem.Colors.warning)
                    .font(.caption)
                Text("Not indexed")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
        .animation(DesignSystem.Animation.smooth, value: indexService.isIndexing)
        .animation(DesignSystem.Animation.smooth, value: indexService.indexedFileCount)
        .onTapGesture {
            showDetails = true
        }
        .popover(isPresented: $showDetails) {
            CodebaseIndexDetailsView(editorViewModel: editorViewModel)
        }
    }
}

struct CodebaseIndexDetailsView: View {
    @StateObject private var indexService = CodebaseIndexService.shared
    var editorViewModel: EditorViewModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codebase Index")
                .font(.headline)
            
            Divider()
            
            if indexService.isIndexing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: indexService.indexProgress)
                    Text("Indexing \(indexService.indexedFileCount) files...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(indexService.lastIndexDate != nil ? "Indexed" : "Not Indexed")
                            .foregroundColor(indexService.lastIndexDate != nil ? .green : .orange)
                    }
                    
                    if let lastIndexDate = indexService.lastIndexDate {
                        HStack {
                            Text("Last indexed:")
                            Spacer()
                            Text(lastIndexDate, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Files indexed:")
                        Spacer()
                        Text("\(indexService.indexedFileCount)")
                    }
                    
                    HStack {
                        Text("Symbols:")
                        Spacer()
                        Text("\(indexService.totalSymbolCount)")
                    }
                }
                .font(.caption)
            }
            
            Divider()
            
            Button("Re-index") {
                if let url = editorViewModel?.rootFolderURL {
                    indexService.indexProject(at: url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 300)
    }
}
