//
//  DiffView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct DiffLine: Identifiable {
    let id = UUID()
    let lineNumber: Int?
    let content: String
    let type: DiffType
    
    enum DiffType {
        case unchanged
        case added
        case removed
        case header
    }
}

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let lines: [DiffLine]
}

class DiffParser {
    static func parse(_ diff: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var currentHeader = ""
        var lineNum = 0
        
        let lines = diff.components(separatedBy: .newlines)
        
        for line in lines {
            if line.hasPrefix("@@") {
                // Save previous hunk
                if !currentLines.isEmpty {
                    hunks.append(DiffHunk(header: currentHeader, lines: currentLines))
                }
                
                // Extract line number from header
                if let range = line.range(of: #"\+(\d+)"#, options: .regularExpression) {
                    let numStr = String(line[range]).dropFirst()
                    lineNum = Int(numStr) ?? 0
                }
                
                currentHeader = line
                currentLines = [DiffLine(lineNumber: nil, content: line, type: .header)]
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentLines.append(DiffLine(lineNumber: lineNum, content: String(line.dropFirst()), type: .added))
                lineNum += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentLines.append(DiffLine(lineNumber: nil, content: String(line.dropFirst()), type: .removed))
            } else if !line.hasPrefix("diff ") && !line.hasPrefix("index ") && !line.hasPrefix("---") && !line.hasPrefix("+++") {
                let cleanLine = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                currentLines.append(DiffLine(lineNumber: lineNum, content: cleanLine, type: .unchanged))
                lineNum += 1
            }
        }
        
        // Save last hunk
        if !currentLines.isEmpty {
            hunks.append(DiffHunk(header: currentHeader, lines: currentLines))
        }
        
        return hunks
    }
}

struct DiffView: View {
    let originalContent: String
    let modifiedContent: String
    let onAccept: () -> Void
    let onReject: () -> Void
    
    @State private var showSideBySide: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                Text("Changes")
                    .font(.headline)
                Spacer()
                
                Picker("View", selection: $showSideBySide) {
                    Text("Side by Side").tag(true)
                    Text("Inline").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Spacer()
                
                Button(action: onReject) {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button(action: onAccept) {
                    Label("Accept", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if showSideBySide {
                SideBySideDiffView(original: originalContent, modified: modifiedContent)
            } else {
                InlineDiffView(original: originalContent, modified: modifiedContent)
            }
        }
    }
}

struct SideBySideDiffView: View {
    let original: String
    let modified: String
    
    var body: some View {
        HSplitView {
            // Original
            VStack(spacing: 0) {
                HStack {
                    Text("Original")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(original.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                Text(line)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Modified
            VStack(spacing: 0) {
                HStack {
                    Text("Modified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(modified.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                Text(line)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct InlineDiffView: View {
    let original: String
    let modified: String
    
    var diffLines: [DiffLine] {
        let originalLines = original.components(separatedBy: .newlines)
        let modifiedLines = modified.components(separatedBy: .newlines)
        
        var result: [DiffLine] = []
        var i = 0
        var j = 0
        
        while i < originalLines.count || j < modifiedLines.count {
            if i < originalLines.count && j < modifiedLines.count && originalLines[i] == modifiedLines[j] {
                result.append(DiffLine(lineNumber: j + 1, content: originalLines[i], type: .unchanged))
                i += 1
                j += 1
            } else {
                // Lines differ
                if i < originalLines.count {
                    result.append(DiffLine(lineNumber: nil, content: originalLines[i], type: .removed))
                    i += 1
                }
                if j < modifiedLines.count {
                    result.append(DiffLine(lineNumber: j + 1, content: modifiedLines[j], type: .added))
                    j += 1
                }
            }
        }
        
        return result
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines) { line in
                    HStack(spacing: 0) {
                        // Line number
                        Text(line.lineNumber.map { String($0) } ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .padding(.trailing, 8)
                        
                        // Indicator
                        Text(indicatorFor(line.type))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(colorFor(line.type))
                            .frame(width: 20)
                        
                        // Content
                        Text(line.content)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 1)
                    .background(backgroundFor(line.type))
                }
            }
            .padding()
        }
    }
    
    private func indicatorFor(_ type: DiffLine.DiffType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        case .header: return "@"
        }
    }
    
    private func colorFor(_ type: DiffLine.DiffType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .secondary
        case .header: return .blue
        }
    }
    
    private func backgroundFor(_ type: DiffLine.DiffType) -> Color {
        switch type {
        case .added: return .green.opacity(0.1)
        case .removed: return .red.opacity(0.1)
        case .unchanged: return .clear
        case .header: return .blue.opacity(0.1)
        }
    }
}

struct InlineCodeDiffView: View {
    let suggestion: String
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("AI Suggestion")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reject (Esc)")
                
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.green)
                .help("Accept (Tab)")
            }
            
            Text(suggestion)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

