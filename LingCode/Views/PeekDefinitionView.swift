//
//  PeekDefinitionView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct PeekDefinitionView: View {
    let definition: Definition
    let onGoToDefinition: () -> Void
    let onClose: () -> Void
    
    @State private var fileContent: String = ""
    @State private var visibleLines: [String] = []
    
    private let contextLines = 5
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "eye")
                VStack(alignment: .leading, spacing: 0) {
                    Text(definition.name)
                        .font(.headline)
                    Text(definition.file.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: onGoToDefinition) {
                    Image(systemName: "arrow.right.square")
                }
                .buttonStyle(PlainButtonStyle())
                .help("Go to Definition")
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Code preview
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                        let lineNumber = definition.line - contextLines + index
                        HStack(spacing: 0) {
                            Text("\(lineNumber)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .padding(.trailing, 8)
                            
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 1)
                        .background(lineNumber == definition.line ? Color.accentColor.opacity(0.2) : Color.clear)
                    }
                }
                .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 500, height: 250)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 5)
        .onAppear {
            loadFileContent()
        }
    }
    
    private func loadFileContent() {
        guard let content = try? String(contentsOf: definition.file, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        let startLine = max(0, definition.line - 1 - contextLines)
        let endLine = min(lines.count, definition.line + contextLines)
        
        visibleLines = Array(lines[startLine..<endLine])
    }
}

