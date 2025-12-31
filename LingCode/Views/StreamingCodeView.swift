//
//  StreamingCodeView.swift
//  LingCode
//
//  Cursor-style streaming code display - shows code as it's generated
//

import SwiftUI

/// Shows streaming code generation like Cursor
struct StreamingCodeView: View {
    @ObservedObject var viewModel: AIViewModel
    
    @State private var streamingContent: String = ""
    @State private var parsedFiles: [StreamingFile] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Streaming response
            if viewModel.isLoading {
                ForEach(parsedFiles) { file in
                    StreamingFileCard(file: file)
                }
                
                // Show raw streaming if no files parsed yet
                if parsedFiles.isEmpty && !streamingContent.isEmpty {
                    StreamingRawContent(content: streamingContent)
                }
            }
        }
        .onChange(of: viewModel.conversation.messages.last?.content) { _, newContent in
            if let content = newContent, viewModel.isLoading {
                streamingContent = content
                parseStreamingContent(content)
            }
        }
        .onAppear {
            if let lastMessage = viewModel.conversation.messages.last,
               lastMessage.role == .assistant {
                streamingContent = lastMessage.content
                parseStreamingContent(lastMessage.content)
            }
        }
    }
    
    private func parseStreamingContent(_ content: String) {
        // Parse code blocks from streaming content
        let codeBlockPattern = #"```(\w+)?\n([\s\S]*?)```"#
        let filePattern = #"`([^`\n]+\.[a-zA-Z0-9]+)`"#
        
        var newFiles: [StreamingFile] = []
        
        // Find all code blocks
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            let matches = regex.matches(in: content, options: [], range: range)
            
            for match in matches where match.numberOfRanges >= 3 {
                // Get language
                var language = "text"
                if match.numberOfRanges > 1 {
                    let langRange = match.range(at: 1)
                    if langRange.location != NSNotFound,
                       let swiftRange = Range(langRange, in: content) {
                        language = String(content[swiftRange])
                    }
                }
                
                // Get code content
                let codeRange = match.range(at: 2)
                if codeRange.location != NSNotFound,
                   let swiftRange = Range(codeRange, in: content) {
                    let code = String(content[swiftRange])
                    
                    // Try to find file path before this code block
                    let beforeCode = String(content.prefix(codeRange.location))
                    var filePath: String? = nil
                    
                    if let fileRegex = try? NSRegularExpression(pattern: filePattern, options: []) {
                        let beforeRange = NSRange(beforeCode.startIndex..<beforeCode.endIndex, in: beforeCode)
                        if let fileMatch = fileRegex.matches(in: beforeCode, options: [], range: beforeRange).last,
                           fileMatch.numberOfRanges > 1 {
                            let pathRange = fileMatch.range(at: 1)
                            if pathRange.location != NSNotFound,
                               let pathSwiftRange = Range(pathRange, in: beforeCode) {
                                filePath = String(beforeCode[pathSwiftRange])
                            }
                        }
                    }
                    
                    let fileName = filePath ?? "code.\(language)"
                    let fileId = UUID().uuidString
                    
                    // Update or create file
                    if let existingIndex = newFiles.firstIndex(where: { $0.path == filePath }) {
                        newFiles[existingIndex].content = code
                        newFiles[existingIndex].language = language
                    } else {
                        newFiles.append(StreamingFile(
                            id: fileId,
                            path: filePath,
                            name: fileName,
                            language: language,
                            content: code,
                            isStreaming: true
                        ))
                    }
                }
            }
        }
        
        parsedFiles = newFiles
    }
}

// MARK: - Streaming File

struct StreamingFile: Identifiable {
    let id: String
    var path: String?
    var name: String
    var language: String
    var content: String
    var isStreaming: Bool
}

// MARK: - Streaming File Card

struct StreamingFileCard: View {
    let file: StreamingFile
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                
                Text(file.name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                
                if file.isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                            .opacity(0.6)
                            .animation(
                                Animation.easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true),
                                value: file.isStreaming
                            )
                        Text("Streaming...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Streaming code content
            if isExpanded {
                Divider()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(file.content.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .frame(width: 30, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 1)
                        }
                        
                        // Streaming cursor
                        if file.isStreaming {
                            HStack(spacing: 0) {
                                Text("\(file.content.components(separatedBy: .newlines).count + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .frame(width: 30, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 12)
                                    .opacity(0.8)
                                    .animation(
                                        Animation.easeInOut(duration: 1.0)
                                            .repeatForever(autoreverses: true),
                                        value: file.isStreaming
                                    )
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: file.name).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        default: return "doc.fill"
        }
    }
}

// MARK: - Streaming Raw Content

struct StreamingRawContent: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text("Generating response...")
                    .font(.system(size: 12, weight: .medium))
            }
            
            ScrollView {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

