//
//  InlineEditSessionView.swift
//  LingCode
//
//  View for ⌘K inline edit session using EditorCore
//  Shows diff preview and allows accept/reject
//
//  ARCHITECTURE: This view does NOT import EditorCore.
//  All EditorCore access goes through EditorCoreAdapter wrapper types.
//

import SwiftUI
// ARCHITECTURE: No EditorCore import - uses app-level wrapper types only

/// View for inline edit session (⌘K)
/// Observes InlineEditSessionModel and shows diff preview without mutating editor
/// 
/// ARCHITECTURE: Uses app-level wrapper types, not EditorCore types directly.
struct InlineEditSessionView: View {
    @ObservedObject var sessionModel: InlineEditSessionModel
    let onAccept: () -> Void
    let onAcceptAndContinue: () -> Void
    let onReject: () -> Void
    let onCancel: () -> Void
    let onReuseIntent: (String) -> Void // Callback to reuse intent elsewhere
    let onFixSyntaxAndRetry: (String) -> Void // Callback to fix syntax and retry
    let onRetry: () -> Void // Callback to retry with same execution plan
    
    @State private var isTimelineExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("Edit with AI")
                        .font(.headline)
                    Spacer()
                    
                    // Status indicator
                    statusIndicator
                    
                    // Timeline toggle
                    Button(action: { isTimelineExpanded.toggle() }) {
                        Image(systemName: isTimelineExpanded ? "clock.fill" : "clock")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Show session timeline")
                    
                    Text("Cmd+K")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                    
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                // Timeline (collapsible)
                if isTimelineExpanded {
                    timelineView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            Divider()
            
            // Content area
            Group {
                switch sessionModel.status {
                case .thinking:
                    thinkingView
                case .streaming:
                    streamingView
                case .ready:
                    readyView
                case .applied:
                    appliedView
                case .continuing:
                    continuingView
                case .rejected:
                    rejectedView
                case .blocked:
                    blockedView
                case .error(let message):
                    errorView(message: message)
                default:
                    EmptyView()
                }
            }
            // INVARIANT: This view only OBSERVES sessionModel - it never mutates editor content
            .frame(maxHeight: 400)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .frame(maxWidth: 600)
    }
    
    // MARK: - Thinking View (Early Feedback)
    
    private var thinkingView: some View {
        VStack(spacing: 16) {
            // Show provisional intent immediately
            if !sessionModel.streamingText.isEmpty {
                // If we have any text (even partial), show it
                streamingView
            } else {
                // Show analyzing state with intent preview
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Analyzing your request...")
                        .font(.headline)
                    
                    // Show user intent if available (from first proposal or model)
                    if let firstProposal = sessionModel.proposedEdits.first, !firstProposal.intent.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Intent:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(firstProposal.intent)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Timeline View
    
    private var timelineView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session Timeline")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(sessionModel.timeline.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sessionModel.timeline) { event in
                        TimelineEventRow(event: event)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 200)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
    
    // MARK: - Timeline Event Row
    
    private struct TimelineEventRow: View {
        let event: SessionTimelineEvent
        
        private var timeString: String {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            return formatter.string(from: event.timestamp)
        }
        
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                // Icon
                Image(systemName: event.eventType.icon)
                    .font(.caption)
                    .foregroundColor(colorForEventType(event.eventType))
                    .frame(width: 16)
                
                // Time
                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)
                
                // Description
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.description)
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    if let details = event.details {
                        Text(details)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 2)
        }
        
        private func colorForEventType(_ type: SessionTimelineEvent.EventType) -> Color {
            switch type.color {
            case "blue": return .blue
            case "green": return .green
            case "red": return .red
            case "orange": return .orange
            default: return .primary
            }
        }
    }
    
    // MARK: - Status Indicator
    
    private var statusIndicator: some View {
        Group {
            switch sessionModel.status {
            case .thinking:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .streaming:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Generating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            case .applied:
                Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            case .continuing:
                ProgressView()
                    .scaleEffect(0.6)
            case .blocked:
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            case .rejected:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Streaming View
    
    private var streamingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(sessionModel.streamingText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .frame(maxHeight: 300)
    }
    
    // MARK: - Ready View (Diff Preview)
    
    private var readyView: some View {
        VStack(spacing: 0) {
            // Proposed edits list
            if sessionModel.proposedEdits.isEmpty {
                Text("No edits proposed")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sessionModel.proposedEdits) { proposal in
                            EditProposalCard(
                                proposal: proposal,
                                isSelected: sessionModel.isSelected(proposalId: proposal.id),
                                onToggleSelection: {
                                    sessionModel.toggleSelection(proposalId: proposal.id)
                                }
                            )
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
                
                Divider()
                
                // Action buttons with selection controls
                VStack(spacing: 8) {
                    // Selection controls
                    HStack {
                        Button("Select All") {
                            sessionModel.selectAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        
                        Button("Deselect All") {
                            sessionModel.deselectAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        
                        Spacer()
                        
                        let selectedCount = sessionModel.selectedProposalIds.count
                        let totalCount = sessionModel.proposedEdits.count
                        Text("\(selectedCount) of \(totalCount) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .keyboardShortcut(.cancelAction)
                        
                        Spacer()
                        
                        // Reuse Intent button (only shown when session is ready or applied)
                        if sessionModel.status == .ready || sessionModel.status == .applied {
                            Button("Apply Elsewhere") {
                                onReuseIntent(sessionModel.originalIntent)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .help("Apply this same intent to other files")
                        }
                        
                        Button("Reject All") {
                            onReject()
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        
                        // Accept button shows count if not all selected
                        let selectedCount = sessionModel.selectedProposalIds.count
                        let totalCount = sessionModel.proposedEdits.count
                        let buttonTitle = selectedCount == totalCount 
                            ? "Accept All" 
                            : "Accept \(selectedCount)"
                        
                        Button(buttonTitle) {
                            onAccept()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCount == 0)
                        
                        // Apply & Continue button
                        Button("Apply & Continue") {
                            onAcceptAndContinue()
                        }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .buttonStyle(.bordered)
                        .disabled(selectedCount == 0)
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Blocked View
    
    private var blockedView: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                
                Text("This change can't be applied safely yet")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("We found some issues that need to be fixed first")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            Divider()
            
            // Grouped issues
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Can't apply yet (blocking issues)
                    let blockingIssues = sessionModel.validationErrors.flatMap { $0.issues }.filter { $0.severity == .critical }
                    if !blockingIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Can't apply yet")
                                    .font(.headline)
                            }
                            
                            ForEach(Array(blockingIssues.enumerated()), id: \.offset) { _, issue in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.red)
                                    Text(issue.message)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Needs review (warnings)
                    let warningIssues = sessionModel.validationErrors.flatMap { $0.issues }.filter { $0.severity == .warning }
                    if !warningIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Needs review")
                                    .font(.headline)
                            }
                            
                            ForEach(Array(warningIssues.enumerated()), id: \.offset) { _, issue in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.orange)
                                    Text(issue.message)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 200)
            
            Divider()
            
            // Next steps
            VStack(alignment: .leading, spacing: 12) {
                Text("Next steps")
                    .font(.headline)
                
                // Primary action: Fix syntax only
                let hasSyntaxErrors = sessionModel.validationErrors.flatMap { $0.issues }.contains { 
                    if case .syntaxError = $0 { return true }
                    return false
                }
                
                if hasSyntaxErrors {
                    Button(action: {
                        onFixSyntaxAndRetry(sessionModel.originalIntent)
                    }) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                            Text("Fix syntax only and retry")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                
                // Secondary actions
                HStack(spacing: 8) {
                    Button("Review selected changes") {
                        // Scroll to proposals - could be enhanced
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Edit instruction") {
                        // Allow editing instruction
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Applied View
    
    private var appliedView: some View {
        // CORE INVARIANT: IDE may only show "Complete" if at least one edit was applied
        // Check execution outcome to determine if changes were actually made
        if let outcome = sessionModel.executionOutcome, !outcome.changesApplied {
            // No changes were made - show no-op explanation
            return AnyView(noOpView(outcome: outcome))
        } else {
            // Changes were applied - show success
            return AnyView(successView(outcome: sessionModel.executionOutcome))
        }
    }
    
    private func noOpView(outcome: ExecutionOutcome) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text("No changes were applied")
                .font(.headline)
            
            if let explanation = outcome.noOpExplanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if !outcome.validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(outcome.validationIssues.enumerated()), id: \.offset) { _, issue in
                        Text("• \(issue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button("Close") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
        .padding()
    }
    
    private func successView(outcome: ExecutionOutcome?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            
            Text("Changes applied successfully")
                .font(.headline)
            
            if let outcome = outcome {
                VStack(spacing: 4) {
                    Text("\(outcome.filesModified) file\(outcome.filesModified == 1 ? "" : "s") modified")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(outcome.editsApplied) edit\(outcome.editsApplied == 1 ? "" : "s") applied")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Close") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
        .padding()
    }
    
    // MARK: - Continuing View
    
    private var continuingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Continuing edit session...")
                .font(.headline)
            Text("Edits applied, generating more changes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Rejected View
    
    private var rejectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)
            Text("Edits rejected")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // RETRY SEMANTICS: Allow retry using the same execution plan
            // Do NOT reuse partial or empty AI responses
            HStack(spacing: 12) {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                
                Button("Close") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Edit Proposal Card

struct EditProposalCard: View {
    // ARCHITECTURE: Uses app-level wrapper type, not EditorCore type
    let proposal: InlineEditProposal
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selection checkbox and intent
            HStack(alignment: .top, spacing: 8) {
                // Selection checkbox
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                
                // Intent description
                if !proposal.intent.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(proposal.intent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            
            // File header
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption)
                Text(proposal.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("+\(proposal.statistics.addedLines) -\(proposal.statistics.removedLines)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Diff preview (first hunk only for brevity)
            if let firstHunk = proposal.preview.diffHunks.first {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(firstHunk.lines.prefix(10).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 4) {
                            // Line indicator
                            Text(linePrefix(for: line.type))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(lineColor(for: line.type))
                                .frame(width: 12)
                            
                            // Line number
                            Text("\(line.lineNumber)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            
                            // Line content
                            Text(line.content)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(lineColor(for: line.type))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    if firstHunk.lines.count > 10 {
                        Text("... \(firstHunk.lines.count - 10) more lines")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 46)
                    }
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    private func linePrefix(for type: InlineDiffLinePreview.ChangeType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }
    
    private func lineColor(for type: InlineDiffLinePreview.ChangeType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .primary
        }
    }
}
