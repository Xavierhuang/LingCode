//
//  CompletionSummaryView.swift
//  LingCode
//
//  Completion summary view component
//

import SwiftUI

struct CompletionSummaryView: View {
    let parsedFiles: [StreamingFileInfo]
    let parsedCommands: [ParsedCommand]
    let lastUserRequest: String
    let lastMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                
                Text(parsedFiles.isEmpty ? "Response Complete" : "Generation Complete")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
            }
            
            Divider()
            
            // Generated summary description
            if let summaryText = generateSummaryText() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
            }
            
            // User request summary
            if !lastUserRequest.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(lastUserRequest)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
                .padding(.bottom, 4)
            }
            
            // Summary stats
            if !parsedFiles.isEmpty {
                fileSummaryView
            } else if !parsedCommands.isEmpty {
                commandSummaryView
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var fileSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File list
            VStack(alignment: .leading, spacing: 4) {
                Text("Files Modified:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ForEach(parsedFiles.prefix(5)) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                        Text(file.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                
                if parsedFiles.count > 5 {
                    Text("+ \(parsedFiles.count - 5) more files")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            let totalAdded = parsedFiles.reduce(0) { $0 + $1.addedLines }
            let totalRemoved = parsedFiles.reduce(0) { $0 + $1.removedLines }
            
            if totalAdded > 0 || totalRemoved > 0 {
                Divider()
                HStack {
                    if totalAdded > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                            Text("+\(totalAdded) lines")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.green)
                    }
                    
                    if totalRemoved > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 10))
                            Text("-\(totalRemoved) lines")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    private var commandSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commands Provided:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            ForEach(parsedCommands.prefix(3)) { command in
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text(command.command)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
            }
            
            if parsedCommands.count > 3 {
                Text("+ \(parsedCommands.count - 3) more commands")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func generateSummaryText() -> String? {
        // Generate a human-readable summary of what was done
        if !parsedFiles.isEmpty {
            if parsedFiles.count == 1 {
                let file = parsedFiles[0]
                if let summary = file.changeSummary, !summary.isEmpty {
                    return summary
                }
                return "Generated \(file.name)"
            } else {
                // Multiple files
                let fileNames = parsedFiles.prefix(2).map { $0.name }.joined(separator: ", ")
                if parsedFiles.count == 2 {
                    return "Generated \(fileNames)"
                } else {
                    return "Generated \(fileNames) and \(parsedFiles.count - 2) more file\(parsedFiles.count - 2 == 1 ? "" : "s")"
                }
            }
        } else if !parsedCommands.isEmpty {
            if parsedCommands.count == 1 {
                return "Provided terminal command: \(parsedCommands[0].command)"
            } else {
                return "Provided \(parsedCommands.count) terminal commands"
            }
        } else if let lastMessage = lastMessage, !lastMessage.isEmpty {
            // Try to extract a brief summary from the response
            let lines = lastMessage.components(separatedBy: .newlines)
            if let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 100 {
                    return String(trimmed.prefix(100)) + "..."
                }
                return trimmed
            }
        }
        
        return nil
    }
}

