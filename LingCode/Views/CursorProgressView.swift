//
//  CursorProgressView.swift
//  LingCode
//
//  Cursor-style step-by-step progress display
//

import SwiftUI

/// Cursor-style progress view showing step-by-step file creation
struct CursorProgressView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var expandedFiles: Set<UUID> = []
    @State private var showDiffs: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            progressHeader
            
            Divider()
            
            // Step-by-step progress
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Streaming code generation (like Cursor)
                        if viewModel.isLoading {
                            StreamingCodeView(viewModel: viewModel)
                        }
                        
                        // Step 1: Planning
                        if viewModel.isLoading || viewModel.currentPlan != nil {
                            PlanningStepCard(
                                plan: viewModel.currentPlan,
                                isLoading: viewModel.isLoading && viewModel.currentPlan == nil
                            )
                        }
                        
                        // Step 2: Creating Files (with real-time updates)
                        if viewModel.isLoading || !viewModel.currentActions.isEmpty {
                            CreatingFilesStepCard(
                                actions: viewModel.currentActions,
                                isLoading: viewModel.isLoading,
                                expandedFiles: $expandedFiles,
                                showDiffs: $showDiffs,
                                streamingContent: viewModel.isLoading ? (viewModel.conversation.messages.last?.content ?? "") : nil,
                                onOpen: { action in openFile(action) },
                                onApply: { action in applyFile(action) },
                                onReject: { action in rejectFile(action) }
                            )
                        }
                        
                        // Step 3: Complete
                        if !viewModel.isLoading && !viewModel.createdFiles.isEmpty {
                            CompleteStepCard(
                                fileCount: viewModel.createdFiles.count,
                                onOpenAll: openAllFiles
                            )
                        }
                        
                        // Empty state
                        if !viewModel.isLoading && viewModel.currentActions.isEmpty && viewModel.currentPlan == nil && viewModel.createdFiles.isEmpty {
                            EmptyStateView()
                        }
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.currentActions.count) { _, newCount in
                    if let lastAction = viewModel.currentActions.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastAction.id, anchor: .center)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            progressInputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var progressHeader: some View {
        HStack(spacing: 12) {
            // Status with animation
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(progressStatus)
                        .font(.system(size: 14, weight: .semibold))
                } else if !viewModel.createdFiles.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                    Text("\(viewModel.createdFiles.count) changes ready")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .font(.system(size: 16))
                    Text("AI Assistant")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            
            Spacer()
            
            // Stop button
            if viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                        Text("Stop")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }
    
    private var progressStatus: String {
        if !viewModel.currentActions.isEmpty {
            let completed = viewModel.currentActions.filter { $0.status == .completed }.count
            return "Creating files... \(completed)/\(viewModel.currentActions.count)"
        } else if viewModel.currentPlan != nil {
            return "Planning complete, creating files..."
        } else {
            return "Analyzing request..."
        }
    }
    
    // MARK: - Actions
    
    private func openFile(_ action: AIAction) {
        guard let projectURL = editorViewModel.rootFolderURL,
              let filePath = action.filePath else { return }
        let fileURL = projectURL.appendingPathComponent(filePath)
        editorViewModel.openFile(at: fileURL)
    }
    
    private func applyFile(_ action: AIAction) {
        guard let content = action.fileContent ?? action.result,
              let projectURL = editorViewModel.rootFolderURL,
              let filePath = action.filePath else { return }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let directory = fileURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            action.status = .completed
            editorViewModel.openFile(at: fileURL)
        } catch {
            action.status = .failed
            action.error = error.localizedDescription
        }
    }
    
    private func rejectFile(_ action: AIAction) {
        action.status = .failed
    }
    
    private func openAllFiles() {
        for fileURL in viewModel.createdFiles {
            editorViewModel.openFile(at: fileURL)
        }
    }
    
    // MARK: - Input Area
    
    private var progressInputArea: some View {
        VStack(spacing: 8) {
            // Context file indicator
            if let file = editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent {
                HStack {
                    Image(systemName: "doc")
                        .font(.system(size: 10))
                    Text(file)
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal, 12)
            }
            
            // Input field
            HStack(spacing: 10) {
                Button(action: {}) {
                    Image(systemName: "at")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                TextField("Ask AI to create files or modify code...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .onSubmit {
                        if !viewModel.currentInput.isEmpty {
                            sendMessage()
                        }
                    }
                
                Button(action: {
                    if viewModel.isLoading {
                        viewModel.cancelGeneration()
                    } else {
                        sendMessage()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isLoading ? Color.red : (viewModel.currentInput.isEmpty ? Color.gray : Color.accentColor))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.isLoading && viewModel.currentInput.isEmpty)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty else { return }
        // FIX: Build context asynchronously
        Task { @MainActor in
            let context = await editorViewModel.getContextForAI() ?? ""
            viewModel.sendMessage(context: context, projectURL: editorViewModel.rootFolderURL)
        }
    }
}

// MARK: - Planning Step Card

struct PlanningStepCard: View {
    let plan: AIPlan?
    let isLoading: Bool
    @State private var visibleSteps: Set<Int> = []

    var body: some View {
        ProgressStepCard(
            stepNumber: 1,
            title: "Planning",
            icon: "list.bullet.rectangle",
            iconColor: .blue,
            isComplete: plan != nil,
            isLoading: isLoading
        ) {
            planContent
        }
    }

    @ViewBuilder
    private var planContent: some View {
        if let plan = plan {
            planSteps(plan: plan)
        } else if isLoading {
            loadingView
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func planSteps(plan: AIPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                planStepRow(index: index, step: step)
            }
        }
    }

    @ViewBuilder
    private func planStepRow(index: Int, step: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
                .scaleEffect(visibleSteps.contains(index) ? 1.0 : 0.5)
            Text(step)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .opacity(visibleSteps.contains(index) ? 1.0 : 0)
        .offset(x: visibleSteps.contains(index) ? 0 : -20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    _ = visibleSteps.insert(index)
                }
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Analyzing your request...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Creating Files Step Card

struct CreatingFilesStepCard: View {
    let actions: [AIAction]
    let isLoading: Bool
    @Binding var expandedFiles: Set<UUID>
    @Binding var showDiffs: Set<UUID>
    let streamingContent: String?
    let onOpen: (AIAction) -> Void
    let onApply: (AIAction) -> Void
    let onReject: (AIAction) -> Void
    
    @State private var streamingFiles: [String: String] = [:] // filePath -> content
    
    private var completedCount: Int {
        actions.filter { $0.status == .completed }.count
    }
    
    var body: some View {
        ProgressStepCard(
            stepNumber: 2,
            title: "Creating Files",
            icon: "doc.badge.plus",
            iconColor: .orange,
            isComplete: !isLoading && completedCount == actions.count,
            isLoading: isLoading,
            progress: actions.isEmpty ? nil : Double(completedCount) / Double(actions.count)
        ) {
            Group {
                if actions.isEmpty && isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Preparing files...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(actions) { action in
                            CursorFileChangeCard(
                                action: action,
                                isExpanded: expandedFiles.contains(action.id),
                                showDiff: showDiffs.contains(action.id),
                                streamingContent: streamingFiles[action.filePath ?? ""],
                                isStreaming: isLoading && action.status == .executing,
                                onToggle: {
                                    if expandedFiles.contains(action.id) {
                                        expandedFiles.remove(action.id)
                                    } else {
                                        expandedFiles.insert(action.id)
                                    }
                                },
                                onToggleDiff: {
                                    if showDiffs.contains(action.id) {
                                        showDiffs.remove(action.id)
                                    } else {
                                        showDiffs.insert(action.id)
                                    }
                                },
                                onOpen: { onOpen(action) },
                                onApply: { onApply(action) },
                                onReject: { onReject(action) }
                            )
                            .id(action.id)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .onChange(of: streamingContent) { _, newContent in
            if let content = newContent {
                parseStreamingContent(content)
            }
        }
    }
    
    private func parseStreamingContent(_ content: String) {
        // Parse code blocks and update streaming files
        let codeBlockPattern = #"```(\w+)?\n([\s\S]*?)```"#
        let filePattern = #"`([^`\n]+\.[a-zA-Z0-9]+)`"#
        
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            let matches = regex.matches(in: content, options: [], range: range)
            
            for match in matches where match.numberOfRanges >= 3 {
                let codeRange = match.range(at: 2)
                if codeRange.location != NSNotFound,
                   let swiftRange = Range(codeRange, in: content) {
                    let code = String(content[swiftRange])
                    
                    // Find file path before this code block
                    let beforeCode = String(content.prefix(codeRange.location))
                    
                    if let fileRegex = try? NSRegularExpression(pattern: filePattern, options: []) {
                        let beforeRange = NSRange(beforeCode.startIndex..<beforeCode.endIndex, in: beforeCode)
                        if let fileMatch = fileRegex.matches(in: beforeCode, options: [], range: beforeRange).last,
                           fileMatch.numberOfRanges > 1 {
                            let pathRange = fileMatch.range(at: 1)
                            if pathRange.location != NSNotFound,
                               let pathSwiftRange = Range(pathRange, in: beforeCode) {
                                let filePath = String(beforeCode[pathSwiftRange])
                                streamingFiles[filePath] = code
                                
                                // Update action content in real-time
                                if let action = actions.first(where: { $0.filePath == filePath }) {
                                    action.fileContent = code
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Complete Step Card

struct CompleteStepCard: View {
    let fileCount: Int
    let onOpenAll: () -> Void
    
    var body: some View {
        ProgressStepCard(
            stepNumber: 3,
            title: "Complete",
            icon: "checkmark.seal.fill",
            iconColor: .green,
            isComplete: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(fileCount) file\(fileCount == 1 ? "" : "s") created successfully")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Button(action: onOpenAll) {
                    Label("Open All Files", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Step Card

struct ProgressStepCard<Content: View>: View {
    let stepNumber: Int
    let title: String
    let icon: String
    let iconColor: Color
    let isComplete: Bool
    let isLoading: Bool
    let progress: Double?
    @ViewBuilder let content: Content

    @State private var checkmarkScale: CGFloat = 0.8
    @State private var isVisible = false

    init(
        stepNumber: Int,
        title: String,
        icon: String,
        iconColor: Color,
        isComplete: Bool = false,
        isLoading: Bool = false,
        progress: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.stepNumber = stepNumber
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.isComplete = isComplete
        self.isLoading = isLoading
        self.progress = progress
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step header
            HStack(spacing: 12) {
                // Step number badge with animation
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .scaleEffect(isComplete ? 1.1 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isComplete)

                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(iconColor)
                            .scaleEffect(checkmarkScale)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: checkmarkScale)
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(iconColor)
                    } else {
                        Text("\(stepNumber)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))

                    if let progress = progress {
                        ProgressView(value: progress)
                            .frame(width: 200)
                            .tint(iconColor)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(isLoading ? .linear(duration: 2).repeatForever(autoreverses: false) : .default, value: isLoading)
            }

            // Step content with stagger animation
            if isComplete || isLoading {
                content
                    .padding(.leading, 44)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity).combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(iconColor.opacity(isComplete ? 0.5 : 0.3), lineWidth: isComplete ? 2 : 1)
                )
        )
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isComplete)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isLoading)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isVisible)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(stepNumber - 1) * 0.1)) {
                isVisible = true
            }
        }
        .onChange(of: isComplete) { _, newValue in
            if newValue {
                // Pulse animation when completed
                checkmarkScale = 1.3
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    checkmarkScale = 1.0
                }
            }
        }
    }
}

// MARK: - Cursor File Change Card

struct CursorFileChangeCard: View {
    let action: AIAction
    let isExpanded: Bool
    let showDiff: Bool
    let streamingContent: String?
    let isStreaming: Bool
    let onToggle: () -> Void
    let onToggleDiff: () -> Void
    let onOpen: () -> Void
    let onApply: () -> Void
    let onReject: () -> Void
    
    private var fileName: String {
        action.filePath ?? action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // File header
            HStack(spacing: 10) {
                // Status icon
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
                
                // File icon
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                
                // File name
                Text(fileName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                
                // Status badge
                HStack(spacing: 4) {
                    if isStreaming {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.8)
                            .animation(
                                Animation.easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true),
                                value: isStreaming
                            )
                    }
                    Text(isStreaming ? "STREAMING" : statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isStreaming ? Color.blue : statusColor)
                .cornerRadius(4)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 6) {
                    Button(action: onOpen) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    
                    if action.status == .pending || action.status == .executing {
                        Button(action: onReject) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.red)
                        
                        Button(action: onApply) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.green)
                    }
                    
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Expanded content
            if isExpanded {
                Divider()
                
                // Use streaming content if available, otherwise use fileContent or result
                let displayContent = streamingContent ?? action.fileContent ?? action.result
                
                if showDiff, let content = displayContent {
                    // Show diff view
                    CursorStyleDiffView(
                        originalContent: nil,
                        newContent: content,
                        fileName: fileName,
                        onAccept: onApply,
                        onReject: onReject
                    )
                    .frame(maxHeight: 300)
                } else if let content = displayContent {
                    // Show streaming code preview
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            let lines = content.components(separatedBy: .newlines)
                            ForEach(Array(lines.prefix(30).enumerated()), id: \.offset) { index, line in
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
                            
                            // Streaming cursor indicator
                            if isStreaming {
                                HStack(spacing: 0) {
                                    Text("\(lines.count + 1)")
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
                                            value: isStreaming
                                        )
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(NSColor.textBackgroundColor))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var statusIcon: String {
        switch action.status {
        case .pending: return "circle.dotted"
        case .executing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch action.status {
        case .pending: return .orange
        case .executing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private var statusText: String {
        switch action.status {
        case .pending: return "NEW"
        case .executing: return "CREATING"
        case .completed: return "CREATED"
        case .failed: return "FAILED"
        }
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        default: return "doc.fill"
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.purple.opacity(0.6))
            
            Text("AI Assistant Ready")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Ask me to create files, modify code, or help with your project")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.blue)
                    Text("Type your request in the input below")
                        .font(.system(size: 12))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.orange)
                    Text("Watch files appear as they're created")
                        .font(.system(size: 12))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "3.circle.fill")
                        .foregroundColor(.green)
                    Text("Review and apply changes")
                        .font(.system(size: 12))
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

