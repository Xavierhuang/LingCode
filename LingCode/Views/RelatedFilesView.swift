//
//  RelatedFilesView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct RelatedFilesView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var selectedFile: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Related Files")
                    .font(.headline)
                Spacer()
                Button(action: {
                    // Related files are automatically updated when includeRelatedFilesInContext changes
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh related files")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            let relatedFiles: [URL] = {
                guard let document = viewModel.editorState.activeDocument,
                      let filePath = document.filePath,
                      let projectURL = viewModel.rootFolderURL else {
                    return []
                }
                return FileDependencyService.shared.findRelatedFiles(
                    for: filePath,
                    in: projectURL
                )
            }()
            
            if relatedFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No related files found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(relatedFiles, id: \.self, selection: $selectedFile) { fileURL in
                    Button(action: {
                        viewModel.openFile(at: fileURL)
                    }) {
                        HStack {
                            Image(systemName: iconName(for: fileURL))
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileURL.lastPathComponent)
                                    .font(.system(.body, design: .default))
                                    .lineLimit(1)
                                
                                Text(fileURL.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 250)
    }
    
    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "apple.terminal"
        case "js", "jsx": return "curlybraces.square"
        case "ts", "tsx": return "t.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "xml": return "doc.text"
        default: return "doc"
        }
    }
}

