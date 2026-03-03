//
//  AgentModeView.swift
//  LingCode
//
//  Main view for the autonomous agent interface
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reported by AgentModeView so the host can give the panel enough width when the agent list is visible.
struct AgentPanelMinWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 324
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AgentModeView: View {
    private static let debugLogPath = "/Users/weijiahuang/Desktop/LingCode-main-2/.cursor/debug-0a8696.log"
    private static func debugLog(showAgentList: Bool, width: CGFloat, height: CGFloat) {
        let line = "{\"sessionId\":\"0a8696\",\"location\":\"AgentModeView.swift:body\",\"message\":\"Agent layout\",\"data\":{\"showAgentList\":\(showAgentList),\"geoWidth\":\(width),\"geoHeight\":\(height)}\",\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000)),\"hypothesisId\":\"H1\"}\n"
        Self.appendLog(line)
    }
    private static func appendLog(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: debugLogPath)
        if FileManager.default.fileExists(atPath: debugLogPath) {
            guard let h = try? FileHandle(forUpdating: url) else { return }
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    @StateObject private var coordinator = AgentCoordinator.shared
    @StateObject private var imageContextService = ImageContextService.shared
    @StateObject private var historyService = AgentHistoryService.shared
    @ObservedObject private var localOnlyService = LocalOnlyService.shared
    @State private var inputText: String = ""
    @State private var lastStepCount: Int = 0
    @Namespace private var bottomID
    @State private var showApprovalDialog = false
    @State private var selectedChatId: UUID?
    @State private var showAgentList: Bool = true
    @State private var isDraggingOver: Bool = false
    @State private var activeMentions: [Mention] = []
    @State private var showMentionPopup = false
    @State private var showFilePicker = false
    
    @ObservedObject var editorViewModel: EditorViewModel
    
    private var selectedAgent: AgentService? {
        coordinator.agent(for: selectedChatId)
    }
    
    private var targetAgent: AgentService? {
        if let agent = selectedAgent, !agent.isRunning { return agent }
        return coordinator.agents.first { !$0.isRunning }
    }
    
    var body: some View {
        GeometryReader { geometry in
            // #region agent log
            let _ = AgentModeView.debugLog(showAgentList: showAgentList, width: geometry.size.width, height: geometry.size.height)
            // #endregion
            HSplitView {
                VStack(spacing: 0) {
                    headerView
                    Divider()
                    contentView
                    Divider()
                    inputAreaView
                }
                .frame(minWidth: 324, maxWidth: showAgentList ? .infinity : geometry.size.width)
                
                if showAgentList {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(width: 1)
                    
                    AgentListView(
                        coordinator: coordinator,
                        selectedChatId: $selectedChatId,
                        onNewAgent: {
                            let agent = coordinator.addAgent()
                            selectedChatId = agent.id
                        }
                    )
                    .frame(minWidth: 178, maxWidth: 243)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .preference(key: AgentPanelMinWidthKey.self, value: showAgentList ? 502 : 324)
        .onAppear {
            DispatchQueue.main.async {
                if selectedChatId == nil, let first = coordinator.agents.first {
                    selectedChatId = first.id
                }
                if coordinator.agentNeedingApprovalId != nil {
                    showApprovalDialog = true
                }
            }
        }
        .onChange(of: coordinator.agentNeedingApprovalId) { _, newValue in
            DispatchQueue.main.async { showApprovalDialog = newValue != nil }
        }
        .sheet(isPresented: $showApprovalDialog) {
            if let agent = coordinator.agentNeedingApproval, let decision = agent.pendingApproval {
                AgentApprovalDialog(
                    decision: decision,
                    reason: agent.pendingApprovalReason ?? "This action requires approval",
                    onApprove: {
                        agent.resumeWithApproval(true)
                        showApprovalDialog = false
                    },
                    onDeny: {
                        agent.resumeWithApproval(false)
                        showApprovalDialog = false
                    }
                )
            }
        }
    }
    
    // MARK: - Header
    
    private var agentRulesFileName: String? {
        guard let url = editorViewModel.rootFolderURL else { return nil }
        return SpecPromptAssemblyService.loadedRulesFileName(workspaceRootURL: url)
    }
    
    private var agentIsLocalMode: Bool {
        localOnlyService.isLocalModeEnabled
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
            Text("Autonomous Agent")
                .font(.headline)
            
            if let agent = selectedAgent {
                if agent.isRunning {
                    AgentStatusLabel(agent: agent)
                } else if !agent.steps.isEmpty {
                    Text("\(agent.steps.count) step\(agent.steps.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let name = agentRulesFileName {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .help("Workspace rules loaded")
            }
            
            Text(agentIsLocalMode ? "Local" : "Cloud")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(agentIsLocalMode ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((agentIsLocalMode ? Color.green : Color.clear).opacity(0.12))
                .cornerRadius(4)
                .help(agentIsLocalMode ? "Using local model" : "Using cloud API")
            
            Spacer()
            
            if let agent = selectedAgent, agent.isRunning {
                Button("Stop") { agent.cancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            
            Button(action: {
                // #region agent log
                let line = "{\"sessionId\":\"0a8696\",\"location\":\"AgentModeView.swift:toggle\",\"message\":\"Hide/Show list tapped\",\"data\":{\"before\":\(showAgentList)}\",\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000)),\"hypothesisId\":\"H2\"}\n"
                AgentModeView.appendLog(line)
                // #endregion
                showAgentList.toggle()
            }) {
                Image(systemName: showAgentList ? "sidebar.right" : "sidebar.left")
                    .foregroundColor(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(showAgentList ? "Hide Agent List" : "Show Agent List")
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        if selectedAgent?.pendingApproval != nil {
            approvalPendingView
        } else if let agent = selectedAgent {
            if agent.isRunning || !agent.steps.isEmpty {
                AgentStepsView(agent: agent, lastStepCount: $lastStepCount, bottomID: bottomID, projectURL: editorViewModel.rootFolderURL, onOpenFile: { path in
                    guard let root = editorViewModel.rootFolderURL else { return }
                    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
                    editorViewModel.openFile(at: url)
                })
            } else {
                emptyStateView
            }
        } else if let sid = selectedChatId, let historyItem = historyService.getAgent(by: sid) {
            AgentHistoryDetailView(agent: historyItem)
        } else if let firstRunning = coordinator.agents.first(where: { $0.isRunning }) {
            AgentStepsView(agent: firstRunning, lastStepCount: $lastStepCount, bottomID: bottomID, projectURL: editorViewModel.rootFolderURL, onOpenFile: { path in
                    guard let root = editorViewModel.rootFolderURL else { return }
                    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
                    editorViewModel.openFile(at: url)
                })
        } else {
            emptyStateView
        }
    }
    
    private var approvalPendingView: some View {
        VStack(spacing: 12) {
            Text("Waiting for your approval")
                .font(.headline)
            Text("The agent wants to run an action (e.g. a terminal command). Approve or deny in the dialog, or use the button below.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Review action") { showApprovalDialog = true }
                .buttonStyle(.borderedProminent)
            AgentStepsView(agent: selectedAgent!, lastStepCount: $lastStepCount, bottomID: bottomID, projectURL: editorViewModel.rootFolderURL, onOpenFile: { path in
                    guard let root = editorViewModel.rootFolderURL else { return }
                    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
                    editorViewModel.openFile(at: url)
                })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Start an autonomous task")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("The agent will think, act, and observe iteratively")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Input Area
    
    private var inputAreaView: some View {
        VStack(spacing: 8) {
            if !imageContextService.attachedImages.isEmpty {
                attachedImagesView
            }
            
            if !activeMentions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeMentions) { mention in
                            MentionBadgeView(mention: mention) {
                                activeMentions.removeAll { $0.id == mention.id }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
            
            HStack(spacing: 8) {
                Button(action: { showMentionPopup = true }) {
                    Image(systemName: "at")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add context (@file, @codebase, etc.)")
                .popover(isPresented: $showMentionPopup, arrowEdge: .top) {
                    MentionPopupView(
                        isVisible: $showMentionPopup,
                        onSelect: { type in
                            if type == .file {
                                showMentionPopup = false
                                showFilePicker = true
                            } else {
                                addMention(type)
                            }
                        },
                        editorViewModel: editorViewModel
                    )
                }
                .sheet(isPresented: $showFilePicker) {
                    FileMentionPickerView(
                        editorViewModel: editorViewModel,
                        onSelect: { filePath in
                            let mention = Mention(
                                type: .file,
                                value: filePath,
                                displayName: "@file:\(filePath)"
                            )
                            if !activeMentions.contains(where: { $0.type == .file && $0.value == filePath }) {
                                activeMentions.append(mention)
                            }
                        },
                        isVisible: $showFilePicker
                    )
                }
                
                Button(action: openImagePicker) {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Attach image")
                
                TextField("Describe the task, @ for context", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...3)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .onSubmit { if !inputText.isEmpty || !activeMentions.isEmpty { startTask() } }
                    .onChange(of: inputText) { _, newValue in
                        if newValue.hasSuffix("@") {
                            showMentionPopup = true
                        }
                    }
                    .help("Cmd+Return to send. Type @ to add file/codebase/selection context.")
                
                Button(action: { if !inputText.isEmpty || !activeMentions.isEmpty { startTask() } }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(inputText.isEmpty || targetAgent == nil ? .secondary : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled((inputText.isEmpty && activeMentions.isEmpty) || targetAgent == nil)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (Cmd+Return)")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDraggingOver ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .onDrop(of: [.image, .fileURL], isTargeted: $isDraggingOver) { providers in
            Task { _ = await handleImageDrop(providers: providers) }
            return true
        }
    }
    
    private var attachedImagesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(imageContextService.attachedImages, id: \.id) { image in
                    AttachedImageThumbnail(
                        image: image,
                        onRemove: { imageContextService.removeImage(image.id) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 70)
    }
    
    // MARK: - Actions
    
    private func startTask() {
        guard let agent = targetAgent else { return }
        var taskDescription = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = imageContextService.attachedImages
        let mentions = activeMentions
        guard !taskDescription.isEmpty || !mentions.isEmpty else { return }
        if taskDescription.isEmpty && !mentions.isEmpty {
            taskDescription = "Use the attached context and suggest or apply changes as appropriate."
        }
        inputText = ""
        activeMentions.removeAll()
        lastStepCount = 0
        selectedChatId = agent.id

        Task { @MainActor in
            var context = await editorViewModel.getContextForAI() ?? ""
            if !mentions.isEmpty {
                let mentionContext = await MentionParser.shared.buildContextFromMentionsAsync(
                    mentions,
                    projectURL: editorViewModel.rootFolderURL,
                    selectedText: editorViewModel.editorState.selectedText,
                    terminalOutput: nil
                )
                if !mentionContext.isEmpty {
                    context = mentionContext + "\n\n" + (context.isEmpty ? "" : "--- Editor context ---\n" + context)
                }
            }
            agent.runTask(
                taskDescription,
                projectURL: editorViewModel.rootFolderURL,
                context: context.isEmpty ? nil : context,
                images: images,
                onStepUpdate: { _ in },
                onComplete: { result in
                    if result.success {
                        print("Agent task completed successfully")
                    } else {
                        print("Agent task failed: \(result.error ?? "Unknown error")")
                    }
                    imageContextService.clearImages()
                }
            )
        }
    }
    
    private func addMention(_ type: MentionType) {
        var value = ""
        var displayName = type.rawValue
        switch type {
        case .selection:
            let selection = editorViewModel.editorState.selectedText
            if !selection.isEmpty {
                value = selection
                displayName = "@selection"
            }
        case .file:
            displayName = "@file:\(value)"
        case .folder:
            if let url = editorViewModel.rootFolderURL {
                value = url.path
                displayName = "@folder:\(url.lastPathComponent)"
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
        if !activeMentions.contains(where: { $0.type == type && $0.value == value }) {
            activeMentions.append(mention)
        }
        showMentionPopup = false
    }
    
    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP]
        panel.message = "Select images to attach"
        panel.prompt = "Attach"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = imageContextService.addFromFile(url)
            }
        }
    }
    
    private func handleImageDrop(providers: [NSItemProvider]) async -> Bool {
        var handled = false
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                        Task { @MainActor in
                            if error == nil {
                                if let data = item as? Data,
                                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                                    _ = imageContextService.addFromFile(url)
                                } else if let url = item as? URL {
                                    _ = imageContextService.addFromFile(url)
                                }
                            }
                            continuation.resume()
                        }
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                        Task { @MainActor in
                            if error == nil {
                                if let url = item as? URL {
                                    _ = imageContextService.addFromFile(url)
                                } else if let data = item as? Data, let image = NSImage(data: data) {
                                    _ = imageContextService.addImage(image, source: .dragDrop)
                                } else if let image = item as? NSImage {
                                    _ = imageContextService.addImage(image, source: .dragDrop)
                                }
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

// MARK: - Agent Status Label

struct AgentStatusLabel: View {
    @ObservedObject var agent: AgentService
    
    var body: some View {
        Text(agent.streamingText.isEmpty ? "Connecting..." : "Streaming...")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
