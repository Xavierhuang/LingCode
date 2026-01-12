//
//  CursorStyleDiffView.swift
//  LingCode
//
//  Cursor-style inline diff with green/red highlighting
//

import SwiftUI

/// Cursor-style diff line
struct CursorDiffLine: Identifiable {
    let id = UUID()
    let lineNumber: Int?
    let content: String
    let type: DiffType
    
    enum DiffType {
        case unchanged
        case added
        case removed
        case modified
        case context
    }
}

/// Cursor-style inline diff view
struct CursorStyleDiffView: View {
    let originalContent: String?
    let newContent: String
    let fileName: String
    let onAccept: () -> Void
    let onReject: () -> Void
    
    @State private var showSideBySide = false
    @State private var isHovering = false
    
    private var diffLines: [CursorDiffLine] {
        generateDiff()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                // File icon
                Image(systemName: fileIcon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                
                Text(fileName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                
                // Change badge
                Text(originalContent == nil ? "NEW" : "MODIFIED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(originalContent == nil ? Color.green : Color.orange)
                    .cornerRadius(3)
                
                Spacer()
                
                // View toggle
                Picker("", selection: $showSideBySide) {
                    Text("Inline").tag(false)
                    Text("Side by Side").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                
                // Actions
                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(DiffActionButtonStyle(color: .red))
                .help("Reject changes")
                
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(DiffActionButtonStyle(color: .green))
                .help("Accept changes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Diff content
            if showSideBySide {
                sideBySideView
            } else {
                inlineView
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Inline View
    
    private var inlineView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(diffLines) { line in
                    InlineDiffLineView(line: line)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: line.id)
                }
            }
        }
        .frame(maxHeight: 400)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: diffLines.count)
    }
    
    // MARK: - Side by Side View
    
    private var sideBySideView: some View {
        HStack(spacing: 0) {
            // Original
            VStack(spacing: 0) {
                Text("Original")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(diffLines.filter { $0.type == .removed || $0.type == .unchanged || $0.type == .context }) { line in
                            SideDiffLineView(line: line, side: .left)
                        }
                    }
                }
            }
            
            Divider()
            
            // New
            VStack(spacing: 0) {
                Text("New")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(diffLines.filter { $0.type == .added || $0.type == .unchanged || $0.type == .context }) { line in
                            SideDiffLineView(line: line, side: .right)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }
    
    // MARK: - Diff Generation
    
    private func generateDiff() -> [CursorDiffLine] {
        let newLines = newContent.components(separatedBy: .newlines)
        
        guard let original = originalContent else {
            // All new content
            return newLines.enumerated().map { index, line in
                CursorDiffLine(lineNumber: index + 1, content: line, type: .added)
            }
        }
        
        let originalLines = original.components(separatedBy: .newlines)
        var result: [CursorDiffLine] = []
        
        // Simple line-by-line diff
        let maxLines = max(originalLines.count, newLines.count)
        
        for i in 0..<maxLines {
            let origLine = i < originalLines.count ? originalLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            
            if origLine == newLine {
                if let line = origLine {
                    result.append(CursorDiffLine(lineNumber: i + 1, content: line, type: .unchanged))
                }
            } else {
                if let orig = origLine {
                    result.append(CursorDiffLine(lineNumber: i + 1, content: orig, type: .removed))
                }
                if let new = newLine {
                    result.append(CursorDiffLine(lineNumber: i + 1, content: new, type: .added))
                }
            }
        }
        
        return result
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        default: return "doc.fill"
        }
    }
}

// MARK: - Inline Diff Line View

struct InlineDiffLineView: View {
    let line: CursorDiffLine
    
    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text(line.lineNumber.map { String($0) } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)
            
            // Change indicator
            Text(changeIndicator)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(indicatorColor)
                .frame(width: 14)
            
            // Content
            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(backgroundColor)
    }
    
    private var changeIndicator: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "-"
        case .modified: return "~"
        default: return " "
        }
    }
    
    private var indicatorColor: Color {
        switch line.type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        default: return .clear
        }
    }
    
    private var textColor: Color {
        switch line.type {
        case .added: return Color(red: 0.2, green: 0.6, blue: 0.2)
        case .removed: return Color(red: 0.7, green: 0.2, blue: 0.2)
        default: return .primary
        }
    }
    
    private var backgroundColor: Color {
        switch line.type {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .modified: return Color.orange.opacity(0.1)
        default: return .clear
        }
    }
}

// MARK: - Side Diff Line View

struct SideDiffLineView: View {
    let line: CursorDiffLine
    let side: Side
    
    enum Side { case left, right }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(line.lineNumber.map { String($0) } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 8)
            
            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(backgroundColor)
    }
    
    private var textColor: Color {
        switch (line.type, side) {
        case (.added, .right): return Color(red: 0.2, green: 0.6, blue: 0.2)
        case (.removed, .left): return Color(red: 0.7, green: 0.2, blue: 0.2)
        default: return .primary
        }
    }
    
    private var backgroundColor: Color {
        switch (line.type, side) {
        case (.added, .right): return Color.green.opacity(0.15)
        case (.removed, .left): return Color.red.opacity(0.15)
        default: return .clear
        }
    }
}

// MARK: - Diff Action Button Style

struct DiffActionButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(color)
            .padding(6)
            .background(color.opacity(configuration.isPressed ? 0.3 : 0.1))
            .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    CursorStyleDiffView(
        originalContent: """
        func hello() {
            print("Hello")
        }
        """,
        newContent: """
        func hello() {
            print("Hello, World!")
        }
        
        func goodbye() {
            print("Goodbye!")
        }
        """,
        fileName: "Example.swift",
        onAccept: {},
        onReject: {}
    )
    .frame(width: 600)
    .padding()
}

