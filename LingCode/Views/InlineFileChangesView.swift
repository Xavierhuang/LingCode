//
//  InlineFileChangesView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct InlineFileChangesView: View {
    let actions: [AIAction]
    let createdFiles: [URL]
    let isLoading: Bool
    let onOpenFile: (URL) -> Void
    let onViewDetails: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Creating files...")
                        .font(.caption)
                        .fontWeight(.medium)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(createdFiles.count) file\(createdFiles.count == 1 ? "" : "s") created")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onViewDetails) {
                    Label("View Details", systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // File list
            VStack(spacing: 4) {
                ForEach(actions.prefix(5)) { action in
                    InlineFileRow(
                        action: action,
                        createdFiles: createdFiles,
                        onOpen: { onOpenFile($0) }
                    )
                }
                
                if actions.count > 5 {
                    Text("and \(actions.count - 5) more files...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            // Action buttons
            if !isLoading && !createdFiles.isEmpty {
                HStack(spacing: 8) {
                    Button(action: {
                        for file in createdFiles {
                            onOpenFile(file)
                        }
                    }) {
                        Label("Open All", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: {
                        if let file = createdFiles.first {
                            NSWorkspace.shared.activateFileViewerSelecting([file])
                        }
                    }) {
                        Label("Reveal", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isLoading ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isLoading ? Color.blue.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct InlineFileRow: View {
    let action: AIAction
    let createdFiles: [URL]
    let onOpen: (URL) -> Void
    
    private var fileName: String {
        action.name.replacingOccurrences(of: "Create ", with: "")
    }
    
    private var fileURL: URL? {
        createdFiles.first { $0.lastPathComponent == fileName }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status
            statusIcon
                .frame(width: 16)
            
            // File icon
            Image(systemName: fileIcon)
                .font(.caption)
                .foregroundColor(.accentColor)
            
            // File name
            Text(fileName)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
            
            // Status text
            statusText
            
            // Open button
            if action.status == .completed, let url = fileURL {
                Button(action: { onOpen(url) }) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(action.status == .executing ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch action.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundColor(.gray)
                .font(.caption)
        case .executing:
            ProgressView()
                .scaleEffect(0.5)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        switch action.status {
        case .pending:
            Text("Pending")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .executing:
            Text("Writing...")
                .font(.caption2)
                .foregroundColor(.blue)
        case .completed:
            Text("Done")
                .font(.caption2)
                .foregroundColor(.green)
        case .failed:
            Text("Failed")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
    
    private var fileIcon: String {
        let name = fileName.lowercased()
        if name.hasSuffix(".swift") { return "swift" }
        if name.hasSuffix(".js") || name.hasSuffix(".jsx") { return "curlybraces" }
        if name.hasSuffix(".ts") || name.hasSuffix(".tsx") { return "curlybraces.square" }
        if name.hasSuffix(".py") { return "terminal" }
        if name.hasSuffix(".html") { return "chevron.left.slash.chevron.right" }
        if name.hasSuffix(".css") { return "paintbrush" }
        if name.hasSuffix(".json") { return "doc.text" }
        if name.hasSuffix(".md") { return "text.justify" }
        return "doc.fill"
    }
}



