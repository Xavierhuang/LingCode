//
//  StatusBarView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct StatusBarView: View {
    @ObservedObject var editorState: EditorState
    let fontSize: CGFloat
    
    var body: some View {
        HStack {
            if let document = editorState.activeDocument {
                HStack(spacing: 16) {
                    HStack(spacing: 12) {
                    Text("Ln \(editorState.cursorPosition > 0 ? lineNumber(for: editorState.cursorPosition, in: document.content) : 1), Col \(columnNumber(for: editorState.cursorPosition, in: document.content))")
                    
                    // Usage indicator
                    UsageIndicatorView()
                }
                        .font(.system(size: 11, design: .monospaced))
                    
                    if !editorState.selectedText.isEmpty {
                        Text("\(editorState.selectedText.count) selected")
                            .font(.system(size: 11))
                    }
                    
                    Text(document.language?.uppercased() ?? "PLAIN TEXT")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Ready")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Text("UTF-8")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("LF")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("Spaces: \(EditorConstants.tabSize)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .frame(height: 24)
    }
    
    private func lineNumber(for position: Int, in text: String) -> Int {
        let beforeCursor = String(text.prefix(position))
        return beforeCursor.components(separatedBy: .newlines).count
    }
    
    private func columnNumber(for position: Int, in text: String) -> Int {
        let beforeCursor = String(text.prefix(position))
        if let lastNewline = beforeCursor.lastIndex(of: "\n") {
            let lineStart = beforeCursor.index(after: lastNewline)
            return text.distance(from: lineStart, to: beforeCursor.endIndex) + 1
        }
        return position + 1
    }
}




