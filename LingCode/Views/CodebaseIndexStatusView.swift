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
        HStack(spacing: 6) {
            if indexService.isIndexing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Indexing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let lastIndexDate = indexService.lastIndexDate {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("\(indexService.indexedFileCount) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Not indexed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
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
