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
    
    @StateObject private var updateCoordinator = StreamingUpdateCoordinator()
    @State private var expandedFiles: Set<String> = []
    @State private var lastUserRequest: String = ""
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var isThinkingExpanded: Bool = false // Track if thinking process is expanded
    private let terminalService = TerminalExecutionService.shared
    @State private var activeMentions: [Mention] = []
    @State private var showUndoConfirmation = false
    @State private var isApplyingFiles = false // Track if files are currently being applied
    @State private var isVerifying: Bool = false // Track if shadow verification is in progress
    @State private var verificationStatus: VerificationStatus? = nil // Verification result
    @State private var showStackDialog = false // Show Graphite stacking dialog
    @State private var stackingPlan: StackingPlan? = nil // AI-generated stacking plan
    @State private var isCreatingStack = false // Track stack creation progress
    @State private var showReviewView = false // Show review view for all files
    @State private var keptFiles: Set<String> = [] // Files marked as "kept" (not applied, but kept visible)
    @State private var showBatchApplyConfirmation = false // Show confirmation dialog for batch apply
    @State private var showPerformanceDashboard = false // Show performance dashboard
    @State private var showTestGeneration = false // Show test generation options
    @State private var performanceDashboardObserver: NSObjectProtocol?
    private let fileActionHandler = FileActionHandler.shared
    
    enum VerificationStatus {
        case success
        case failure(String)
    }
    
    // Check if changes are large enough to warrant stacking
    private var shouldOfferStacking: Bool {
        guard editorViewModel.rootFolderURL != nil else { return false }
        let totalFiles = parsedFiles.count
        let totalLines = parsedFiles.reduce(0) { $0 + $1.content.components(separatedBy: .newlines).count }
        
        // Use same threshold as ApplyCodeService
        return totalFiles > 10 || totalLines > 500 || (totalFiles > 5 && totalLines > 200)
    }
    
    // CPU OPTIMIZATION: Coordinator provides throttled updates and prevents 100% CPU usage
    // PROBLEM: Without coordinator, every token/character chunk triggers:
    // - Immediate @Published updates → SwiftUI re-renders
    // - Parsing on every character → 100% CPU usage
    // - Multiple onChange handlers → re-entrant update loops
    // - Auto-scroll on every character → excessive layout calculations
    // SOLUTION: StreamingUpdateCoordinator throttles updates to ~100ms intervals,
    // ensures parsing happens at most once per tick, and only updates MainActor
    // state when parsed output meaningfully changes
    
    // Computed properties that observe coordinator's published state
    // SMOOTH STREAMING FIX: Use displayedText (60 FPS interpolated) instead of throttledStreamingText
    private var streamingText: String { updateCoordinator.displayedText }
    private var parsedFiles: [StreamingFileInfo] { updateCoordinator.parsedFiles }
    private var parsedCommands: [ParsedCommand] { updateCoordinator.parsedCommands }
    
    // SMOOTH STREAMING FIX: State for sticky scroll
    @State private var shouldAutoScroll: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            StreamingHeaderView(viewModel: viewModel, projectURL: editorViewModel.rootFolderURL)
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1)
            
            // Context visualization (NEW - Better than Cursor)
            ContextVisualizationView()
            
            // Inline task queue (Cursor-style)
            InlineTaskQueueView()
            
            streamingContent
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1)
            
            // Apply button - shows when generation is complete and there are files to apply
            // Show button bar if we have files, even if they're still marked as streaming
            // (they'll be marked as complete when loading finishes)
            if !viewModel.isLoading && !parsedFiles.isEmpty {
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
        .sheet(isPresented: $showReviewView) {
            FileReviewView(
                files: parsedFiles,
                projectURL: editorViewModel.rootFolderURL,
                onApply: { file in
                    fileActionHandler.applyFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
                },
                onReject: { file in
                    updateCoordinator.removeFile(file.id)
                }
            )
        }
            .sheet(isPresented: $showPerformanceDashboard) {
                PerformanceDashboardView()
                    .frame(minWidth: 600, minHeight: 500)
            }
            .onAppear {
                // Listen for performance dashboard notification
                // FIX: Capture state directly (struct doesn't need weak)
                performanceDashboardObserver = NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ShowPerformanceDashboard"),
                    object: nil,
                    queue: .main
                ) { _ in
                    // Defer state update to avoid "Publishing changes from within view updates" warning
                    Task { @MainActor in
                        showPerformanceDashboard = true
                    }
                }
            }
            .onDisappear {
                if let observer = performanceDashboardObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
            .sheet(isPresented: $showTestGeneration) {
            TestGenerationView(
                files: parsedFiles,
                projectURL: editorViewModel.rootFolderURL,
                onDismiss: {
                    showTestGeneration = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showTodoList) {
            TodoListView(
                todos: $viewModel.todoList,
                onExecute: {
                    // Get the last user message and execute with todo list
                    // The context and parameters are stored in pendingExecutionContext
                    if let lastMessage = viewModel.conversation.messages.last(where: { $0.role == .user }) {
                        // Get context for the execution
                        Task { @MainActor in
                            let context = await editorViewModel.getContextForAI()
                            viewModel.executeWithTodoList(
                                userMessage: lastMessage.content,
                                context: context,
                                projectURL: editorViewModel.rootFolderURL,
                                images: imageContextService.attachedImages,
                                forceEditMode: true // Always use edit mode for todo list execution
                            )
                        }
                    }
                },
                onCancel: {
                    viewModel.showTodoList = false
                    viewModel.todoList = []
                }
            )
        }
        .alert("Apply All Files?", isPresented: $showBatchApplyConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Apply All") {
                autoApplyAllFiles()
            }
        } message: {
            let filesToApply = parsedFiles.filter { !keptFiles.contains($0.id) && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let fileCount = filesToApply.count
            let fileList = filesToApply.prefix(5).map { $0.path }.joined(separator: "\n")
            let moreFiles = fileCount > 5 ? "\n... and \(fileCount - 5) more file(s)" : ""
            
            Text("This will apply \(fileCount) file(s) to your workspace:\n\n\(fileList)\(moreFiles)\n\nThis action will modify your files. Make sure you have saved your work.")
        }
        // CPU OPTIMIZATION: Send raw streaming text to coordinator (no blocking, no throttling here)
        // Coordinator handles throttling, parsing, and state updates internally
        // This prevents re-entrant SwiftUI update loops by centralizing all update logic
        .onChange(of: viewModel.conversation.messages.last?.content) { _, newContent in
            // Send raw streaming text to coordinator at full speed
            // Coordinator will throttle updates and trigger parsing as needed
            if let content = newContent {
                updateCoordinator.updateStreamingText(content)
            }
        }
        // CPU OPTIMIZATION: Coordinator automatically re-parses when context changes
        // No need for separate onChange handler - coordinator will detect changes on next tick
        .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
            // When loading completes, flush coordinator updates to ensure final state is applied
            if wasLoading && !isLoading {
                Task { @MainActor in
                    updateCoordinator.flushUpdates()
                    // Re-parse final content after a brief delay to ensure all streaming is complete
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    handleLoadingComplete()
                }
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
        .onChange(of: updateCoordinator.parsedFiles) { oldFiles, newFiles in
            // Auto-expand new files that are streaming
            for file in newFiles {
                if file.isStreaming && !expandedFiles.contains(file.id) {
                    expandedFiles.insert(file.id)
                }
            }
        }
        .onAppear {
            // Setup coordinator callbacks on appear
            setupCoordinator()
            handleAppear()
        }
        .sheet(isPresented: $showStackDialog) {
            if let plan = stackingPlan {
                GraphiteStackDialogView(
                    plan: plan,
                    workspaceURL: editorViewModel.rootFolderURL ?? URL(fileURLWithPath: "/"),
                    isCreating: $isCreatingStack,
                    onDismiss: { showStackDialog = false },
                    onStackCreated: { stackedPRs in
                        print("✅ Created stack with \(stackedPRs.count) PRs")
                        showStackDialog = false
                    }
                )
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Analyzing changes for stacking...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(40)
            }
        }
    }
    
    // MARK: - View Components
    
    
    private var streamingContent: some View {
        // SMOOTH STREAMING FIX: Use NSScrollView wrapper for 60 FPS sticky scroll
        StickyScrollView(shouldAutoScroll: $shouldAutoScroll) { scrollPercentage in
            // Track scroll position for auto-scroll detection
        } content: {
            VStack(spacing: DesignSystem.Spacing.md) {
                // AGENT STATE: Always show a state - never blank
                agentStateView
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.md)
            // SMOOTH STREAMING FIX: Force view update when displayedText changes (triggers scroll)
            // This ensures StickyScrollView.updateNSView is called on every 60 FPS text update
            .id(updateCoordinator.displayedText.count) // Use count as ID to trigger updates
        }
        .onChange(of: updateCoordinator.displayedText) { _, _ in
            // SMOOTH STREAMING FIX: Auto-scroll on every text update (60 FPS smooth)
            // The .id() modifier above ensures StickyScrollView.updateNSView is called,
            // which will trigger scrollToBottom() when shouldAutoScroll is true
            if shouldAutoScroll && viewModel.isLoading {
                // Scroll happens automatically in StickyScrollView.updateNSView
                // No animation needed here because the text change is already small (2 chars)
                // The "stick-to-bottom" will feel natural
            }
        }
        .onAppear {
            shouldAutoScroll = true
        }
    }
    
    // AGENT STATE: Render based on explicit state - never blank
    private var agentStateView: some View {
        Group {
            switch updateCoordinator.agentState {
            case .idle:
                emptyStateView
                
            case .streaming:
                generatingView
                
            case .validating:
                validatingView
                
            case .blocked(let reason):
                blockedView(reason: reason)
                
            case .empty:
                emptyOutputView
                
            case .ready(let edits):
                readyView(edits: edits)
            }
        }
    }
    
    private var generatingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Animated progress indicator
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.blue)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Generating...")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("AI is writing code")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            // Show live streaming text so the user can see code as it's written
            if !streamingText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            HStack {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                Text("Live Preview")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            
                            // Content
                            Text(streamingText)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DesignSystem.Spacing.sm)
                                .id("streaming-live")
                        }
                    }
                    .frame(maxHeight: 300)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .onChange(of: streamingText.count) { _, _ in
                        withAnimation(.none) {
                            proxy.scrollTo("streaming-live", anchor: .bottom)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
    
    private var validatingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Animated validation indicator
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.orange)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Validating output...")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Checking code safety and correctness")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
    
    private func blockedView(reason: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text("Output blocked by Edit Mode")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(reason)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .padding()
    }
    
    private var emptyOutputView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .symbolEffect(.pulse, options: .repeating)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("No edits produced")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("The AI response did not contain any file edits.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
    
    private func readyView(edits: [StreamingFileInfo]) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Code review before apply (NEW - Better than Cursor)
            if !parsedFiles.isEmpty {
                ForEach(parsedFiles) { file in
                    if let review = viewModel.codeReviewResults[file.path] {
                        CodeReviewBeforeApplyView(
                            reviewResult: review,
                            filePath: file.path,
                            onDismiss: {
                                viewModel.codeReviewResults.removeValue(forKey: file.path)
                            },
                            onApplyAnyway: {
                                applyFile(file)
                                viewModel.codeReviewResults.removeValue(forKey: file.path)
                            }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.md)
                    }
                }
            }
            
            // Tool call progress and approval (human-in-the-loop)
            if !viewModel.toolCallProgresses.isEmpty {
                ToolCallProgressListView(
                    progresses: viewModel.toolCallProgresses,
                    onApprove: { toolCallId in
                        viewModel.approveToolCall(toolCallId)
                    },
                    onReject: { toolCallId in
                        viewModel.rejectToolCall(toolCallId)
                    }
                )
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
            }
            
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
        .onChange(of: parsedFiles.count) { oldCount, newCount in
            // Trigger code review when files are ready
            if newCount > oldCount {
                for file in parsedFiles where !file.isStreaming {
                    if viewModel.codeReviewResults[file.path] == nil {
                        triggerCodeReview(for: file)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.accent)
                .symbolEffect(.pulse, options: .repeating)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("AI Assistant Ready")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Ask me anything or request code changes")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .padding(.horizontal, DesignSystem.Spacing.lg)
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
            // ARCHITECTURE: Hard boundary - internal reasoning is never rendered
            // Only validated, executable output is shown
            // Do NOT show thinking process, plans, or raw streaming tokens
            
            parsedFilesView
            actionsView
            // rawStreamingView REMOVED - do not show raw streams directly to UI
            // Only show validated, parsed output (parsedFilesView, actionsView)

            // Completion summary - show after AI has responded
            // COMPLETION GATE: Only show if all conditions are met (checked inside CompletionSummaryView)
            // Show summary when loading is complete AND we have either:
            // 1. Parsed files/commands, OR
            // 2. An assistant message in the conversation, OR
            // 3. A user request was made (even if no response yet)
            if !viewModel.isLoading && hasResponse {
                CompletionSummaryView(
                    parsedFiles: parsedFiles,
                    parsedCommands: parsedCommands,
                    lastUserRequest: lastUserRequest,
                    lastMessage: viewModel.conversation.messages.last(where: { $0.role == .assistant })?.content,
                    currentActions: viewModel.currentActions,
                    executionOutcome: nil, // TODO: Pass execution outcome when available from inline edits
                    expansionResult: nil
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
                .id("completion-summary-\(viewModel.conversation.messages.count)") // Force refresh when messages change
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
    
    // SMOOTH STREAMING FIX: Namespace for matchedGeometryEffect
    @Namespace private var fileCardNamespace
    
    private var parsedFilesView: some View {
        ForEach(parsedFiles) { file in
            fileCard(for: file)
                .id(file.id)
                // SMOOTH STREAMING FIX: Use matchedGeometryEffect for smooth morphing transitions
                // This allows cards to "slide open" smoothly instead of snapping into place
                .matchedGeometryEffect(id: file.id, in: fileCardNamespace)
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
            isKept: keptFiles.contains(file.id),
            onToggle: { toggleFile(file.id) },
            onOpen: { openFile(file) },
            onApply: { 
                applyFile(file)
                // Remove from kept files when applied
                keptFiles.remove(file.id)
            },
            onReject: { 
                rejectFile(file)
                // Remove from kept files when rejected
                keptFiles.remove(file.id)
            },
            onUnkeep: {
                // Un-keep this file
                keptFiles.remove(file.id)
            }
        )
    }
    
    
    private func rejectFile(_ file: StreamingFileInfo) {
        // ARCHITECTURE: Use safe state update method instead of direct mutation
        updateCoordinator.removeFile(file.id)
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
    
    // ARCHITECTURE: rawStreamingView REMOVED
    // Hard boundary: Internal reasoning/thinking is never rendered
    // Only validated, executable output is shown (parsedFilesView, actionsView)
    // Raw streams are buffered internally but never displayed directly
    // This prevents users from seeing:
    // - "Thinking..." text
    // - "Plan" text
    // - Internal analysis
    // - Raw streamed tokens
    
    // MARK: - Apply Button Bar
    
    private var applyButtonBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // File count badge
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
                Text("\(parsedFiles.count) File\(parsedFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(Color.blue.opacity(0.1))
            )
            
            Spacer()
            
            // Undo button
            Button(action: {
                // Show confirmation before clearing files
                showUndoConfirmation = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                    Text("Undo")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Remove all files from view")
            
            Button(action: {
                // Toggle keep status for all files
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if keptFiles.count == parsedFiles.count {
                        // All files are kept, unkeep all
                        keptFiles.removeAll()
                    } else {
                        // Keep all files
                        keptFiles = Set(parsedFiles.map { $0.id })
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: keptFiles.count == parsedFiles.count && !parsedFiles.isEmpty ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 10, weight: .medium))
                    Text(keptFiles.count == parsedFiles.count && !parsedFiles.isEmpty ? "Unkeep" : "Keep")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(keptFiles.count == parsedFiles.count && !parsedFiles.isEmpty ? .purple : .secondary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(keptFiles.count == parsedFiles.count && !parsedFiles.isEmpty ? Color.purple.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help(keptFiles.count == parsedFiles.count && !parsedFiles.isEmpty ? "Unkeep all files" : "Keep files visible without applying")
            
            Button(action: {
                showReviewView = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Review")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Review all file changes")
            .alert("Clear All Files?", isPresented: $showUndoConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    // ARCHITECTURE: Use safe state update method instead of direct mutation
                    // Clear all files except kept ones
                    let filesToRemove = parsedFiles.filter { !keptFiles.contains($0.id) }
                    for file in filesToRemove {
                        updateCoordinator.removeFile(file.id)
                    }
                    // If all files were kept, clear the keptFiles set
                    if filesToRemove.isEmpty {
                        keptFiles.removeAll()
                    }
                    print("✅ Cleared \(filesToRemove.count) file(s) (kept \(keptFiles.count) file(s))")
                }
            } message: {
                let keptCount = parsedFiles.filter { keptFiles.contains($0.id) }.count
                let removableCount = parsedFiles.count - keptCount
                if keptCount > 0 {
                    Text("This will remove \(removableCount) file\(removableCount == 1 ? "" : "s") from the view. \(keptCount) kept file\(keptCount == 1 ? "" : "s") will remain visible. Files will remain on disk if they were already applied.")
                } else {
                    Text("This will remove all \(parsedFiles.count) file\(parsedFiles.count == 1 ? "" : "s") from the view. The files will remain on disk if they were already applied.")
                }
            }
            
            // Smart Stack badge (shown when changes are large)
            if shouldOfferStacking && GraphiteService.shared.isGraphiteInstalled() {
                Button(action: {
                    showStackDialog = true
                    createStackingPlan()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 11, weight: .medium))
                        Text("Stack it?")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Verification badge (shown when verification is complete)
            if let status = verificationStatus {
                HStack(spacing: 4) {
                    switch status {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Compiles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    case .failure:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Build Failed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            }
            
            Button(action: {
                // Show confirmation dialog before applying
                showBatchApplyConfirmation = true
            }) {
                HStack(spacing: 6) {
                    if isVerifying {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                            .tint(.white)
                    } else if isApplyingFiles {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(isVerifying ? "Verifying..." : (isApplyingFiles ? "Applying..." : "Apply All"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill((isVerifying || isApplyingFiles) ? Color.accentColor.opacity(0.7) : Color.accentColor)
                        .shadow(color: (isVerifying || isApplyingFiles) ? Color.clear : Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 3)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isVerifying || isApplyingFiles)
            .scaleEffect(isVerifying || isApplyingFiles ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isVerifying || isApplyingFiles)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var hasFilesToApply: Bool {
        // Check if we have any files with valid content (even if still marked as streaming)
        // The re-parse on completion will mark them as complete
        parsedFiles.contains { file in
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
    
    // CPU OPTIMIZATION: Coordinator handles all message changes
    // No need for handleMessageChange - coordinator receives updates via onChange handler
    // Coordinator throttles updates and triggers parsing internally
    
    // CPU OPTIMIZATION: Setup coordinator callbacks
    // Coordinator needs context for parsing and callbacks for file updates
    private func setupCoordinator() {
        // ARCHITECTURE: Coordinator needs context including user prompt for intent classification
        updateCoordinator.getContext = { [viewModel, editorViewModel] in
            let lastUserMessage = viewModel.conversation.messages.last(where: { $0.role == .user })?.content
            return (
                isLoading: viewModel.isLoading,
                projectURL: editorViewModel.rootFolderURL,
                actions: viewModel.currentActions,
                userPrompt: lastUserMessage
            )
        }
        
        // Handle validation errors
        // ARCHITECTURE: No [weak self] needed - CursorStreamingView is a struct (value type)
        // Structs don't have retain cycles, so weak capture is not applicable
        updateCoordinator.onValidationError = { errorMessage in
            // Show error to user (could be enhanced with alert/toast)
            print("⚠️ VALIDATION ERROR: \(errorMessage)")
            // TODO: Show user-visible error UI
        }
        
        updateCoordinator.onFilesUpdated = { files in
            // Auto-expand new files that are streaming
            // Note: We can't directly modify expandedFiles here since it's a @State property
            // The coordinator will trigger a view update, and we'll handle expansion in the view
        }
    }
    
    private func handleAppear() {
        guard let lastMessage = viewModel.conversation.messages.last,
              lastMessage.role == .assistant else { return }
        
        // Send existing content to coordinator
        updateCoordinator.updateStreamingText(lastMessage.content)
    }
    
    // Handle loading completion (called after coordinator flushes updates)
    // ARCHITECTURE: All parsing/validation happens in EditIntentCoordinator
    // Views only observe state, never mutate it during render
    private func handleLoadingComplete() {
        // Final validation is handled by EditIntentCoordinator via StreamingUpdateCoordinator
        // No direct parsing or state mutation here - coordinator handles it
        // This ensures state updates happen asynchronously AFTER view updates
        
        // Mark existing files as complete if needed
        // ARCHITECTURE: Use safe state update method
        Task { @MainActor in
            if !parsedFiles.isEmpty {
                let updatedFiles = parsedFiles.map { file in
                    var updated = file
                    updated.isStreaming = false
                    return updated
                }
                // ARCHITECTURE: Use safe state update method instead of direct mutation
                updateCoordinator.updateFiles(updatedFiles)
                
                if viewModel.autoExecuteCode {
                    print("✅ Auto-applying \(updatedFiles.count) files (auto-execute enabled)")
                    self.autoApplyAllFiles()
                } else {
                    print("ℹ️ Auto-execute is disabled. Use 'Apply All' button to apply files.")
                }
            }
        }
    }
    
    // MARK: - Parsing
    
    // CPU OPTIMIZATION: Parsing is now handled by StreamingUpdateCoordinator
    // The coordinator ensures parsing happens at most once per tick (~100ms intervals)
    // and only updates MainActor state when parsed output meaningfully changes
    // This prevents 100% CPU usage by ensuring parsing does NOT run on every token
    
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
            await Task.yield()
            fileActionHandler.openFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
        }
    }
    
    // Trigger code review when files are ready
    private func triggerCodeReview(for file: StreamingFileInfo) {
        guard !viewModel.isReviewingCode else { return }
        
        viewModel.isReviewingCode = true
        let reviewService = AICodeReviewService.shared
        
        reviewService.reviewCode(
            file.content,
            language: detectLanguage(from: (file.path as NSString).pathExtension),
            fileName: file.name
        ) { result in
            DispatchQueue.main.async {
                viewModel.isReviewingCode = false
                switch result {
                case .success(let review):
                    viewModel.codeReviewResults[file.path] = review
                case .failure:
                    // Silently fail - don't block user
                    break
                }
            }
        }
    }
    
    private func applyFile(_ file: StreamingFileInfo) {
        // CRITICAL FIX: Mark file as applied to prevent confusion
        // Defer to avoid publishing during view updates
        Task { @MainActor in
            await Task.yield()
            fileActionHandler.applyFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
            
            // Mark file as applied
            updateCoordinator.markFileAsApplied(file.id)
        }
    }
    
    private func autoApplyAllFiles() {
        // Prevent multiple simultaneous apply operations
        guard !isApplyingFiles && !isVerifying else {
            print("⚠️ Apply/verification operation already in progress")
            return
        }
        
        // Apply all parsed files that have valid content
        // IMPROVED: Be more lenient - if generation is complete, apply files with valid content regardless of streaming status
        // EXCLUDE kept files from auto-apply
        let filesToApply = parsedFiles.filter { file in
            // Don't auto-apply kept files
            guard !keptFiles.contains(file.id) else { return false }
            
            // Only apply if content is valid (not empty and has meaningful content)
            let hasValidContent = !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                  file.content.count > 10 // Minimum content length to avoid empty files
            
            // If generation is complete, apply files with valid content regardless of streaming status
            if !viewModel.isLoading {
                return hasValidContent
            }
            
            // If still generating, only apply files that are marked as complete
            return !file.isStreaming && hasValidContent
        }
        
        guard !filesToApply.isEmpty else {
            let streamingCount = parsedFiles.filter { $0.isStreaming }.count
            if streamingCount > 0 && viewModel.isLoading {
                print("⚠️ No valid files to apply - \(streamingCount) file(s) still streaming. Wait for generation to complete.")
            } else {
                print("⚠️ No valid files to apply - all files are empty or too small")
            }
            return
        }
        
        // SHADOW WORKSPACE: Verify edits compile before applying
        guard let projectURL = editorViewModel.rootFolderURL else {
            print("⚠️ No project URL - skipping shadow verification")
            applyFilesDirectly(filesToApply)
            return
        }
        
        // Start verification
        isVerifying = true
        verificationStatus = nil
        
        ShadowWorkspaceService.shared.verifyFilesInShadow(
            files: filesToApply,
            originalWorkspace: projectURL
        ) { (success: Bool, message: String) in
            DispatchQueue.main.async {
                isVerifying = false
                verificationStatus = success ? .success : .failure(message)
                
                if success {
                    print("✅ Shadow verification passed - applying files")
                    applyFilesDirectly(filesToApply)
                } else {
                    print("❌ Shadow verification failed: \(message)")
                    // Still allow applying, but user sees the failure badge
                    // User can choose to apply anyway or fix the issues
                }
            }
        }
    }
    
    private func applyFilesDirectly(_ filesToApply: [StreamingFileInfo]) {
        // Apply and open files sequentially to avoid state update conflicts
        // IMPORTANT: Do NOT remove files from parsedFiles after applying - keep them visible for review
        Task { @MainActor in
            await Task.yield()
            isApplyingFiles = true
            
            defer {
                isApplyingFiles = false
            }
            
            var appliedCount = 0
            for (index, file) in filesToApply.enumerated() {
                // Small delay between each file to avoid overwhelming the system
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay between files
                }
                
                // Double-check content is still valid before applying
                if !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Use openFile instead of applyFile to both write AND open in editor
                    fileActionHandler.openFile(file, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
                    appliedCount += 1
                    print("✅ Applied and opened file: \(file.path) (\(appliedCount)/\(filesToApply.count))")
                } else {
                    print("⚠️ Skipping file \(file.path) - content is empty")
                }
            }
            
            // Final refresh after all files are applied to ensure file tree is updated
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s delay to ensure all writes complete
            self.editorViewModel.refreshFileTree()
            
            // Files remain in parsedFiles so they stay visible for review
            // User can manually remove them with "Undo All" if needed
            print("✅ All \(appliedCount) file(s) applied successfully. Files remain visible for review.")
        }
    }
    
    private func openAction(_ action: AIAction) {
        fileActionHandler.openAction(action, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
    }
    
    private func applyAction(_ action: AIAction) {
        fileActionHandler.applyAction(action, projectURL: editorViewModel.rootFolderURL, editorViewModel: editorViewModel)
    }
    
    // MARK: - Graphite Stacking
    
    private func createStackingPlan() {
        guard editorViewModel.rootFolderURL != nil else { return }
        
        // Convert StreamingFileInfo to CodeChange for stacking analysis
        let projectURL = editorViewModel.rootFolderURL!
        let changes = parsedFiles.map { file -> CodeChange in
            let fileURL = projectURL.appendingPathComponent(file.path)
            let originalContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            
            return CodeChange(
                id: UUID(),
                filePath: file.path,
                fileName: fileURL.lastPathComponent,
                operationType: originalContent.isEmpty ? .create : .update,
                originalContent: originalContent.isEmpty ? nil : originalContent,
                newContent: file.content,
                lineRange: nil,
                language: detectLanguage(from: fileURL.pathExtension)
            )
        }
        
        GraphiteService.shared.createStackingPlan(changes: changes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let plan):
                    stackingPlan = plan
                case .failure(let error):
                    print("❌ Failed to create stacking plan: \(error.localizedDescription)")
                    // Fallback: create simple plan
                    let fallbackPlan = GraphiteService.shared.createFallbackPlan(changes: changes)
                    stackingPlan = fallbackPlan
                }
            }
        }
    }
    
    private func detectLanguage(from fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "c", "cpp", "h", "hpp": return "c"
        default: return "text"
        }
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

        // Defer all state mutations to avoid "Publishing changes from within view updates"
        let userRequest = viewModel.currentInput
        Task { @MainActor in
            await Task.yield()

            // Store user request for completion summary
            lastUserRequest = userRequest

            // Only clear files when starting a NEW conversation/message
            let previousFileCount = parsedFiles.count
            if previousFileCount > 0 {
                print("🔄 Starting new message - clearing \(previousFileCount) previous file(s) from view")
            }

            // Reset coordinator state (clears all streaming text, parsed files, and commands)
            updateCoordinator.reset()
            
            // Clear verification status for new request
            verificationStatus = nil

            // FIX: Build context asynchronously
            Task { @MainActor in
                // Pass user message as query to detect website modifications and include existing files
                var context = await editorViewModel.getContextForAI(query: userRequest) ?? ""

                // Build context from mentions
                let mentionContext = MentionParser.shared.buildContextFromMentions(
                    activeMentions,
                    projectURL: editorViewModel.rootFolderURL,
                    selectedText: editorViewModel.editorState.selectedText,
                    terminalOutput: nil
                )
                context += mentionContext

                // Agent mode always uses Edit Mode to ensure executable edits only
                viewModel.sendMessage(
                    context: context,
                    projectURL: editorViewModel.rootFolderURL,
                    images: imageContextService.attachedImages,
                    forceEditMode: true
                )
            }

            // Clear images and mentions after sending
            imageContextService.clearImages()
            activeMentions.removeAll()
        }
    }
    
    private var hasResponse: Bool {
        // Check if AI has provided any response
        // Show summary if:
        // 1. We have parsed files or commands, OR
        // 2. There's an assistant message in the conversation, OR
        // 3. There was a user request (even if response is still processing)
        let hasAssistantMessage = viewModel.conversation.messages.contains(where: { $0.role == .assistant })
        let hasParsedContent = !parsedFiles.isEmpty || !parsedCommands.isEmpty
        let hasUserRequest = !lastUserRequest.isEmpty
        
        // Show summary if we have any indication of a response or request
        return hasParsedContent || hasAssistantMessage || (hasUserRequest && !viewModel.isLoading)
    }

    // MARK: - Error State Views
    
    /// Parse failure view - shown when parsing yields zero files or zero edits
    /// PARSE FAILURE HANDLING: Abort pipeline, do NOT show "Response Complete"
    private var parseFailureView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 18))
                
                Text("Parse Failure")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("No files or commands were parsed from the AI response.")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                
                Text("The response may be incomplete or in an unexpected format.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Button("Retry") {
                // Retry the last request
                if let lastMessage = viewModel.conversation.messages.last(where: { $0.role == .user }) {
                    viewModel.currentInput = lastMessage.content
                    viewModel.sendMessage()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1.5)
        )
    }
}
