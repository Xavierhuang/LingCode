//
//  AgentModeView.swift
//  LingCode
//
//  Main view for the autonomous agent interface
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AgentModeView: View {
    @StateObject private var coordinator = AgentCoordinator.shared
    @StateObject private var imageContextService = ImageContextService.shared
    @StateObject private var historyService = AgentHistoryService.shared
    @State private var inputText: String = ""
    @State private var lastStepCount: Int = 0
    @Namespace private var bottomID
    @State private var showApprovalDialog = false
    @State private var selectedChatId: UUID?
    @State private var showAgentList: Bool = true
    @State private var isDraggingOver: Bool = false
    
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
            HSplitView {
                VStack(spacing: 0) {
                    headerView
                    Divider()
                    contentView
                    Divider()
                    inputAreaView
                }
                .frame(width: showAgentList ? geometry.size.width / 2 : geometry.size.width)
                
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
                    .frame(width: geometry.size.width / 2)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if selectedChatId == nil, let first = coordinator.agents.first {
                selectedChatId = first.id
            }
            if coordinator.agentNeedingApprovalId != nil {
                showApprovalDialog = true
            }
        }
        .onChange(of: coordinator.agentNeedingApprovalId) { _, newValue in
            showApprovalDialog = newValue != nil
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
    
    private var headerView: some View {
        HStack {
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
            
            Spacer()
            
            if let agent = selectedAgent, agent.isRunning {
                Button("Stop") { agent.cancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            
            Button(action: { showAgentList.toggle() }) {
                Image(systemName: showAgentList ? "sidebar.right" : "sidebar.left")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
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
                AgentStepsView(agent: agent, lastStepCount: $lastStepCount, bottomID: bottomID)
            } else {
                emptyStateView
            }
        } else if let sid = selectedChatId, let historyItem = historyService.getAgent(by: sid) {
            AgentHistoryDetailView(agent: historyItem)
        } else if let firstRunning = coordinator.agents.first(where: { $0.isRunning }) {
            AgentStepsView(agent: firstRunning, lastStepCount: $lastStepCount, bottomID: bottomID)
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
            AgentStepsView(agent: selectedAgent!, lastStepCount: $lastStepCount, bottomID: bottomID)
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
            
            HStack(spacing: 8) {
                Button(action: openImagePicker) {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Attach image")
                
                TextField("Describe the task...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...3)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .onSubmit { if !inputText.isEmpty { startTask() } }
                    .help("Cmd+Return to send (Return alone adds a new line)")
                
                Button(action: { if !inputText.isEmpty { startTask() } }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(inputText.isEmpty || targetAgent == nil ? .secondary : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(inputText.isEmpty || targetAgent == nil)
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
        let taskDescription = inputText
        let images = imageContextService.attachedImages
        inputText = ""
        lastStepCount = 0
        selectedChatId = agent.id

        Task { @MainActor in
            let context = await editorViewModel.getContextForAI()
            agent.runTask(
                taskDescription,
                projectURL: editorViewModel.rootFolderURL,
                context: context,
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
