//
//  FileReviewView.swift
//  LingCode
//
//  Review view for all file changes (Cursor-style)
//

import SwiftUI

struct FileReviewView: View {
    let files: [StreamingFileInfo]
    let projectURL: URL?
    let onApply: (StreamingFileInfo) -> Void
    let onReject: (StreamingFileInfo) -> Void
    
    @State private var selectedFile: StreamingFileInfo?
    @State private var originalContents: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            HSplitView {
                // File list
                List(selection: $selectedFile) {
                    ForEach(files) { file in
                        HStack {
                            Image(systemName: iconForFile(file.path))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((file.path as NSString).lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Text((file.path as NSString).deletingLastPathComponent)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .tag(file)
                    }
                }
                .frame(minWidth: 250, idealWidth: 300)
                
                // File diff view
                if let file = selectedFile ?? files.first {
                    CursorStyleDiffView(
                        originalContent: originalContents[file.id]?.isEmpty == false ? originalContents[file.id] : nil,
                        newContent: file.content,
                        fileName: (file.path as NSString).lastPathComponent,
                        onAccept: {
                            onApply(file)
                            if files.count == 1 {
                                dismiss()
                            }
                        },
                        onReject: {
                            onReject(file)
                            if files.count == 1 {
                                dismiss()
                            }
                        }
                    )
                } else {
                    VStack {
                        Text("Select a file to review")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Review Changes (\(files.count) file\(files.count == 1 ? "" : "s"))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply All") {
                        files.forEach { onApply($0) }
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadOriginalContents()
        }
    }
    
    private func loadOriginalContents() {
        guard let projectURL = projectURL else { return }
        for file in files {
            let fileURL = projectURL.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                originalContents[file.id] = content
            } else {
                originalContents[file.id] = ""
            }
        }
    }
    
    private func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "js"
        case "ts", "tsx": return "ts"
        case "py": return "python"
        case "md": return "doc.text"
        case "json": return "curlybraces"
        case "html": return "html"
        case "css": return "css"
        default: return "doc"
        }
    }
}
