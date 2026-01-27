//
//  FileMentionPickerView.swift
//  LingCode
//
//  Enhanced @file mention picker with search and file browser
//

import SwiftUI

struct FileMentionPickerView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    let onSelect: (String) -> Void
    @Binding var isVisible: Bool
    
    @State private var searchQuery: String = ""
    @State private var selectedPath: String?
    
    private var filteredFiles: [URL] {
        guard let projectURL = editorViewModel.rootFolderURL else { return [] }
        
        var files: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        for case let fileURL as URL in enumerator {
            if !fileURL.hasDirectoryPath {
                let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                
                if searchQuery.isEmpty || relativePath.lowercased().contains(searchQuery.lowercased()) {
                    files.append(fileURL)
                }
            }
        }
        
        return files.sorted { $0.path < $1.path }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // File list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredFiles.prefix(50), id: \.path) { fileURL in
                        FileMentionRow(
                            fileURL: fileURL,
                            projectURL: editorViewModel.rootFolderURL,
                            isSelected: selectedPath == fileURL.path,
                            onSelect: {
                                let relativePath = fileURL.path.replacingOccurrences(
                                    of: (editorViewModel.rootFolderURL?.path ?? "") + "/",
                                    with: ""
                                )
                                onSelect(relativePath)
                                isVisible = false
                            }
                        )
                    }
                }
            }
        }
        .frame(width: 400, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct FileMentionRow: View {
    let fileURL: URL
    let projectURL: URL?
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var relativePath: String {
        guard let projectURL = projectURL else { return fileURL.lastPathComponent }
        return fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
    }
    
    private var icon: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces.square"
        case "py": return "terminal"
        case "rs": return "gear"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "html": return "chevron.left.slash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        case "md": return "text.justify"
        default: return "doc.fill"
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text((relativePath as NSString).deletingLastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
