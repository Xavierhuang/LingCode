//
//  TabBarView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct TabBarView: View {
    @ObservedObject var editorState: EditorState
    let onClose: (UUID) -> Void
    @State private var hoveredTabId: UUID?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(editorState.documents) { document in
                    TabItemView(
                        document: document,
                        isActive: editorState.activeDocumentId == document.id,
                        isHovered: hoveredTabId == document.id,
                        onSelect: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                editorState.setActiveDocument(document.id)
                            }
                        },
                        onClose: {
                            onClose(document.id)
                        },
                        onHover: { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                hoveredTabId = hovering ? document.id : nil
                            }
                        }
                    )
                }
            }
        }
        .frame(height: 36)
        .background(
            Color(NSColor.controlBackgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
        )
    }
}

struct TabItemView: View {
    let document: Document
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? .primary : .secondary)
                    
                    Text(document.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity((isActive || isHovered) ? 1.0 : 0.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if isActive {
                    Color(NSColor.selectedContentBackgroundColor)
                } else if isHovered {
                    Color(NSColor.controlBackgroundColor).opacity(0.5)
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            // Active indicator line
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .offset(y: 17)
                .opacity(isActive ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            onHover(hovering)
        }
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button("Close") {
                onClose()
            }
            Button("Close Others") {
                // TODO: Implement close others
            }
            Button("Close All") {
                // TODO: Implement close all
            }
        }
    }
    
    private var iconName: String {
        guard let filePath = document.filePath else { return "doc" }
        let ext = filePath.pathExtension.lowercased()
        
        switch ext {
        case "swift": return "swift"
        case "py": return "apple.terminal"
        case "js", "jsx": return "curlybraces.square"
        case "ts", "tsx": return "t.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "curlybraces"
        case "md": return "doc.text"
        default: return "doc"
        }
    }
}

