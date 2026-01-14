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
    let executionOutcome: ExecutionOutcome?
    let expansionResult: WorkspaceEditExpansion.ExpansionResult?
    
    // Deterministic summary built from parsed results
    // WHY DERIVED, NOT GENERATED: Summary is built from observable diffs/actions only
    // No additional AI call - we already have structured data
    private var summary: CompletionSummary? {
        CompletionSummaryBuilder.shared.buildSummary(
            parsedFiles: parsedFiles,
            parsedCommands: parsedCommands,
            currentActions: currentActions,
            executionOutcome: executionOutcome,
            expansionResult: expansionResult
        )
    }
    
    init(
        parsedFiles: [StreamingFileInfo],
        parsedCommands: [ParsedCommand],
        lastUserRequest: String,
        lastMessage: String?,
        currentActions: [AIAction]? = nil,
        executionOutcome: ExecutionOutcome? = nil,
        expansionResult: WorkspaceEditExpansion.ExpansionResult? = nil
    ) {
        self.parsedFiles = parsedFiles
        self.parsedCommands = parsedCommands
        self.lastUserRequest = lastUserRequest
        self.lastMessage = lastMessage
        self.currentActions = currentActions
        self.executionOutcome = executionOutcome
        self.expansionResult = expansionResult
    }
    
    var body: some View {
        // COMPLETION GATE: Only show "Response Complete" if all conditions are met
        // CORE INVARIANT: IDE must NEVER show "Response Complete" unless:
        // 1. HTTP 2xx response
        // 2. Non-empty response body
        // 3. At least one parsed edit/proposal/command
        // 4. At least one change applied OR explicitly proposed
        
        let hasValidCompletion = hasValidCompletionState()
        
        if !hasValidCompletion {
            // Don't show completion view if conditions aren't met
            return AnyView(EmptyView())
        }
        
        return AnyView(completionContentView)
    }
    
    /// Check if response meets all completion requirements
    /// 
    /// COMPLETION GATE: "Response Complete" may ONLY appear if ALL are true:
    /// 1. HTTP response was successful (checked by caller via AIResponseState)
    /// 2. AI response is non-empty (checked by caller)
    /// 3. At least one file was parsed successfully OR at least one command
    /// 4. At least one edit is proposed or applied
    /// 
    /// PARSE FAILURE HANDLING: If parsing yields zero files or zero edits,
    /// do NOT show "Response Complete" - show error state instead
    private func hasValidCompletionState() -> Bool {
        // Condition 3: At least one parsed edit/proposal/command
        let hasParsedOutput = !parsedFiles.isEmpty || !parsedCommands.isEmpty || (currentActions?.isEmpty == false)
        
        // Condition 4: At least one change applied OR explicitly proposed
        // (parsedFiles with content changes count as proposals)
        let hasProposedChanges = !parsedFiles.isEmpty || !parsedCommands.isEmpty
        
        // PARSE FAILURE CHECK: If no parsed output, this is a parse failure
        // Do NOT show "Response Complete" for parse failures
        guard hasParsedOutput && hasProposedChanges else {
            return false
        }
        
        // All conditions must be met
        return true
    }
    
    private var completionContentView: some View {
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
            
            // Deterministic summary (derived from parsed results, not AI-generated)
            if let summary = summary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    // Title
                    Text(summary.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    // Bullet points
                    if !summary.bulletPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(summary.bulletPoints.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(point)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 6)
            } else if let summaryText = generateComprehensiveSummary() {
                // Fallback to old summary generation (for backward compatibility)
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
            } else if let lastMessage = lastMessage, !lastMessage.isEmpty {
                // Show message preview if no files or commands but we have a response
                messagePreviewView
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
            // File count and stats (use summary stats if available, otherwise compute)
            HStack(spacing: 12) {
                let totalAdded = summary?.fileStats?.totalAddedLines ?? parsedFiles.reduce(0) { $0 + $1.addedLines }
                let totalRemoved = summary?.fileStats?.totalRemovedLines ?? parsedFiles.reduce(0) { $0 + $1.removedLines }
                
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
    
    private var messagePreviewView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastMessage = lastMessage, !lastMessage.isEmpty {
                Text("Response:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                // Show first few lines of response
                let lines = lastMessage.components(separatedBy: .newlines)
                let previewLines = Array(lines.prefix(5))
                let preview = previewLines.joined(separator: "\n")
                
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                
                if lines.count > 5 {
                    Text("+ \(lines.count - 5) more line\(lines.count - 5 == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }
}

