//
//  AIChatView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct AIChatView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var isCollapsed: Bool = false
    @State private var showMentionPopup: Bool = false
    @State private var activeMentions: [Mention] = []
    @State private var showFileSelector: Bool = false
    @State private var showProjectGenerator: Bool = false
    @State private var viewMode: AIViewMode = .progress  // Show progress by default like Cursor
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var shouldAutoScroll: Bool = true  // Track if we should auto-scroll
    @State private var lastMessageCount: Int = 0
    
    enum AIViewMode {
        case chat
        case cursor  // Cursor-style experience (default)
        case progress
        case composer  // Multi-file editing mode
    }
    
    // Show Cursor experience when AI is working
    private var shouldShowCursorView: Bool {
        viewModel.isLoading || !viewModel.currentActions.isEmpty || !viewModel.createdFiles.isEmpty
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left-edge collapse button (Cursor-style)
            leftEdgeCollapseButton
            
            if !isCollapsed {
                VStack(spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        // Icon only (no text to avoid layout issues)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .help("AI Assistant")
                        
                        Spacer()
                        
                        // View mode toggle
                        Picker("", selection: $viewMode) {
                            Image(systemName: "list.bullet.rectangle")
                                .tag(AIViewMode.progress)
                            Image(systemName: "sparkles")
                                .tag(AIViewMode.cursor)
                            Image(systemName: "bubble.left.and.bubble.right")
                                .tag(AIViewMode.chat)
                            Image(systemName: "square.stack.3d.up")
                                .tag(AIViewMode.composer)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 160)
                        .help("Switch between Progress, Cursor-style, Chat, and Composer view")
                        
                        // New Project button
                        Button(action: { showProjectGenerator = true }) {
                            Image(systemName: "plus.app")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Create New Project")
                        
                        Menu {
                            Button(action: { showProjectGenerator = true }) {
                                Label("New Project...", systemImage: "plus.app")
                            }
                            Divider()
                            Button(action: { viewModel.clearConversation() }) {
                                Label("Clear Chat", systemImage: "trash")
                            }
                            Divider()
                            Toggle("Show Thinking", isOn: $viewModel.showThinkingProcess)
                            Toggle("Auto Execute", isOn: $viewModel.autoExecuteCode)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("More Options")
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.secondaryBackground)
                    
                    Rectangle()
                        .fill(DesignSystem.Colors.borderSubtle)
                        .frame(height: 1)
                    
                    // Switch between views based on mode
                    switch viewMode {
                    case .cursor:
                        // Cursor-level polished experience (default)
                        CursorLevelAIView(viewModel: viewModel, editorViewModel: editorViewModel)
                        
                    case .progress:
                        // Cursor-style streaming experience (exact like Cursor)
                        CursorStreamingView(viewModel: viewModel, editorViewModel: editorViewModel)
                    
                    case .composer:
                        // Composer Mode - Multi-file editing
                        ComposerView(viewModel: viewModel, editorViewModel: editorViewModel)
                    
                    case .chat:
                    // Traditional chat view
                    VStack(spacing: 0) {
                        // Show file progress inline when loading
                        if viewModel.isLoading && !viewModel.currentActions.isEmpty {
                            InlineProgressBar(viewModel: viewModel)
                        }
                        
                        // Show thinking process if enabled and loading
                        if viewModel.showThinkingProcess && viewModel.isLoading {
                            ThinkingProcessView(viewModel: viewModel)
                                .padding(.vertical, 8)
                        }
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(viewModel.conversation.messages) { message in
                                        MessageBubble(
                                            message: message,
                                            isStreaming: viewModel.isLoading && message.id == viewModel.conversation.messages.last?.id,
                                            workingDirectory: editorViewModel.rootFolderURL,
                                            onCopyCode: { code in
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(code, forType: .string)
                                            }
                                        )
                                            .id(message.id)
                                    }
                                    
                                    // Show file changes inline in chat
                                    if !viewModel.currentActions.isEmpty {
                                        InlineFileChangesView(
                                            actions: viewModel.currentActions,
                                            createdFiles: viewModel.createdFiles,
                                            isLoading: viewModel.isLoading,
                                            onOpenFile: { url in
                                                editorViewModel.openFile(at: url)
                                            },
                                            onViewDetails: {
                                                viewMode = .cursor
                                            }
                                        )
                                    }
                                    
                                    if viewModel.isLoading && viewModel.currentActions.isEmpty && !viewModel.showThinkingProcess {
                                        LoadingIndicatorView(onCancel: {
                                            viewModel.cancelGeneration()
                                        })
                                    }
                                    
                                    // Scroll to bottom button (appears when user scrolls up)
                                    if !shouldAutoScroll {
                                        Button(action: {
                                            shouldAutoScroll = true
                                            if let lastMessage = viewModel.conversation.messages.last {
                                                withAnimation {
                                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                                }
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: "arrow.down.circle.fill")
                                                Text("Scroll to bottom")
                                            }
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(16)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .padding(.top, 8)
                                    }
                                }
                                .padding()
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: viewModel.conversation.messages.count) { oldValue, newValue in
                                // Only auto-scroll on new messages when not loading (to avoid blocking during streaming)
                                if !viewModel.isLoading && newValue > oldValue, let lastMessage = viewModel.conversation.messages.last {
                                    lastMessageCount = newValue
                                    // Small delay to allow user to scroll if they want
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                            // Don't auto-scroll on content changes during streaming - let user scroll freely
                            // This prevents the scroll view from being locked during code generation
                        }
                        
                        Divider()
                        
                        // Context badges
                        if !activeMentions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(activeMentions) { mention in
                                        MentionBadgeView(mention: mention) {
                                            activeMentions.removeAll { $0.id == mention.id }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                        
                        // Quick context buttons
                        HStack(spacing: 8) {
                            Button(action: { addMention(.selection) }) {
                                Label("Selection", systemImage: "selection.pin.in.out")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(editorViewModel.editorState.selectedText.isEmpty)
                            
                            Button(action: { addMention(.file) }) {
                                Label("File", systemImage: "doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(editorViewModel.editorState.activeDocument == nil)
                            
                            Button(action: { showFileSelector = true }) {
                                Label("@", systemImage: "at")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .popover(isPresented: $showMentionPopup, arrowEdge: .top) {
                                MentionPopupView(isVisible: $showMentionPopup) { type in
                                    addMention(type)
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("Related", isOn: $editorViewModel.includeRelatedFilesInContext)
                                .font(.caption)
                                .toggleStyle(.checkbox)
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                        
                        // Input area
                        HStack(alignment: .bottom) {
                            Button(action: { showMentionPopup = true }) {
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Add context")
                            
                            TextField("Ask AI... (type @ for mentions)", text: $viewModel.currentInput, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...5)
                                .onSubmit {
                                    sendMessageWithContext()
                                }
                                .onChange(of: viewModel.currentInput) { _, newValue in
                                    // Check for @ trigger
                                    if newValue.hasSuffix("@") {
                                        showMentionPopup = true
                                    }
                                }
                        
                            Button(action: {
                                if viewModel.isLoading {
                                    viewModel.cancelGeneration()
                                } else {
                                    sendMessageWithContext()
                                }
                            }) {
                                Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(viewModel.isLoading ? .red : .accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!viewModel.isLoading && viewModel.currentInput.isEmpty && activeMentions.isEmpty)
                            .help(viewModel.isLoading ? "Stop generation" : "Send message")
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .onDrop(of: [.image, .fileURL], isTargeted: .constant(false)) { providers in
                            Task {
                                _ = await handleImageDrop(providers: providers)
                            }
                            return true
                        }
                        
                        // Attached images preview
                        if !imageContextService.attachedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(imageContextService.attachedImages) { image in
                                        ZStack(alignment: .topTrailing) {
                                            Image(nsImage: image.image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 60, height: 60)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                            
                                            Button(action: {
                                                imageContextService.removeImage(image.id)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                                    .font(.system(size: 14))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .offset(x: 4, y: -4)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                            .padding(.horizontal)
                        }
                        
                        // Context files indicator
                        if let contextFiles = getContextFiles(), !contextFiles.isEmpty {
                            ContextFilesIndicator(files: contextFiles)
                                .padding(.horizontal)
                                .padding(.bottom, 4)
                        }
                        
                        if let error = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        
                        // Show created files summary (compact)
                        if !viewModel.createdFiles.isEmpty && !viewModel.isLoading && viewModel.currentActions.isEmpty {
                            createdFilesSection
                        }
                    }
                    }
                }
            }
        }
        .sheet(isPresented: $showProjectGenerator) {
            ProjectGenerationView(viewModel: viewModel, isPresented: $showProjectGenerator)
        }
    }
    
    // MARK: - Left Edge Collapse Button
    
    @State private var isHoveringToggle: Bool = false
    
    private var leftEdgeCollapseButton: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        }) {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHoveringToggle ? .primary : .secondary)
                    .frame(width: 20, height: 20)
                    .padding(.vertical, 8)
                Spacer()
            }
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .background(
                Group {
                    if isHoveringToggle {
                        Color(NSColor.controlAccentColor).opacity(0.2)
                    } else {
                        Color(NSColor.separatorColor)
                            .opacity(isCollapsed ? 0.3 : 0.5)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(isCollapsed ? "Show AI panel" : "Hide AI panel")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringToggle = hovering
            }
        }
    }
    
    // MARK: - Created Files Section
    
    private var createdFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(viewModel.createdFiles.count) files created")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Open All") {
                    for file in viewModel.createdFiles {
                        editorViewModel.openFile(at: file)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.createdFiles.prefix(8), id: \.self) { file in
                        Button(action: {
                            editorViewModel.openFile(at: file)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: iconForFile(file))
                                    .font(.caption2)
                                Text(file.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if viewModel.createdFiles.count > 8 {
                        Text("+\(viewModel.createdFiles.count - 8)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces.square"
        case "py": return "terminal"
        case "rs": return "gear"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "html": return "chevron.left.slash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        case "md": return "text.justify"
        default: return "doc.fill"
        }
    }
    
    private func addMention(_ type: MentionType) {
        var value = ""
        var displayName = type.rawValue
        
        switch type {
        case .file:
            if let doc = editorViewModel.editorState.activeDocument,
               let filePath = doc.filePath {
                value = filePath.lastPathComponent
                displayName = "@file:\(value)"
            }
        case .selection:
            if !editorViewModel.editorState.selectedText.isEmpty {
                displayName = "@selection"
            }
        case .folder:
            if let url = editorViewModel.rootFolderURL {
                value = url.lastPathComponent
                displayName = "@folder:\(value)"
            }
        case .codebase:
            displayName = "@codebase"
        case .terminal:
            displayName = "@terminal"
        case .web:
            displayName = "@web"
        }
        
        let mention = Mention(type: type, value: value, displayName: displayName)
        
        // Don't add duplicates
        if !activeMentions.contains(where: { $0.type == type && $0.value == value }) {
            activeMentions.append(mention)
        }
    }
    
    private func getContextFiles() -> [String]? {
        var files: [String] = []
        
        // Add active file
        if let activeFile = editorViewModel.editorState.activeDocument?.filePath {
            files.append(activeFile.lastPathComponent)
        }
        
        // Add files from mentions
        for mention in activeMentions {
            if mention.type == .file, !mention.value.isEmpty {
                files.append(mention.value)
            }
        }
        
        // Add related files if enabled
        if editorViewModel.includeRelatedFilesInContext,
           let document = editorViewModel.editorState.activeDocument,
           let filePath = document.filePath,
           let projectURL = editorViewModel.rootFolderURL {
            let relatedFiles = FileDependencyService.shared.findRelatedFiles(
                for: filePath,
                in: projectURL
            )
            files.append(contentsOf: relatedFiles.map { $0.lastPathComponent })
        }
        
        return files.isEmpty ? nil : files
    }
    
    private func sendMessageWithContext() {
        // Get user's message to find relevant files
        let userQuery = viewModel.currentInput
        var context = editorViewModel.getContextForAI(query: userQuery) ?? ""
        
        // Build context from mentions
        let mentionContext = MentionParser.shared.buildContextFromMentions(
            activeMentions,
            projectURL: editorViewModel.rootFolderURL,
            selectedText: editorViewModel.editorState.selectedText,
            terminalOutput: nil
        )
        
        context += mentionContext
        
        // Clear mentions after sending
        activeMentions.removeAll()
        
        let projectURL = editorViewModel.rootFolderURL
        viewModel.sendMessage(
            context: context,
            projectURL: projectURL,
            images: imageContextService.attachedImages
        )
        
        // Clear images after sending
        imageContextService.clearImages()
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
}
