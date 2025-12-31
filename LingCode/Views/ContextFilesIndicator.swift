//
//  ContextFilesIndicator.swift
//  LingCode
//
//  Shows which files are included in AI context
//

import SwiftUI

/// Indicator showing which files are in AI context
struct ContextFilesIndicator: View {
    let files: [String]
    @State private var isExpanded = false
    
    var body: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text("\(files.count) file\(files.count == 1 ? "" : "s") in context")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files, id: \.self) { file in
                            HStack(spacing: 4) {
                                Image(systemName: fileIcon(for: file))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.7))
                                Text(file)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 16)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
    }
    
    private func fileIcon(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        case "html": return "globe"
        case "css": return "paintbrush"
        case "md": return "doc.text"
        default: return "doc"
        }
    }
}







