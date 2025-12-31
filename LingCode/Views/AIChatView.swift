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
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.accentColor)
                        Text("AI Assistant")
                            .font(.headline)
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
                                .font(.caption)
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
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
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
                                }
                                .padding()
                            }
                            .onChange(of: viewModel.conversation.messages.count) { oldValue, newValue in
                                if let lastMessage = viewModel.conversation.messages.last {
                                    withAnimation {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
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
        .overlay(alignment: .bottom) {
            if viewModel.isGeneratingProject {
                ProjectProgressOverlay(viewModel: viewModel)
                    .padding()
            }
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

struct LoadingIndicatorView: View {
    @State private var animationPhase: Int = 0
    var onCancel: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.3)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
                
                Text("AI is thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let onCancel = onCancel {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                        Text("Stop")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .onAppear {
            animationPhase = 2
        }
    }
}

struct MessageBubble: View {
    let message: AIMessage
    let isStreaming: Bool
    let onCopyCode: (String) -> Void
    var workingDirectory: URL? = nil
    
    @State private var isHovering: Bool = false
    
    init(message: AIMessage, isStreaming: Bool = false, workingDirectory: URL? = nil, onCopyCode: @escaping (String) -> Void) {
        self.message = message
        self.isStreaming = isStreaming
        self.workingDirectory = workingDirectory
        self.onCopyCode = onCopyCode
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer()
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .padding(.top, 4)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content with code block detection
                if message.role == .assistant {
                    VStack(alignment: .leading, spacing: 4) {
                        FormattedMessageView(content: message.content, onCopyCode: onCopyCode, workingDirectory: workingDirectory)
                        
                        // Show streaming indicator
                        if isStreaming && !message.content.isEmpty {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Streaming...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    Text(message.content)
                        .padding(10)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(8)
                }
                
                if !message.content.isEmpty {
                    HStack {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if isHovering {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                Spacer()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct FormattedMessageView: View {
    let content: String
    let onCopyCode: (String) -> Void
    var workingDirectory: URL? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseContent(), id: \.id) { block in
                if block.isTerminalCommand {
                    // Cursor-style terminal command with Run button
                    TerminalCommandBlock(
                        command: block.content,
                        language: block.language,
                        workingDirectory: workingDirectory,
                        onCopy: { onCopyCode(block.content) }
                    )
                } else if block.isCode {
                    CodeBlockView(code: block.content, language: block.language, onCopy: {
                        onCopyCode(block.content)
                    })
                } else {
                    Text(block.content)
                        .font(.body)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func parseContent() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeContent = ""
        var language = ""
        
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block - check if it's a terminal command
                    let isTerminal = isTerminalLanguage(language)
                    blocks.append(ContentBlock(
                        content: codeContent.trimmingCharacters(in: .whitespacesAndNewlines),
                        isCode: true,
                        language: language,
                        isTerminalCommand: isTerminal
                    ))
                    codeContent = ""
                    language = ""
                    inCodeBlock = false
                } else {
                    // Start of code block
                    if !currentText.isEmpty {
                        blocks.append(ContentBlock(content: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isCode: false, language: nil))
                        currentText = ""
                    }
                    language = String(line.dropFirst(3))
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeContent += line + "\n"
            } else {
                currentText += line + "\n"
            }
        }
        
        // Handle remaining content
        if !currentText.isEmpty {
            blocks.append(ContentBlock(content: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isCode: false, language: nil))
        }
        
        return blocks.filter { !$0.content.isEmpty }
    }
    
    private func isTerminalLanguage(_ language: String) -> Bool {
        let terminalLanguages = ["bash", "shell", "sh", "zsh", "terminal", "console", "cmd", "powershell"]
        return terminalLanguages.contains(language.lowercased())
    }
}

// MARK: - Terminal Command Block (Cursor-style)

struct TerminalCommandBlock: View {
    let command: String
    let language: String?
    let workingDirectory: URL?
    let onCopy: () -> Void
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var isHovering = false
    @State private var isExecuting = false
    @State private var hasExecuted = false
    @State private var output = ""
    @State private var exitCode: Int32?
    @State private var showOutput = false
    @State private var showConfirmation = false
    
    private var isDestructive: Bool {
        let destructive = ["rm ", "rm\t", "rmdir", "delete", "remove", "drop ", "truncate", "format", "> /", ">> /", "sudo rm", "git reset --hard", "git clean"]
        return destructive.contains { command.lowercased().contains($0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Text(language ?? "Terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Status indicator
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Running...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if hasExecuted {
                    Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(exitCode == 0 ? .green : .red)
                    Text(exitCode == 0 ? "Success" : "Failed")
                        .font(.caption)
                        .foregroundColor(exitCode == 0 ? .green : .red)
                }
                
                // Copy button
                if isHovering {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Copy command")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Command
            HStack(spacing: 0) {
                Text("$ ")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                
                Spacer()
            }
            .padding(12)
            .background(Color.black.opacity(0.85))
            
            // Output section
            if showOutput && (!output.isEmpty || isExecuting) {
                Divider()
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if isExecuting {
                            Button(action: cancelExecution) {
                                Label("Cancel", systemImage: "stop.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    ScrollView {
                        Text(output.isEmpty ? "Waiting for output..." : output)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(output.isEmpty ? .gray : .white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(12)
                    .background(Color.black.opacity(0.9))
                }
            }
            
            // Action bar
            HStack(spacing: 12) {
                if isDestructive {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Destructive")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
                
                Spacer()
                
                if hasExecuted && !isExecuting {
                    Button(action: {
                        hasExecuted = false
                        output = ""
                        exitCode = nil
                        showOutput = false
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if isExecuting {
                    Button(action: cancelExecution) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                } else if !hasExecuted {
                    Button(action: {
                        if isDestructive {
                            showConfirmation = true
                        } else {
                            executeCommand()
                        }
                    }) {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .alert("Run Destructive Command?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run Anyway", role: .destructive) {
                executeCommand()
            }
        } message: {
            Text("This command may modify or delete files:\n\n$ \(command)\n\nAre you sure you want to run it?")
        }
    }
    
    private var borderColor: Color {
        if isExecuting { return .orange }
        if hasExecuted {
            return exitCode == 0 ? .green : .red
        }
        return Color.secondary.opacity(0.3)
    }
    
    private func executeCommand() {
        isExecuting = true
        showOutput = true
        output = ""
        
        terminalService.execute(
            command,
            workingDirectory: workingDirectory,
            environment: nil,
            onOutput: { out in
                output += out
            },
            onError: { err in
                output += err
            },
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
        output += "\n[Cancelled by user]"
    }
}

struct ContentBlock: Identifiable {
    let id = UUID()
    let content: String
    let isCode: Bool
    let language: String?
    var isTerminalCommand: Bool = false
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    let onCopy: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isHovering {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Inline Progress Bar

struct InlineProgressBar: View {
    @ObservedObject var viewModel: AIViewModel
    
    private var progress: Double {
        guard !viewModel.currentActions.isEmpty else { return 0 }
        let completed = Double(viewModel.currentActions.filter { $0.status == .completed }.count)
        return completed / Double(viewModel.currentActions.count)
    }
    
    private var currentFileName: String {
        if let executing = viewModel.currentActions.first(where: { $0.status == .executing }) {
            return executing.name.replacingOccurrences(of: "Create ", with: "")
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Creating files...")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if !currentFileName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text(currentFileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Text("\(viewModel.currentActions.filter { $0.status == .completed }.count)/\(viewModel.currentActions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { viewModel.cancelGeneration() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
    }
}

// MARK: - Inline File Changes View

struct InlineFileChangesView: View {
    let actions: [AIAction]
    let createdFiles: [URL]
    let isLoading: Bool
    let onOpenFile: (URL) -> Void
    let onViewDetails: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Creating files...")
                        .font(.caption)
                        .fontWeight(.medium)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(createdFiles.count) file\(createdFiles.count == 1 ? "" : "s") created")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onViewDetails) {
                    Label("View Details", systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // File list
            VStack(spacing: 4) {
                ForEach(actions.prefix(5)) { action in
                    InlineFileRow(
                        action: action,
                        createdFiles: createdFiles,
                        onOpen: { onOpenFile($0) }
                    )
                }
                
                if actions.count > 5 {
                    Text("and \(actions.count - 5) more files...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            // Action buttons
            if !isLoading && !createdFiles.isEmpty {
                HStack(spacing: 8) {
                    Button(action: {
                        for file in createdFiles {
                            onOpenFile(file)
                        }
                    }) {
                        Label("Open All", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: {
                        if let file = createdFiles.first {
                            NSWorkspace.shared.activateFileViewerSelecting([file])
                        }
                    }) {
                        Label("Reveal", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isLoading ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isLoading ? Color.blue.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct InlineFileRow: View {
    let action: AIAction
    let createdFiles: [URL]
    let onOpen: (URL) -> Void
    
    private var fileName: String {
        action.name.replacingOccurrences(of: "Create ", with: "")
    }
    
    private var fileURL: URL? {
        createdFiles.first { $0.lastPathComponent == fileName }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status
            statusIcon
                .frame(width: 16)
            
            // File icon
            Image(systemName: fileIcon)
                .font(.caption)
                .foregroundColor(.accentColor)
            
            // File name
            Text(fileName)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
            
            // Status text
            statusText
            
            // Open button
            if action.status == .completed, let url = fileURL {
                Button(action: { onOpen(url) }) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(action.status == .executing ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch action.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundColor(.gray)
                .font(.caption)
        case .executing:
            ProgressView()
                .scaleEffect(0.5)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        switch action.status {
        case .pending:
            Text("Pending")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .executing:
            Text("Writing...")
                .font(.caption2)
                .foregroundColor(.blue)
        case .completed:
            Text("Done")
                .font(.caption2)
                .foregroundColor(.green)
        case .failed:
            Text("Failed")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
    
    private var fileIcon: String {
        let name = fileName.lowercased()
        if name.hasSuffix(".swift") { return "swift" }
        if name.hasSuffix(".js") || name.hasSuffix(".jsx") { return "curlybraces" }
        if name.hasSuffix(".ts") || name.hasSuffix(".tsx") { return "curlybraces.square" }
        if name.hasSuffix(".py") { return "terminal" }
        if name.hasSuffix(".html") { return "chevron.left.slash.chevron.right" }
        if name.hasSuffix(".css") { return "paintbrush" }
        if name.hasSuffix(".json") { return "doc.text" }
        if name.hasSuffix(".md") { return "text.justify" }
        return "doc.fill"
    }
}
