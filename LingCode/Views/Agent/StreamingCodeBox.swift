//
//  StreamingCodeBox.swift
//  LingCode
//
//  Cursor-like streaming code box with real-time animation
//

import SwiftUI

struct StreamingCodeBox: View {
    let content: String
    let isStreaming: Bool
    let fileName: String?
    
    @State private var displayedLines: [String] = []
    @State private var currentLineIndex: Int = 0
    @State private var isAnimating: Bool = false
    @State private var lastContentHash: Int = 0
    
    private var allLines: [String] {
        content.components(separatedBy: .newlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeaderView
            Divider()
            codeScrollView
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(streamingBorder)
        .onAppear { initializeContent() }
        .onChange(of: content) { oldContent, newContent in
            handleContentUpdate(oldContent: oldContent, newContent: newContent)
        }
    }
    
    // MARK: - Header
    
    private var fileHeaderView: some View {
        HStack(spacing: 6) {
            if let name = fileName, !name.isEmpty {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundColor(fileColor(for: name))
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }
            // Don't show anything if no filename - the parent card already shows status
            Spacer()
            if isStreaming {
                streamingBadge
            } else if !displayedLines.isEmpty {
                Text("\(displayedLines.count) lines")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
    }
    
    private var streamingBadge: some View {
        HStack(spacing: 4) {
            PulseDot(color: .blue, size: 6, minScale: 0.8, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 0.8)
            Text("Writing")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue)
        }
    }
    
    // MARK: - Code Content
    
    private var codeScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if displayedLines.isEmpty && isStreaming {
                        placeholderView
                    } else {
                        ForEach(Array(displayedLines.enumerated()), id: \.offset) { index, line in
                            codeLineRow(index: index, line: line)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        
                        if isStreaming {
                            streamingCursor
                                .id("cursor")
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .animation(.easeOut(duration: 0.1), value: displayedLines.count)
            }
            .frame(minHeight: 60, maxHeight: 250) // minHeight prevents UI jumping during streaming
            .onChange(of: displayedLines.count) { _, newCount in
                withAnimation(.easeOut(duration: 0.1)) {
                    if isStreaming {
                        proxy.scrollTo("cursor", anchor: .bottom)
                    } else if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var placeholderView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .id("placeholder")
    }
    
    private func codeLineRow(index: Int, line: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(index + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 35, alignment: .trailing)
                .padding(.trailing, 8)
            
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .background(isRecentLine(index) ? Color.blue.opacity(0.08) : Color.clear)
        .id(index)
    }
    
    private func isRecentLine(_ index: Int) -> Bool {
        guard isStreaming else { return false }
        return index >= displayedLines.count - 3
    }
    
    private var streamingCursor: some View {
        HStack(spacing: 0) {
            Text("\(displayedLines.count + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 35, alignment: .trailing)
                .padding(.trailing, 8)
            
            BlinkingCursor()
        }
        .padding(.vertical, 1)
    }
    
    private var streamingBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isStreaming ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
            .animation(.easeInOut(duration: 0.3), value: isStreaming)
    }
    
    // MARK: - Animation Logic
    
    private func initializeContent() {
        if !content.isEmpty {
            let lines = allLines
            let initialCount = min(5, lines.count)
            displayedLines = Array(lines.prefix(initialCount))
            currentLineIndex = initialCount
            
            if currentLineIndex < lines.count {
                animateRemainingLines()
            }
        }
        lastContentHash = content.hashValue
    }
    
    private func handleContentUpdate(oldContent: String, newContent: String) {
        let newHash = newContent.hashValue
        guard newHash != lastContentHash else { return }
        lastContentHash = newHash
        
        let newLines = newContent.components(separatedBy: .newlines)
        
        if newLines.count > displayedLines.count {
            currentLineIndex = displayedLines.count
            animateNewLines(allLines: newLines)
        } else if newLines.count < displayedLines.count {
            displayedLines = newLines
            currentLineIndex = newLines.count
        } else {
            displayedLines = newLines
        }
    }
    
    private func animateNewLines(allLines: [String]) {
        guard currentLineIndex < allLines.count else { return }
        guard !isAnimating else { return }
        
        isAnimating = true
        
        let linesToAdd = allLines.count - currentLineIndex
        let batchSize = max(1, linesToAdd / 10)
        
        for i in 0..<linesToAdd {
            let delay = Double(i / batchSize) * 0.02
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let lineIndex = self.currentLineIndex + i
                if lineIndex < allLines.count && self.displayedLines.count <= lineIndex {
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.displayedLines.append(allLines[lineIndex])
                    }
                }
                
                if i == linesToAdd - 1 {
                    self.currentLineIndex = allLines.count
                    self.isAnimating = false
                }
            }
        }
    }
    
    private func animateRemainingLines() {
        let lines = allLines
        guard currentLineIndex < lines.count else { return }
        
        let remaining = lines.count - currentLineIndex
        for i in 0..<remaining {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.015) {
                let idx = self.currentLineIndex + i
                if idx < lines.count && self.displayedLines.count <= idx {
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.displayedLines.append(lines[idx])
                    }
                }
            }
        }
        currentLineIndex = lines.count
    }
    
    // MARK: - Helpers
    
    private func fileColor(for name: String) -> Color {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "html": return .red
        case "css": return .purple
        case "json": return .green
        case "py": return .cyan
        case "go": return .teal
        case "rs": return .orange
        default: return .gray
        }
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var isVisible = true
    
    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(width: 2, height: 14)
            .opacity(isVisible ? 0.9 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible.toggle()
                }
            }
    }
}

// MARK: - File Read Box

struct FileReadBox: View {
    let content: String
    let isStreaming: Bool
    let fileName: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isStreaming ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private var headerView: some View {
        HStack(spacing: 6) {
            if let name = fileName {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }
            Spacer()
            if isStreaming {
                HStack(spacing: 4) {
                    PulseDot(color: .blue, size: 6, minScale: 0.8, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 0.8)
                    Text("Reading")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                }
            } else if !content.isEmpty {
                Text("\(content.components(separatedBy: .newlines).count) lines")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isStreaming && content.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading file content...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } else {
            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 200)
        }
    }
}
