//
//  CursorExperienceView.swift
//  LingCode
//
//  Exact Cursor-style AI coding experience
//

import SwiftUI

/// Main Cursor-style experience view
struct CursorExperienceView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var expandedFiles: Set<String> = []
    @State private var acceptedFiles: Set<String> = []
    @State private var rejectedFiles: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            experienceHeader
            
            Divider()
            
            // Main content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Previous messages (compact)
                        if !viewModel.conversation.messages.isEmpty {
                            ConversationPreview(messages: viewModel.conversation.messages)
                        }
                        
                        // Thinking/Planning section
                        if viewModel.isLoading || !viewModel.thinkingSteps.isEmpty {
                            ThinkingSection(
                                steps: viewModel.thinkingSteps,
                                isLoading: viewModel.isLoading,
                                onStop: { viewModel.cancelGeneration() }
                            )
                        }
                        
                        // File changes section
                        if !viewModel.currentActions.isEmpty {
                            FileChangesSection(
                                actions: viewModel.currentActions,
                                expandedFiles: $expandedFiles,
                                acceptedFiles: $acceptedFiles,
                                rejectedFiles: $rejectedFiles,
                                onOpenFile: { action in
                                    openFile(for: action)
                                },
                                onApply: { action in
                                    applyChange(action)
                                },
                                onReject: { action in
                                    rejectChange(action)
                                }
                            )
                        }
                        
                        // Terminal commands
                        let commands = TerminalExecutionService.shared.extractCommands(
                            from: viewModel.conversation.messages.last(where: { $0.role == .assistant })?.content ?? ""
                        )
                        if !commands.isEmpty {
                            TerminalCommandsSection(
                                commands: commands,
                                workingDirectory: editorViewModel.rootFolderURL
                            )
                        }
                        
                        // Streaming response
                        if viewModel.isLoading {
                            StreamingCodeSection(viewModel: viewModel)
                                .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.thinkingSteps.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Action bar for file changes
            if !viewModel.currentActions.isEmpty && !viewModel.isLoading {
                actionBar
            }
            
            // Input area
            inputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        VStack(spacing: 8) {
            // Context indicator
            if let activeDoc = editorViewModel.editorState.activeDocument {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text(activeDoc.filePath?.lastPathComponent ?? "Untitled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            
            // Input field
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask AI to edit your code...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: {
                    if viewModel.isLoading {
                        viewModel.cancelGeneration()
                    } else {
                        sendMessage()
                    }
                }) {
                    Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.isLoading ? .red : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.isLoading && viewModel.currentInput.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty else { return }
        // FIX: Build context asynchronously
        Task { @MainActor in
            let context = await editorViewModel.getContextForAI()
            let projectURL = editorViewModel.rootFolderURL
            viewModel.sendMessage(context: context, projectURL: projectURL)
        }
    }
    
    // MARK: - Header
    
    private var experienceHeader: some View {
        HStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.headline)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !viewModel.currentActions.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Changes Ready")
                        .font(.headline)
                    Text("\(viewModel.currentActions.count) file\(viewModel.currentActions.count == 1 ? "" : "s") modified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                
                Text("AI Assistant")
                    .font(.headline)
            }
            
            Spacer()
            
            if viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var headerTitle: String {
        if !viewModel.thinkingSteps.isEmpty {
            if let last = viewModel.thinkingSteps.last {
                switch last.type {
                case .planning: return "Planning..."
                case .thinking: return "Thinking..."
                case .action: return "Making Changes..."
                case .result, .complete: return "Completing..."
                }
            }
        }
        return "Processing..."
    }
    
    private var headerSubtitle: String {
        if let last = viewModel.thinkingSteps.last {
            return last.content.prefix(50) + (last.content.count > 50 ? "..." : "")
        }
        return "Analyzing your request..."
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack(spacing: 12) {
            // Status
            let pendingCount = viewModel.currentActions.count - acceptedFiles.count - rejectedFiles.count
            Text("\(pendingCount) pending")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: rejectAll) {
                Label("Reject All", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
            Button(action: acceptAll) {
                Label("Accept All", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func openFile(for action: AIAction) {
        let fileName = action.name.replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
        
        // First check if file is already created
        if let file = viewModel.createdFiles.first(where: { $0.lastPathComponent == fileName }) {
            editorViewModel.openFile(at: file)
            return
        }
        
        // If not, create a temporary preview by writing the content
        if let content = action.result, let projectURL = editorViewModel.rootFolderURL {
            let fileURL = projectURL.appendingPathComponent(fileName)
            
            // Create directory if needed
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            // Write the file
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                editorViewModel.openFile(at: fileURL)
            } catch {
                print("Failed to write file for preview: \(error)")
            }
        }
    }
    
    private func applyChange(_ action: AIAction) {
        acceptedFiles.insert(action.id.uuidString)
        rejectedFiles.remove(action.id.uuidString)
        // Apply the change to the file
        if let content = action.result, let projectURL = editorViewModel.rootFolderURL {
            let fileName = action.name.replacingOccurrences(of: "Create ", with: "")
                .replacingOccurrences(of: "Modify ", with: "")
            let fileURL = projectURL.appendingPathComponent(fileName)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func rejectChange(_ action: AIAction) {
        rejectedFiles.insert(action.id.uuidString)
        acceptedFiles.remove(action.id.uuidString)
    }
    
    private func acceptAll() {
        for action in viewModel.currentActions {
            applyChange(action)
        }
    }
    
    private func rejectAll() {
        for action in viewModel.currentActions {
            rejectedFiles.insert(action.id.uuidString)
        }
    }
}

// MARK: - Thinking Section

struct ThinkingSection: View {
    let steps: [AIThinkingStep]
    let isLoading: Bool
    let onStop: () -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    
                    Text("Thinking Process")
                        .font(.subheadline.bold())
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    
                    Spacer()
                    
                    if isLoading {
                        Button(action: onStop) {
                            Text("Stop")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(Color.purple.opacity(0.1))
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps) { step in
                        ThinkingStepRow(step: step)
                    }
                    
                    if isLoading && steps.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Analyzing your request...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ThinkingStepRow: View {
    let step: AIThinkingStep
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(iconColor)
                .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(stepTitle)
                    .font(.caption.bold())
                    .foregroundColor(iconColor)
                
                Text(step.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status
            if step.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    private var iconName: String {
        switch step.type {
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "brain"
        case .action: return "gearshape"
        case .result: return "doc.text"
        case .complete: return "checkmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch step.type {
        case .planning: return .blue
        case .thinking: return .purple
        case .action: return .orange
        case .result: return .green
        case .complete: return .green
        }
    }
    
    private var stepTitle: String {
        switch step.type {
        case .planning: return "Planning"
        case .thinking: return "Thinking"
        case .action: return "Action"
        case .result: return "Result"
        case .complete: return "Complete"
        }
    }
}

// MARK: - File Changes Section

struct FileChangesSection: View {
    let actions: [AIAction]
    @Binding var expandedFiles: Set<String>
    @Binding var acceptedFiles: Set<String>
    @Binding var rejectedFiles: Set<String>
    let onOpenFile: (AIAction) -> Void
    let onApply: (AIAction) -> Void
    let onReject: (AIAction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.badge.gearshape")
                    .foregroundColor(.orange)
                Text("File Changes")
                    .font(.subheadline.bold())
                
                Spacer()
                
                Text("\(actions.count) file\(actions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            // File cards
            ForEach(actions) { action in
                FileChangeCard(
                    action: action,
                    isExpanded: expandedFiles.contains(action.id.uuidString),
                    isAccepted: acceptedFiles.contains(action.id.uuidString),
                    isRejected: rejectedFiles.contains(action.id.uuidString),
                    onToggle: {
                        if expandedFiles.contains(action.id.uuidString) {
                            expandedFiles.remove(action.id.uuidString)
                        } else {
                            expandedFiles.insert(action.id.uuidString)
                        }
                    },
                    onOpen: { onOpenFile(action) },
                    onApply: { onApply(action) },
                    onReject: { onReject(action) }
                )
            }
        }
    }
}

struct FileChangeCard: View {
    let action: AIAction
    let isExpanded: Bool
    let isAccepted: Bool
    let isRejected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onApply: () -> Void
    let onReject: () -> Void
    
    private var fileName: String {
        action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    private var isNew: Bool {
        action.name.hasPrefix("Create ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    // Status indicator
                    statusIndicator
                    
                    // File icon
                    Image(systemName: fileIcon)
                        .foregroundColor(.accentColor)
                    
                    // File name
                    Text(fileName)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.medium)
                    
                    // Change type badge
                    Text(isNew ? "NEW" : "MODIFIED")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isNew ? Color.green : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    // Decision badge
                    if isAccepted {
                        Text("ACCEPTED")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                    } else if isRejected {
                        Text("REJECTED")
                            .font(.caption2.bold())
                            .foregroundColor(.red)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(backgroundColor)
            
            // Code preview (always show a summary, expand for full view)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Code diff
                    if let content = action.result {
                        CodeDiffView(
                            fileName: fileName,
                            content: content,
                            isNew: isNew
                        )
                    } else {
                        // No content yet
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Loading content...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.textBackgroundColor))
                    }
                }
            } else {
                // Collapsed preview - show line count
                if let content = action.result {
                    let lineCount = content.components(separatedBy: .newlines).count
                    HStack {
                        Text("\(lineCount) lines")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("File created successfully")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            
            // Action buttons - ALWAYS visible
            if !isAccepted && !isRejected {
                Divider()
                HStack(spacing: 12) {
                    Button(action: onOpen) {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Button(action: onReject) {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    
                    Button(action: onApply) {
                        Label("Apply", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            } else if isAccepted {
                // Show accepted state
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Changes applied to file")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                    Button(action: onOpen) {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.green.opacity(0.1))
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        if isAccepted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if isRejected {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        } else {
            switch action.status {
            case .pending:
                Image(systemName: "circle.dotted")
                    .foregroundColor(.gray)
            case .executing:
                ProgressView()
                    .scaleEffect(0.6)
            case .completed:
                Image(systemName: "circle.fill")
                    .foregroundColor(.orange)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var backgroundColor: Color {
        if isAccepted { return Color.green.opacity(0.05) }
        if isRejected { return Color.red.opacity(0.05) }
        return Color(NSColor.controlBackgroundColor)
    }
    
    private var borderColor: Color {
        if isAccepted { return .green.opacity(0.3) }
        if isRejected { return .red.opacity(0.3) }
        return Color.secondary.opacity(0.2)
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces.square"
        case "py": return "terminal"
        case "html": return "chevron.left.slash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        case "md": return "text.justify"
        default: return "doc.fill"
        }
    }
}

// MARK: - Code Diff View

struct CodeDiffView: View {
    let fileName: String
    let content: String
    let isNew: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language header
            HStack {
                Text(languageName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: copyCode) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Code with line numbers
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let lines = content.components(separatedBy: .newlines)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            // Line number
                            Text("\(index + 1)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .trailing)
                                .padding(.trailing, 8)
                            
                            // Diff indicator
                            Text(isNew ? "+" : " ")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(isNew ? .green : .secondary)
                                .frame(width: 16)
                            
                            // Code line
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Spacer()
                        }
                        .padding(.vertical, 1)
                        .background(isNew ? Color.green.opacity(0.1) : Color.clear)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
            .background(Color(NSColor.textBackgroundColor))
        }
    }
    
    private var languageName: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "jsx": return "JavaScript (JSX)"
        case "ts": return "TypeScript"
        case "tsx": return "TypeScript (TSX)"
        case "py": return "Python"
        case "html": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "md": return "Markdown"
        default: return ext.uppercased()
        }
    }
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}

// MARK: - Terminal Commands Section

struct TerminalCommandsSection: View {
    let commands: [ParsedCommand]
    let workingDirectory: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Terminal Commands")
                    .font(.subheadline.bold())
                
                Spacer()
                
                Text("\(commands.count) command\(commands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            
            // Commands
            ForEach(commands) { command in
                TerminalCommandCard(
                    command: command,
                    workingDirectory: workingDirectory
                )
            }
        }
    }
}

struct TerminalCommandCard: View {
    let command: ParsedCommand
    let workingDirectory: URL?
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var isExpanded = false
    @State private var isExecuting = false
    @State private var hasExecuted = false
    @State private var output = ""
    @State private var exitCode: Int32?
    @State private var showConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Command header
            HStack(spacing: 8) {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 8) {
                        statusIcon
                        
                        Text("$ ")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(.green)
                        
                        Text(command.command)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if command.isDestructive {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Quick run button (always visible)
                if !isExecuting && !hasExecuted {
                    Button(action: {
                        if command.isDestructive {
                            showConfirmation = true
                        } else {
                            runCommand()
                            isExpanded = true // Auto-expand when running
                        }
                    }) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color(red: 0.2, green: 0.6, blue: 1.0))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Run command")
                } else if isExecuting {
                    Button(action: cancelExecution) {
                        Image(systemName: "stop.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Stop command")
                }
                
                // Expand/collapse button
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Full command
                    HStack {
                        Text("$ ")
                            .foregroundColor(.green)
                        Text(command.command)
                            .textSelection(.enabled)
                    }
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(6)
                    
                    // Description
                    if let desc = command.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Output
                    if !output.isEmpty || isExecuting {
                        ScrollView {
                            Text(output.isEmpty ? "Running..." : output)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color.black.opacity(0.9))
                        .cornerRadius(6)
                    }
                    
                    // Actions
                    HStack(spacing: 8) {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command.command, forType: .string)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        if isExecuting {
                            Button(action: cancelExecution) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        } else {
                            Button(action: {
                                if command.isDestructive {
                                    showConfirmation = true
                                } else {
                                    runCommand()
                                }
                            }) {
                                Label(hasExecuted ? "Run Again" : "Run", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .alert("Run Destructive Command?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) { runCommand() }
        } message: {
            Text("This command may modify or delete files:\n\n$ \(command.command)")
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        if isExecuting {
            ProgressView()
                .scaleEffect(0.6)
        } else if hasExecuted {
            Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(exitCode == 0 ? .green : .red)
        } else {
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }
    
    private var borderColor: Color {
        if isExecuting { return .orange }
        if hasExecuted {
            return exitCode == 0 ? .green : .red
        }
        return Color.secondary.opacity(0.2)
    }
    
    private func runCommand() {
        isExecuting = true
        output = ""
        
        terminalService.execute(
            command.command,
            workingDirectory: workingDirectory,
            environment: nil,
            onOutput: { out in output += out },
            onError: { err in output += err },
            onComplete: { code in
                isExecuting = false
                hasExecuted = true
                exitCode = code
            }
        )
    }
    
    private func cancelExecution() {
        terminalService.cancel()
        isExecuting = false
        output += "\n[Cancelled]"
    }
}

// MARK: - Streaming Code Section

struct StreamingCodeSection: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var showFullResponse = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button(action: { showFullResponse.toggle() }) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    
                    Text("Generating response...")
                        .font(.subheadline.bold())
                    
                    Spacer()
                    
                    Image(systemName: showFullResponse ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
            
            // Streaming content
            if showFullResponse {
                if let lastMessage = viewModel.conversation.messages.last(where: { $0.role == .assistant }) {
                    ScrollView {
                        Text(lastMessage.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding()
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Conversation Preview

struct ConversationPreview: View {
    let messages: [AIMessage]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.secondary)
                    
                    Text("Conversation (\(messages.count) messages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        CompactMessageRow(message: message)
                    }
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
}

struct CompactMessageRow: View {
    let message: AIMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.caption)
                .foregroundColor(message.role == .user ? .secondary : .accentColor)
                .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(message.role == .user ? "You" : "AI")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                
                Text(message.content.prefix(200) + (message.content.count > 200 ? "..." : ""))
                    .font(.caption)
                    .lineLimit(3)
            }
            
            Spacer()
            
            // Time
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(message.role == .user ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(6)
    }
}

