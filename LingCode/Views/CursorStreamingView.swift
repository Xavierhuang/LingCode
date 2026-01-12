//
//  CursorStreamingView.swift
//  LingCode
//
//  Exact Cursor-style streaming experience
//

import SwiftUI
import AppKit
@preconcurrency import UniformTypeIdentifiers

/// Cursor-style streaming view - shows everything as it happens
struct CursorStreamingView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    init(viewModel: AIViewModel, editorViewModel: EditorViewModel) {
        self.viewModel = viewModel
        self.editorViewModel = editorViewModel
    }
    
    @State private var streamingText: String = ""
    @State private var parsedFiles: [StreamingFileInfo] = []
    @State private var expandedFiles: Set<String> = []
    @State private var showGraphiteView = false
    @State private var selectedFileForGraphite: StreamingFileInfo?
    @State private var lastUserRequest: String = ""
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var parsedCommands: [ParsedCommand] = []
    @State private var isThinkingExpanded: Bool = false // Track if thinking process is expanded
    private let terminalService = TerminalExecutionService.shared
    @State private var activeMentions: [Mention] = []
    private let contentParser = StreamingContentParser.shared
    private let fileActionHandler = FileActionHandler.shared
    
    // Debouncing for parsing to reduce CPU usage
    private let parseDebouncer = ParseDebouncer(debounceInterval: 200_000_000) // 200ms
    
    var body: some View {
        VStack(spacing: 0) {
            StreamingHeaderView(viewModel: viewModel)
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1)
            
            streamingContent
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1)
            
            // Apply button - shows when generation is complete and there are files to apply
            if !viewModel.isLoading && !parsedFiles.isEmpty && hasFilesToApply {
                applyButtonBar
            }
            
            StreamingInputView(
                viewModel: viewModel,
                editorViewModel: editorViewModel,
                activeMentions: $activeMentions,
                onSendMessage: sendMessage,
                onImageDrop: { providers in
                    return await handleImageDrop(providers: providers)
                }
            )
        }
        .background(DesignSystem.Colors.primaryBackground)
        .onChange(of: viewModel.conversation.messages.last?.content) { _, newContent in
            // Defer state changes to avoid publishing during view updates
            Task { @MainActor in
                handleMessageChange(newContent)
            }
        }
        .onChange(of: viewModel.currentActions) { _, newActions in
            // Defer state changes to avoid publishing during view updates
            Task { @MainActor in
                handleActionsChange(newActions)
            }
        }
        .onChange(of: viewModel.isGeneratingProject) { wasGenerating, isGenerating in
            // When project generation completes, auto-apply all generated files
            if wasGenerating && !isGenerating {
                // Defer state changes outside of view update cycle
                Task { @MainActor in
                    // Small delay to ensure files are fully parsed
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    if !self.parsedFiles.isEmpty {
                        self.autoApplyAllFiles()
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
            // Auto-apply when loading completes (generation finished)
            // Only apply if auto-execute is enabled AND files are complete and not empty
            if wasLoading && !isLoading && viewModel.autoExecuteCode && !parsedFiles.isEmpty {
                // Defer state changes outside of view update cycle
                Task { @MainActor in
                    // Wait to ensure all streaming content is complete
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds to ensure completion
                    
                    // Re-parse to get final content
                    let parser = StreamingContentParser.shared
                    let finalFiles = parser.parseContent(
                        viewModel.conversation.messages.last?.content ?? "",
                        isLoading: false,
                        projectURL: editorViewModel.rootFolderURL,
                        actions: viewModel.currentActions
                    )
                    
                    // Only update if we got valid files
                    if !finalFiles.isEmpty {
                        // Verify all files have substantial content before applying
                        let validFiles = finalFiles.filter { file in
                            let trimmed = file.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            return !trimmed.isEmpty && trimmed.count > 20 // Minimum 20 characters
                        }
                        
                        if !validFiles.isEmpty {
                            print("✅ Auto-applying \(validFiles.count) files (auto-execute enabled)")
                            self.parsedFiles = validFiles
                            // Now apply only complete files (with safety checks)
                            self.autoApplyAllFiles()
                        } else {
                            print("⚠️ No valid files to auto-apply - all files are too small or empty")
                        }
                    } else {
                        print("⚠️ Re-parsing returned no files - skipping auto-apply to prevent code deletion")
                    }
                }
            } else if wasLoading && !isLoading && !viewModel.autoExecuteCode {
                print("ℹ️ Generation complete. Auto-execute is disabled - files will not be automatically applied.")
                print("   Enable 'Auto Execute' in the menu to automatically apply generated files.")
            }
        }
        .onAppear(perform: handleAppear)
        .sheet(isPresented: $showGraphiteView) {
            if !parsedFiles.isEmpty {
                GraphiteStackView(
                    changes: parsedFiles.map { file in
                        CodeChange(
                            id: UUID(),
                            filePath: file.path,
                            fileName: file.name,
                            operationType: .update,
                            originalContent: nil,
                            newContent: file.content,
                            lineRange: nil,
                            language: file.language
                        )
                    }
                )
            }
        }
    }
    
    // MARK: - View Components
    
    
    private var streamingContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    // Empty state
                    if !viewModel.isLoading && parsedFiles.isEmpty && parsedCommands.isEmpty && streamingText.isEmpty {
                        emptyStateView
                    } else {
                        // Terminal commands view
                        if !parsedCommands.isEmpty {
                            TerminalCommandsView(
                                commands: parsedCommands,
                                workingDirectory: editorViewModel.rootFolderURL,
                                onRunAll: runAllCommands
                            )
                        }
                        
                        contentVStack
                            .id("streaming")
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            // Don't auto-scroll during streaming - let user scroll freely
            // Only scroll when new files appear (not on every content update)
            .onChange(of: parsedFiles.count) { oldCount, newCount in
                // Only scroll to new file if it's the first one
                if oldCount == 0 && newCount == 1, let firstFile = parsedFiles.first {
                    // Defer state changes to avoid publishing during view updates
                    Task { @MainActor in
                        // Auto-open the first file in the editor for preview
                        self.openFile(firstFile)
                        // Gentle scroll to show the new file
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            proxy.scrollTo(firstFile.id, anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: parsedCommands.count) { _, _ in
                if let lastCommand = parsedCommands.last {
                    // Defer state changes to avoid publishing during view updates
                    Task { @MainActor in
                        // Debounce scroll to avoid interrupting user
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            proxy.scrollTo(lastCommand.id.uuidString, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("AI Assistant Ready")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Ask me anything or request code changes")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
    
    private func runAllCommands() {
        // Run all non-destructive commands sequentially
        let safeCommands = parsedCommands.filter { !$0.isDestructive }
        guard !safeCommands.isEmpty else { return }
        
        // For now, just run the first command
        // In a full implementation, we'd run them sequentially
        if let firstCommand = safeCommands.first {
            terminalService.execute(
                firstCommand.command,
                workingDirectory: editorViewModel.rootFolderURL,
                environment: nil,
                onOutput: { _ in },
                onError: { _ in },
                onComplete: { _ in
                    // Could chain next command here
                }
            )
        }
    }
    
    private var contentVStack: some View {
        VStack(alignment: .leading, spacing: 6) { // More compact spacing between cards
            // Show thinking process if enabled and there are thinking steps
            if viewModel.showThinkingProcess && (!viewModel.thinkingSteps.isEmpty || viewModel.currentPlan != nil) {
                thinkingProcessCard
            }
            
            parsedFilesView
            actionsView
            rawStreamingView

            // Completion summary - show after AI has responded
            if !viewModel.isLoading && hasResponse {
                CompletionSummaryView(
                    parsedFiles: parsedFiles,
                    parsedCommands: parsedCommands,
                    lastUserRequest: lastUserRequest,
                    lastMessage: viewModel.conversation.messages.last(where: { $0.role == .assistant })?.content,
                    currentActions: viewModel.currentActions
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
            }

            // Graphite recommendation for large changes
            if shouldShowGraphiteRecommendation && !viewModel.isLoading {
                GraphiteRecommendationView(
                    parsedFiles: parsedFiles,
                    onCreateStack: createGraphiteStack
                )
            }
        }
    }
    
    private var thinkingProcessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            thinkingHeader
            if isThinkingExpanded {
                thinkingExpandedContent
            }
        }
        .background(thinkingCardBackground)
        .overlay(thinkingCardOverlay)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    private var thinkingHeader: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isThinkingExpanded.toggle()
            }
        }) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                    .font(.system(size: 13))
                
                Text("Thinking Process")
                    .font(.system(size: 13, weight: .semibold))
                
                if !isThinkingExpanded {
                    Spacer()
                    Text(thinkingSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 4)
                }
                
                Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var thinkingExpandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let plan = viewModel.currentPlan {
                        planView(plan: plan)
                    }
                    
                    thinkingStepsView
                    
                    if thinkingStepsCount > 10 {
                        Text("... and \(thinkingStepsCount - 10) more thinking steps")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
        }
    }
    
    private func planView(plan: AIPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                Text("Plan")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text(step)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 4)
    }
    
    private var thinkingStepsView: some View {
        ForEach(Array(displayThinkingSteps)) { step in
            thinkingStepRow(step: step)
        }
    }
    
    private func thinkingStepRow(step: AIThinkingStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.type == .thinking ? "brain.head.profile" : "list.bullet.rectangle")
                .font(.system(size: 11))
                .foregroundColor(step.type == .thinking ? .purple : .blue)
                .frame(width: 16)
            
            Text(step.content)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(step.type == .thinking ? Color.purple.opacity(0.08) : Color.blue.opacity(0.08))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
    
    private var displayThinkingSteps: [AIThinkingStep] {
        Array(viewModel.thinkingSteps.filter { $0.type == .thinking || $0.type == .planning }.suffix(10))
    }
    
    private var thinkingStepsCount: Int {
        viewModel.thinkingSteps.filter { $0.type == .thinking || $0.type == .planning }.count
    }
    
    private var thinkingCardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }
    
    private var thinkingCardOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
    }
    
    private var thinkingSummary: String {
        let thinkingSteps = viewModel.thinkingSteps.filter { $0.type == .thinking || $0.type == .planning }
        
        if let plan = viewModel.currentPlan, !plan.steps.isEmpty {
            return "Planning: \(plan.steps.count) step\(plan.steps.count == 1 ? "" : "s")"
        } else if !thinkingSteps.isEmpty {
            let lastStep = thinkingSteps.last?.content ?? ""
            if lastStep.count > 50 {
                return String(lastStep.prefix(50)) + "..."
            }
            return lastStep
        } else {
            return "Analyzing..."
        }
    }
    
    private var parsedFilesView: some View {
        ForEach(parsedFiles) { file in
            fileCard(for: file)
                .id(file.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .top)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.97))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8)),
                    removal: .opacity
                        .combined(with: .scale(scale: 0.97))
                        .animation(.spring(response: 0.25, dampingFraction: 0.85))
                ))
        }
    }
    
    private func fileCard(for file: StreamingFileInfo) -> some View {
        CursorStreamingFileCard(
            file: file,
            isExpanded: expandedFiles.contains(file.id),
            projectURL: editorViewModel.rootFolderURL,
            onToggle: { toggleFile(file.id) },
            onOpen: { openFile(file) },
            onApply: { applyFile(file) },
            onReject: { rejectFile(file) }
        )
        .overlay(
            // Graphite recommendation for large changes
            Group {
                if shouldShowGraphiteRecommendationForFile(file) {
                    GraphiteRecommendationBadge {
                        showGraphiteStackViewForFile(file)
                    }
                }
            },
            alignment: .topTrailing
        )
    }
    
    
    private func rejectFile(_ file: StreamingFileInfo) {
        // Remove file from parsed files
        parsedFiles.removeAll { $0.id == file.id }
    }
    
    private var actionsView: some View {
        Group {
            if parsedFiles.isEmpty && !viewModel.currentActions.isEmpty {
                ForEach(viewModel.currentActions) { action in
                    actionCard(for: action)
                        .id(action.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.95))
                                .animation(.spring(response: 0.4, dampingFraction: 0.75)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95))
                                .animation(.spring(response: 0.3, dampingFraction: 0.8))
                        ))
                }
            }
        }
    }
    
    private func actionCard(for action: AIAction) -> some View {
        CursorActionCard(
            action: action,
            streamingContent: getStreamingContent(for: action),
            isStreaming: viewModel.isLoading && action.status == .executing,
            onOpen: { openAction(action) },
            onApply: { applyAction(action) }
        )
    }
    
    private var rawStreamingView: some View {
        Group {
            // Show raw streaming content if loading and no files/actions yet, OR if there's thinking content
            if viewModel.isLoading && (parsedFiles.isEmpty && viewModel.currentActions.isEmpty || !viewModel.thinkingSteps.isEmpty) {
                // Only show raw streaming if there's actual content and it's not just thinking steps
                if !streamingText.isEmpty && parsedFiles.isEmpty {
                    StreamingResponseView(
                        content: streamingText,
                        onContentChange: { newContent in
                            // Update streaming text immediately for display
                            Task { @MainActor in
                                self.streamingText = newContent
                            }
                            // Debounce parsing to reduce CPU usage
                            parseDebouncer.debounce {
                                await MainActor.run {
                                    self.parseStreamingContent(newContent)
                                }
                            }
                        }
                    )
                    .id("streaming")
                }
            }
        }
    }
    
    // MARK: - Apply Button Bar
    
    private var applyButtonBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text("\(parsedFiles.count) file\(parsedFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                // Undo all - clear parsed files
                Task { @MainActor in
                    self.parsedFiles.removeAll()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                    Text("Undo All")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                // Apply all files
                autoApplyAllFiles()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Apply All")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var hasFilesToApply: Bool {
        parsedFiles.contains { file in
            !file.isStreaming &&
            !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            file.content.count > 10
        }
    }
    
    // MARK: - Helpers
    
    private func toggleFile(_ fileId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if expandedFiles.contains(fileId) {
                expandedFiles.remove(fileId)
            } else {
                expandedFiles.insert(fileId)
            }
        }
    }
    
    private func handleMessageChange(_ newContent: String?) {
        guard let content = newContent else { return }
        
        // Update streaming text immediately for display (defer to avoid publishing during view updates)
        Task { @MainActor in
            self.streamingText = content
        }
        
        // Debounce parsing to reduce CPU usage - only parse every 200ms
        parseDebouncer.debounce {
            await MainActor.run {
                self.parseStreamingContent(content)
                
                // Re-parse when streaming completes to catch any final commands
                if !self.viewModel.isLoading {
                    let commands = self.terminalService.extractCommands(from: content)
                    if !commands.isEmpty {
                        self.parsedCommands = commands
                    }
                }
            }
        }
    }
    
    private func handleActionsChange(_: [AIAction]) {
        if viewModel.isLoading {
            // Debounce parsing to reduce CPU usage
            let currentText = streamingText
            parseDebouncer.debounce {
                await MainActor.run {
                    self.parseStreamingContent(currentText)
                }
            }
        }
    }
    
    private func handleAppear() {
        guard let lastMessage = viewModel.conversation.messages.last,
              lastMessage.role == .assistant else { return }
        
        // Update state asynchronously to avoid publishing during view updates
        Task { @MainActor in
            self.streamingText = lastMessage.content
            if self.viewModel.isLoading {
                self.parseStreamingContent(lastMessage.content)
            }
        }
    }
    
    // MARK: - Parsing
    
    private func parseStreamingContent(_ content: String) {
        // Skip parsing if content hasn't changed significantly (reduce CPU usage)
        let contentHash = content.hashValue
        if contentHash == parseDebouncer.lastParsedContentHash && viewModel.isLoading {
            return // Content hasn't changed enough to warrant re-parsing
        }
        // Update hash in debouncer (it's a class so we can modify it)
        parseDebouncer.lastParsedContentHash = contentHash
        
        // First, extract terminal commands
        let commands = terminalService.extractCommands(from: content)
        
        // Parse files from content
        let newFiles = contentParser.parseContent(
            content,
            isLoading: viewModel.isLoading,
            projectURL: editorViewModel.rootFolderURL,
            actions: viewModel.currentActions
        )
        
        // Update state asynchronously to avoid publishing during view updates
        Task { @MainActor in
            if !commands.isEmpty {
                self.parsedCommands = commands
            }
            
            // Auto-expand new files that are streaming
            for file in newFiles {
                if file.isStreaming && !self.expandedFiles.contains(file.id) {
                    self.expandedFiles.insert(file.id)
                }
            }
            
            // Only update if files actually changed (avoid unnecessary view updates)
            if newFiles.count != self.parsedFiles.count || 
               !newFiles.elementsEqual(self.parsedFiles, by: { $0.id == $1.id && $0.content == $1.content }) {
                self.parsedFiles = newFiles
            }
        }
    }
    
    private func getStreamingContent(for action: AIAction) -> String? {
        if let filePath = action.filePath,
           let file = parsedFiles.first(where: { $0.path == filePath }) {
            return file.content
        }
        return action.fileContent
    }
    
    // MARK: - Actions
    
    private func openFile(_ file: StreamingFileInfo) {
        // Defer to avoid publishing during view updates
        Task { @MainActor in
            fileActionHandler.openFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
        }
    }
    
    private func applyFile(_ file: StreamingFileInfo) {
        // Defer to avoid publishing during view updates
        Task { @MainActor in
            fileActionHandler.applyFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
        }
    }
    
    private func autoApplyAllFiles() {
        // Auto-apply all parsed files when project generation completes
        // Only apply files that are complete (not streaming) and have valid content
        let filesToApply = parsedFiles.filter { file in
            // Only apply if:
            // 1. Not currently streaming
            // 2. Content is not empty
            // 3. Content has meaningful content (not just whitespace)
            !file.isStreaming &&
            !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            file.content.count > 10 // Minimum content length to avoid empty files
        }
        
        guard !filesToApply.isEmpty else {
            print("⚠️ No valid files to auto-apply (all files are streaming or empty)")
            return
        }
        
        // Apply and open files sequentially to avoid state update conflicts
        Task { @MainActor in
            for (index, file) in filesToApply.enumerated() {
                // Small delay between each file to avoid overwhelming the system
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay between files
                }
                
                // Double-check content is still valid before applying
                if !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Use openFile instead of applyFile to both write AND open in editor
                    self.openFile(file)
                } else {
                    print("⚠️ Skipping file \(file.path) - content is empty")
                }
            }
            
            // Final refresh after all files are applied to ensure file tree is updated
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s delay to ensure all writes complete
            self.editorViewModel.refreshFileTree()
        }
    }
    
    private func openAction(_ action: AIAction) {
        fileActionHandler.openAction(action, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
    }
    
    private func applyAction(_ action: AIAction) {
        fileActionHandler.applyAction(action, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
    }
    
    // MARK: - Drag and Drop
    
    private func handleImageDrop(providers: [NSItemProvider]) async -> Bool {
        var handled = false
        
        for provider in providers {
            // Check if it's a file URL (most common case)
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                        Task { @MainActor in
                            if let error = error {
                                print("Error loading file URL: \(error.localizedDescription)")
                                continuation.resume()
                                return
                            }
                            
                            if let data = item as? Data,
                               let url = URL(dataRepresentation: data, relativeTo: nil) {
                                _ = imageContextService.addFromFile(url)
                            } else if let url = item as? URL {
                                _ = imageContextService.addFromFile(url)
                            }
                            continuation.resume()
                        }
                    }
                }
                handled = true
            }
            // Check if it's an image (for direct image drops)
            else if provider.hasItemConformingToTypeIdentifier("public.image") {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                        Task { @MainActor in
                            if let error = error {
                                print("Error loading image: \(error.localizedDescription)")
                                continuation.resume()
                                return
                            }
                            
                            if let url = item as? URL {
                                _ = imageContextService.addFromFile(url)
                            } else if let data = item as? Data,
                                      let image = NSImage(data: data) {
                                _ = imageContextService.addImage(image, source: .dragDrop)
                            } else if let image = item as? NSImage {
                                _ = imageContextService.addImage(image, source: .dragDrop)
                            }
                            continuation.resume()
                        }
                    }
                }
                handled = true
            }
        }
        
        return handled
    }
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty else { return }
        
        // Store user request for completion summary
        lastUserRequest = viewModel.currentInput
        
        streamingText = ""
        parsedFiles = []
        parsedCommands = [] // Clear previous commands
        // Pass user message as query to detect website modifications and include existing files
        var context = editorViewModel.getContextForAI(query: viewModel.currentInput) ?? ""
        
        // Build context from mentions
        let mentionContext = MentionParser.shared.buildContextFromMentions(
            activeMentions,
            projectURL: editorViewModel.rootFolderURL,
            selectedText: editorViewModel.editorState.selectedText,
            terminalOutput: nil
        )
        context += mentionContext
        
        // Send message with images if any
        viewModel.sendMessage(
            context: context,
            projectURL: editorViewModel.rootFolderURL,
            images: imageContextService.attachedImages
        )
        
        // Clear images and mentions after sending
        imageContextService.clearImages()
        activeMentions.removeAll()
    }
    
    private var hasResponse: Bool {
        // Check if AI has provided any response
        return !parsedFiles.isEmpty ||
               !parsedCommands.isEmpty ||
               !lastUserRequest.isEmpty ||
               viewModel.conversation.messages.contains(where: { $0.role == .assistant })
    }

    private var shouldShowGraphiteRecommendation: Bool {
        let totalFiles = parsedFiles.count
        let totalLines = parsedFiles.reduce(0) { $0 + $1.addedLines }
        return totalFiles > 5 || totalLines > 200
    }
    
    private func shouldShowGraphiteRecommendationForFile(_ file: StreamingFileInfo) -> Bool {
        let lineCount = file.content.components(separatedBy: .newlines).count
        return lineCount > 200 || file.addedLines > 100
    }
    
    private func showGraphiteStackViewForFile(_ file: StreamingFileInfo) {
        selectedFileForGraphite = file
        showGraphiteView = true
    }
    
    private func createGraphiteStack() {
        showGraphiteView = true
    }
}
