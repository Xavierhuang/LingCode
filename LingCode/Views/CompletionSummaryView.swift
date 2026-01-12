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
    let currentActions: [AIAction]?
    
    init(
        parsedFiles: [StreamingFileInfo],
        parsedCommands: [ParsedCommand],
        lastUserRequest: String,
        lastMessage: String?,
        currentActions: [AIAction]? = nil
    ) {
        self.parsedFiles = parsedFiles
        self.parsedCommands = parsedCommands
        self.lastUserRequest = lastUserRequest
        self.lastMessage = lastMessage
        self.currentActions = currentActions
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Success header
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 18))
                
                Text("Response Complete")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
            }
            
            Divider()
            
            // Generated comprehensive summary
            if let summaryText = generateComprehensiveSummary() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(summaryText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .padding(.bottom, 6)
            }
            
            // User request
            if !lastUserRequest.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(lastUserRequest)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .padding(.bottom, 6)
            }
            
            // Detailed file summary
            if !parsedFiles.isEmpty {
                detailedFileSummaryView
            } else if !parsedCommands.isEmpty {
                commandSummaryView
            }
            
            // Action summary if available
            if let actions = currentActions, !actions.isEmpty {
                actionSummaryView(actions: actions)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.2), lineWidth: 1.5)
        )
    }
    
    private var detailedFileSummaryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // File count and stats
            HStack(spacing: 12) {
                let totalAdded = parsedFiles.reduce(0) { $0 + $1.addedLines }
                let totalRemoved = parsedFiles.reduce(0) { $0 + $1.removedLines }
                
                if totalAdded > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text("+\(totalAdded)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.green)
                }
                
                if totalRemoved > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 11))
                        Text("-\(totalRemoved)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 11))
                    Text("\(parsedFiles.count) file\(parsedFiles.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.blue)
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // File list
            VStack(alignment: .leading, spacing: 6) {
                Text("Files:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ForEach(parsedFiles.prefix(8)) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.path.hasSuffix(".swift") || file.path.hasSuffix(".py") || file.path.hasSuffix(".js") ? "doc.text.fill" : "doc.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        
                        Text(file.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if file.addedLines > 0 || file.removedLines > 0 {
                            HStack(spacing: 4) {
                                if file.addedLines > 0 {
                                    Text("+\(file.addedLines)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                if file.removedLines > 0 {
                                    Text("-\(file.removedLines)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                if parsedFiles.count > 8 {
                    Text("+ \(parsedFiles.count - 8) more file\(parsedFiles.count - 8 == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                }
            }
        }
    }
    
    private func actionSummaryView(actions: [AIAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 4)
            
            Text("Actions:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            ForEach(actions.prefix(5)) { action in
                HStack(spacing: 8) {
                    Image(systemName: action.status == .completed ? "checkmark.circle.fill" : action.status == .failed ? "xmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundColor(action.status == .completed ? .green : action.status == .failed ? .red : .gray)
                    
                    Text(action.name)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            
            if actions.count > 5 {
                Text("+ \(actions.count - 5) more action\(actions.count - 5 == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 18)
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
    
    private func generateComprehensiveSummary() -> String? {
        var summaryParts: [String] = []
        
        // File generation summary
        if !parsedFiles.isEmpty {
            let totalAdded = parsedFiles.reduce(0) { $0 + $1.addedLines }
            let totalRemoved = parsedFiles.reduce(0) { $0 + $1.removedLines }
            
            if parsedFiles.count == 1 {
                let file = parsedFiles[0]
                if let changeSummary = file.changeSummary, !changeSummary.isEmpty {
                    summaryParts.append(changeSummary)
                } else {
                    summaryParts.append("Generated \(file.name)")
                }
            } else {
                let fileTypes = Set(parsedFiles.map { ($0.path as NSString).pathExtension.lowercased() })
                let typeDescription = fileTypes.isEmpty ? "files" : fileTypes.joined(separator: ", ")
                summaryParts.append("Generated \(parsedFiles.count) \(typeDescription) files")
            }
            
            // Add line change stats
            if totalAdded > 0 || totalRemoved > 0 {
                var changeStats: [String] = []
                if totalAdded > 0 {
                    changeStats.append("+\(totalAdded) lines added")
                }
                if totalRemoved > 0 {
                    changeStats.append("-\(totalRemoved) lines removed")
                }
                if !changeStats.isEmpty {
                    summaryParts.append(changeStats.joined(separator: ", "))
                }
            }
        }
        
        // Command summary
        if !parsedCommands.isEmpty {
            if parsedCommands.count == 1 {
                summaryParts.append("Provided terminal command: \(parsedCommands[0].command)")
            } else {
                summaryParts.append("Provided \(parsedCommands.count) terminal commands")
            }
        }
        
        // Action summary
        if let actions = currentActions, !actions.isEmpty {
            let completed = actions.filter { $0.status == .completed }.count
            if completed > 0 {
                summaryParts.append("Completed \(completed) action\(completed == 1 ? "" : "s")")
            }
        }
        
        // Fallback to message summary
        if summaryParts.isEmpty, let lastMessage = lastMessage, !lastMessage.isEmpty {
            let lines = lastMessage.components(separatedBy: .newlines)
            if let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 150 {
                    return String(trimmed.prefix(150)) + "..."
                }
                return trimmed
            }
        }
        
        return summaryParts.isEmpty ? nil : summaryParts.joined(separator: ". ")
    }
    
    private func generateSummaryText() -> String? {
        return generateComprehensiveSummary()
    }
}

