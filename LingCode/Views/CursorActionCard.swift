//
//  CursorActionCard.swift
//  LingCode
//
//  Cursor-style action card component
//

import SwiftUI

struct CursorActionCard: View {
    let action: AIAction
    let streamingContent: String?
    let isStreaming: Bool
    let onOpen: () -> Void
    let onApply: () -> Void
    
    @State private var isHovered = false
    
    private var fileName: String {
        action.filePath ?? action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    private var displayContent: String {
        streamingContent ?? action.fileContent ?? action.result ?? ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerRow
            contentView
        }
        .background(backgroundShape)
        .overlay(overlayShape)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - View Components
    
    private var headerRow: some View {
        HStack(spacing: 10) {
            statusIcon
            fileNameText
            pathText
            Spacer()
            statusBadge
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(headerBackground)
        .overlay(headerOverlay)
        .onHover(perform: handleHover)
    }
    
    private var statusIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: fileIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(fileIconColor)
            
            if isStreaming {
                Circle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -2)
            }
        }
    }
    
    private var fileNameText: some View {
        Text(fileName)
            .font(.system(size: 13, weight: .medium, design: .default))
            .foregroundColor(.primary)
            .lineLimit(1)
    }
    
    @ViewBuilder
    private var pathText: some View {
        if let path = action.filePath {
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            if isStreaming {
                streamingIndicator
                Text("Generating")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text("Ready")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeBackground)
    }
    
    private var streamingIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 4)
                .shadow(color: Color.white.opacity(0.8), radius: 1)
            
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 6, height: 6)
                .scaleEffect(isStreaming ? 1.5 : 1.0)
                .opacity(isStreaming ? 0.0 : 0.8)
                .animation(
                    Animation.easeOut(duration: 0.8)
                        .repeatForever(autoreverses: false),
                    value: isStreaming
                )
        }
    }
    
    private var badgeBackground: some View {
        Capsule()
            .fill(isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0) : Color(red: 0.2, green: 0.8, blue: 0.4))
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        if isHovered {
            HStack(spacing: 4) {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Open file")
                
                Button(action: onApply) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Apply changes")
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .scale(scale: 0.8))
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor).opacity(0.4))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }
    
    private var headerOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: isStreaming ? 1.5 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }
    
    @ViewBuilder
    private var contentView: some View {
        if !displayContent.isEmpty {
            Divider()
                .padding(.horizontal, 12)
            codePreview
        }
    }
    
    private var codePreview: some View {
        ScrollView {
            codeLines
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 300)
        .background(
            Color(NSColor.textBackgroundColor)
                .opacity(0.5)
        )
    }
    
    private var codeLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = displayContent.components(separatedBy: .newlines)
            ForEach(Array(lines.prefix(30).enumerated()), id: \.offset) { index, line in
                codeLine(index: index, line: line)
            }
            if isStreaming {
                streamingCursorLine(lineCount: lines.count)
            }
        }
    }
    
    private func codeLine(index: Int, line: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(index + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func streamingCursorLine(lineCount: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineCount + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3))
                    .frame(width: 2, height: 14)
                
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                    .frame(width: 2, height: 14)
                    .opacity(0.9)
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.8), radius: 2)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: isStreaming
                    )
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
    }
    
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var overlayShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: isStreaming ? 1.5 : 0
            )
            .shadow(
                color: isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2) : Color.clear,
                radius: isStreaming ? 4 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }
    
    // MARK: - Helpers
    
    private func handleHover(_ hovering: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
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
    
    private var fileIconColor: Color {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 1.0, green: 0.4, blue: 0.2)
        case "js", "jsx": return Color(red: 1.0, green: 0.8, blue: 0.0)
        case "ts", "tsx": return Color(red: 0.0, green: 0.5, blue: 0.8)
        case "py": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "json": return Color(red: 0.9, green: 0.9, blue: 0.9)
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

