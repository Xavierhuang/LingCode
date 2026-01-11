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
    
    @State private var streamingText: String = ""
    @State private var parsedFiles: [StreamingFileInfo] = []
    @State private var expandedFiles: Set<String> = []
    @State private var showGraphiteView = false
    @State private var selectedFileForGraphite: StreamingFileInfo?
    @State private var lastUserRequest: String = ""
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var parsedCommands: [ParsedCommand] = []
    private let terminalService = TerminalExecutionService.shared
    @State private var activeMentions: [Mention] = []
    private let contentParser = StreamingContentParser.shared
    private let fileActionHandler = FileActionHandler.shared
    
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
            handleMessageChange(newContent)
        }
        .onChange(of: viewModel.currentActions) { _, newActions in
            handleActionsChange(newActions)
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
            // Also auto-apply when loading completes if it was a project generation
            if wasLoading && !isLoading && viewModel.isGeneratingProject == false && !parsedFiles.isEmpty {
                // Defer state changes outside of view update cycle
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    self.autoApplyAllFiles()
                }
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
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .onChange(of: streamingText) { _, _ in
                // Only auto-scroll if user hasn't manually scrolled
                // Use a debounced approach - only scroll if content changed significantly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(DesignSystem.Animation.smooth) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: parsedFiles.count) { oldCount, newCount in
                // Only scroll to new file if it's the first one or user is near bottom
                if newCount > oldCount, let lastFile = parsedFiles.last {
                    // Use a gentler scroll that doesn't interrupt user scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(DesignSystem.Animation.smooth) {
                            proxy.scrollTo(lastFile.id, anchor: .center)
                        }
                    }
                }

                // Auto-open the first file in the editor for preview
                if oldCount == 0 && newCount == 1, let firstFile = parsedFiles.first {
                    openFile(firstFile)
                }
            }
            .onChange(of: parsedCommands.count) { _, _ in
                if let lastCommand = parsedCommands.last {
                    // Debounce scroll to avoid interrupting user
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(DesignSystem.Animation.smooth) {
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
        VStack(alignment: .leading, spacing: 8) {
            parsedFilesView
            actionsView
            rawStreamingView

            // Completion summary - show after AI has responded
            if !viewModel.isLoading && hasResponse {
                CompletionSummaryView(
                    parsedFiles: parsedFiles,
                    parsedCommands: parsedCommands,
                    lastUserRequest: lastUserRequest,
                    lastMessage: viewModel.conversation.messages.last(where: { $0.role == .assistant })?.content
                )
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
    
    private var parsedFilesView: some View {
        ForEach(parsedFiles) { file in
            fileCard(for: file)
                .id(file.id)
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
            if viewModel.isLoading && parsedFiles.isEmpty && viewModel.currentActions.isEmpty {
                StreamingResponseView(
                    content: streamingText,
                    onContentChange: { newContent in
                        streamingText = newContent
                        parseStreamingContent(newContent)
                    }
                )
                .id("streaming")
            }
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
        if let content = newContent {
            streamingText = content
            parseStreamingContent(content)
            
            // Re-parse when streaming completes to catch any final commands
            if !viewModel.isLoading {
                let commands = terminalService.extractCommands(from: content)
                if !commands.isEmpty {
                    parsedCommands = commands
                }
            }
        }
    }
    
    private func handleActionsChange(_: [AIAction]) {
        if viewModel.isLoading {
            parseStreamingContent(streamingText)
        }
    }
    
    private func handleAppear() {
        if let lastMessage = viewModel.conversation.messages.last,
           lastMessage.role == .assistant {
            streamingText = lastMessage.content
            if viewModel.isLoading {
                parseStreamingContent(lastMessage.content)
            }
        }
    }
    
    // MARK: - Parsing
    
    private func parseStreamingContent(_ content: String) {
        // First, extract terminal commands
        let commands = terminalService.extractCommands(from: content)
        if !commands.isEmpty {
            parsedCommands = commands
        }
        
        // Parse files from content
        let newFiles = contentParser.parseContent(
            content,
            isLoading: viewModel.isLoading,
            projectURL: editorViewModel.rootFolderURL,
            actions: viewModel.currentActions
        )
        
        // Auto-expand new files that are streaming
        for file in newFiles {
            if file.isStreaming && !expandedFiles.contains(file.id) {
                expandedFiles.insert(file.id)
            }
        }
        
        parsedFiles = newFiles
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
        fileActionHandler.openFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
    }
    
    private func applyFile(_ file: StreamingFileInfo) {
        fileActionHandler.applyFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
    }
    
    private func autoApplyAllFiles() {
        // Auto-apply all parsed files when project generation completes
        // Apply files sequentially to avoid state update conflicts
        let filesToApply = Array(parsedFiles)
        Task { @MainActor in
            for (index, file) in filesToApply.enumerated() {
                // Small delay between each file to avoid overwhelming the system
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay between files
                }
                self.applyFile(file)
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
