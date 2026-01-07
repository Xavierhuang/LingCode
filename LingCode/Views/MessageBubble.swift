//
//  MessageBubble.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct MessageBubble: View {
    let message: AIMessage
    let isStreaming: Bool
    let onCopyCode: (String) -> Void
    var workingDirectory: URL? = nil
    
    @State private var isHovering: Bool = false
    
    init(message: AIMessage, isStreaming: Bool = false, workingDirectory: URL? = nil, onCopyCode: @escaping (String) -> Void) {
        self.message = message
        self.isStreaming = isStreaming
        self.workingDirectory = workingDirectory
        self.onCopyCode = onCopyCode
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer()
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .padding(.top, 4)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content with code block detection
                if message.role == .assistant {
                    VStack(alignment: .leading, spacing: 4) {
                        FormattedMessageView(content: message.content, onCopyCode: onCopyCode, workingDirectory: workingDirectory)
                        
                        // Show streaming indicator
                        if isStreaming && !message.content.isEmpty {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Streaming...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    Text(message.content)
                        .padding(10)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(8)
                }
                
                if !message.content.isEmpty {
                    HStack {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if isHovering {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                Spacer()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct FormattedMessageView: View {
    let content: String
    let onCopyCode: (String) -> Void
    var workingDirectory: URL? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseContent(), id: \.id) { block in
                if block.isTerminalCommand {
                    // Cursor-style terminal command with Run button
                    TerminalCommandBlock(
                        command: block.content,
                        language: block.language,
                        workingDirectory: workingDirectory,
                        onCopy: { onCopyCode(block.content) }
                    )
                } else if block.isCode {
                    CodeBlockView(code: block.content, language: block.language, onCopy: {
                        onCopyCode(block.content)
                    })
                } else {
                    Text(block.content)
                        .font(.body)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func parseContent() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeContent = ""
        var language = ""
        
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block - check if it's a terminal command
                    let isTerminal = isTerminalLanguage(language)
                    blocks.append(ContentBlock(
                        content: codeContent.trimmingCharacters(in: .whitespacesAndNewlines),
                        isCode: true,
                        language: language,
                        isTerminalCommand: isTerminal
                    ))
                    codeContent = ""
                    language = ""
                    inCodeBlock = false
                } else {
                    // Start of code block
                    if !currentText.isEmpty {
                        blocks.append(ContentBlock(content: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isCode: false, language: nil))
                        currentText = ""
                    }
                    language = String(line.dropFirst(3))
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeContent += line + "\n"
            } else {
                currentText += line + "\n"
            }
        }
        
        // Handle remaining content
        if !currentText.isEmpty {
            blocks.append(ContentBlock(content: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isCode: false, language: nil))
        }
        
        return blocks.filter { !$0.content.isEmpty }
    }
    
    private func isTerminalLanguage(_ language: String) -> Bool {
        let terminalLanguages = ["bash", "shell", "sh", "zsh", "terminal", "console", "cmd", "powershell"]
        return terminalLanguages.contains(language.lowercased())
    }
}

