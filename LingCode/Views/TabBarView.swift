//
//  TabBarView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var editorState: EditorState
    let onClose: (UUID) -> Void
    @State private var hoveredTabId: UUID?
    
    /// Check if current file is previewable in browser
    private var canPreviewInBrowser: Bool {
        guard let doc = editorState.activeDocument,
              let path = doc.filePath else { return false }
        let ext = path.pathExtension.lowercased()
        return ["html", "htm", "xhtml", "svg"].contains(ext)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(editorState.documents) { document in
                        TabItemView(
                            document: document,
                            isActive: editorState.activeDocumentId == document.id,
                            isHovered: hoveredTabId == document.id,
                            onSelect: {
                                withAnimation(DesignSystem.Animation.quick) {
                                    editorState.setActiveDocument(document.id)
                                }
                            },
                            onClose: {
                                onClose(document.id)
                            },
                            onHover: { hovering in
                                withAnimation(DesignSystem.Animation.quick) {
                                    hoveredTabId = hovering ? document.id : nil
                                }
                            }
                        )
                    }
                }
            }
            
            Spacer()
            
            // Browser preview button for HTML files
            if canPreviewInBrowser {
                HStack(spacing: 8) {
                    Divider()
                        .frame(height: 20)
                    
                    Button(action: openInBrowser) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                                .font(.system(size: 12))
                            Text("Preview")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Open in Browser")
                }
                .padding(.trailing, 12)
            }
        }
        .frame(height: 36)
        .background(DesignSystem.Colors.secondaryBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func openInBrowser() {
        guard let doc = editorState.activeDocument,
              let path = doc.filePath else { return }
        NSWorkspace.shared.open(path)
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
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button(action: onSelect) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: isActive ? .medium : .regular))
                        .foregroundColor(
                            isActive ? DesignSystem.Colors.textPrimary :
                            DesignSystem.Colors.textSecondary
                        )
                    
                    Text(document.displayName)
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(
                            isActive ? DesignSystem.Colors.textPrimary :
                            DesignSystem.Colors.textSecondary
                        )
                        .lineLimit(1)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity((isActive || isHovered) ? 1.0 : 0.0)
            .help("Close Tab")
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            Group {
                if isActive {
                    DesignSystem.Colors.surfaceElevated
                } else if isHovered {
                    DesignSystem.Colors.surfaceHover
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            // Active indicator line
            Rectangle()
                .fill(DesignSystem.Colors.accent)
                .frame(height: 2)
                .offset(y: 17)
                .opacity(isActive ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            onHover(hovering)
        }
        .animation(DesignSystem.Animation.quick, value: isActive)
        .animation(DesignSystem.Animation.quick, value: isHovered)
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

