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
    @State private var showMentionPopup: Bool = false
    @State private var activeMentions: [Mention] = []
    @State private var showFileSelector: Bool = false
    @State private var showProjectGenerator: Bool = false
    @State private var showHistoryPanel: Bool = false
    @AppStorage("AIChatView.viewMode") private var viewMode: AIViewMode = .agent  // Default to Agent mode
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var shouldAutoScroll: Bool = true  // Track if we should auto-scroll
    @State private var lastMessageCount: Int = 0
    
    enum AIViewMode: String {
        case agent   // Agent mode - autonomous task execution
        case plan    // Plan mode - show planning/thinking process
        case debug   // Debug mode - debugging assistance
        case ask     // Ask mode - regular chat (default)
    }
    
    // Show Cursor experience when AI is working
    private var shouldShowCursorView: Bool {
        viewModel.isLoading || !viewModel.currentActions.isEmpty || !viewModel.createdFiles.isEmpty
    }
    
    var body: some View {
        // Removed left-edge collapse button - using ContentView's resizable divider instead
        VStack(spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        // Icon only (no text to avoid layout issues)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .help("AI Assistant")
                        
                        Spacer()
                        
                        // Mode selector - Agent, Plan, Debug, Ask
                        HStack(spacing: 2) {
                            modeButton(.agent, icon: "infinity", label: "Agent", shortcut: "⌘I")
                            modeButton(.plan, icon: "list.bullet.rectangle", label: "Plan")
                            modeButton(.debug, icon: "ant", label: "Debug")
                            modeButton(.ask, icon: "bubble.left.and.bubble.right", label: "Ask")
                        }
                        .padding(2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                        
                        // History button
                        Button(action: { showHistoryPanel.toggle() }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14))
                                .foregroundColor(showHistoryPanel ? .accentColor : DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Conversation History")
                        .popover(isPresented: $showHistoryPanel, arrowEdge: .bottom) {
                            ConversationHistoryPanel(viewModel: viewModel, isPresented: $showHistoryPanel)
                        }
                        
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
                    case .agent:
                        // Agent Mode - Autonomous ReAct Agent with iterative thinking
                        AgentModeView(editorViewModel: editorViewModel)
                        
                    case .plan:
                        // Plan Mode - Show planning/thinking process
                        PlanModeView(viewModel: viewModel, editorViewModel: editorViewModel)
                        
                    case .debug:
                        // Debug Mode - Debugging assistance
                        DebugModeView(viewModel: viewModel, editorViewModel: editorViewModel)
                        
                    case .ask:
                        // Ask Mode - Simple chat interface (just conversation, no code generation)
                        SimpleChatView(viewModel: viewModel, editorViewModel: editorViewModel)
                    }
                }
        .sheet(isPresented: $showProjectGenerator) {
            ProjectGenerationView(viewModel: viewModel, isPresented: $showProjectGenerator)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToAgentMode"))) { _ in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                viewMode = .agent
            }
        }
    }
    
    // MARK: - Mode Selector
    
    private func modeButton(_ mode: AIViewMode, icon: String, label: String, shortcut: String? = nil) -> some View {
        Button(action: {
            switchToMode(mode)
        }) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: viewMode == mode ? .semibold : .regular))
                .foregroundColor(viewMode == mode ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(viewMode == mode ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .help("\(label) mode\(shortcut.map { " (\($0))" } ?? "")")
    }
    
    /// Switch modes with proper state cleanup
    private func switchToMode(_ mode: AIViewMode) {
        guard viewMode != mode else { return }
        
        // Clear state from previous mode to avoid confusion
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            // Clear streaming state when leaving any mode
            StreamingUpdateCoordinator.shared.reset()
            
            // Clear the AIViewModel state if leaving non-agent modes
            if viewMode != .agent {
                viewModel.cancelGeneration()
            }
            
            viewMode = mode
        }
    }
    
    // Removed leftEdgeCollapseButton - using ContentView's resizable divider instead
    
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
        case .docs:
            displayName = "@docs"
        case .notepad:
            displayName = "@notepad"
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
        // Build context asynchronously with @docs and @web support
        Task { @MainActor in
            // Get user's message to find relevant files
            let userQuery = viewModel.currentInput
            var context = await editorViewModel.getContextForAI(query: userQuery) ?? ""
            
            // Build context from mentions (async for @docs and @web)
            let mentionContext = await MentionParser.shared.buildContextFromMentionsAsync(
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
