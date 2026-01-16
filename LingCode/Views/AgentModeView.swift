//
//  AgentModeView.swift
//  LingCode
//
//  Created for Animated Agent UX
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AgentModeView: View {
    @StateObject private var agentService = AgentService.shared
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var inputText: String = ""
    @State private var lastStepCount: Int = 0
    @Namespace private var bottomID
    @State private var showApprovalDialog = false
    
    @ObservedObject var editorViewModel: EditorViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .symbolEffect(.bounce, value: agentService.isRunning)
                Text("Autonomous Agent")
                    .font(.headline)
                Spacer()
                if agentService.isRunning {
                    Button("Stop") {
                        agentService.cancel()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Steps List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if agentService.steps.isEmpty && !agentService.isRunning {
                            // Empty state
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(agentService.steps) { step in
                                AgentStepRow(step: step)
                                    .id(step.id)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            
                            // Invisible footer to auto-scroll to
                            Color.clear
                                .frame(height: 1)
                                .id(bottomID)
                        }
                    }
                    .padding()
                }
                .onChange(of: agentService.steps.count) { oldCount, newCount in
                    // Auto-scroll when new step is added
                    if newCount > lastStepCount {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                        lastStepCount = newCount
                    }
                }
                .onChange(of: agentService.steps.last?.output) { oldOutput, newOutput in
                    // Auto-scroll when output streams in
                    if let lastStep = agentService.steps.last, lastStep.status == .running {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input Area
            VStack(spacing: 8) {
                // Attached Images
                if !imageContextService.attachedImages.isEmpty {
                    attachedImagesView
                }
                
                HStack(spacing: 8) {
                    // Image attachment button
                    Button(action: {
                        _ = imageContextService.addFromClipboard()
                    }) {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Attach image from clipboard")
                    
                    TextField("Describe the task...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...3)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .onSubmit {
                            if !inputText.isEmpty && !agentService.isRunning {
                                startTask()
                            }
                        }
                    
                    Button(action: {
                        if !inputText.isEmpty && !agentService.isRunning {
                            startTask()
                        }
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(agentService.isRunning || inputText.isEmpty ? .secondary : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(agentService.isRunning || inputText.isEmpty)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                Task {
                    _ = await handleImageDrop(providers: providers)
                }
                return true
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: agentService.pendingApproval) { oldValue, newValue in
            // Show approval dialog when pendingApproval is set
            showApprovalDialog = newValue != nil
        }
        .sheet(isPresented: $showApprovalDialog) {
            if let decision = agentService.pendingApproval {
                AgentApprovalDialog(
                    decision: decision,
                    reason: agentService.pendingApprovalReason ?? "This action requires approval",
                    onApprove: {
                        agentService.resumeWithApproval(true)
                        showApprovalDialog = false
                    },
                    onDeny: {
                        agentService.resumeWithApproval(false)
                        showApprovalDialog = false
                    }
                )
            }
        }
    }
    
    private func startTask() {
        let taskDescription = inputText
        let images = imageContextService.attachedImages
        inputText = ""
        lastStepCount = 0
        
        agentService.runTask(
            taskDescription,
            projectURL: editorViewModel.rootFolderURL,
            context: editorViewModel.getContextForAI(),
            images: images,
            onStepUpdate: { step in
                // Step updated - view will automatically refresh via @Published
            },
            onComplete: { result in
                if result.success {
                    print("✅ Agent task completed successfully")
                } else {
                    print("❌ Agent task failed: \(result.error ?? "Unknown error")")
                }
                // Clear images after task completes
                imageContextService.clearImages()
            }
        )
    }
    
    // MARK: - Attached Images View
    
    private var attachedImagesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(imageContextService.attachedImages, id: \.id) { image in
                    AttachedImageThumbnail(
                        image: image,
                        onRemove: {
                            imageContextService.removeImage(image.id)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 70)
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

struct AgentStepRow: View {
    let step: AgentStep
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Step Header
            HStack(alignment: .top, spacing: 12) {
                StatusIndicator(status: step.status)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.description)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let thought = step.output, !thought.isEmpty, step.status == .running {
                        Text(thought)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let error = step.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    if let result = step.result {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                // Icon for type
                Image(systemName: step.type.icon)
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }
            
            // Streaming Output Box
            if isExpanded, let output = step.output, !output.isEmpty, step.status != .running || output.count > 50 {
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    step.status == .running ? Color.blue.opacity(0.5) : Color.clear,
                    lineWidth: step.status == .running ? 1.5 : 0
                )
        )
        .shadow(
            color: step.status == .running ? Color.blue.opacity(0.1) : Color.clear,
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

struct StatusIndicator: View {
    let status: AgentStepStatus
    
    var body: some View {
        Group {
            switch status {
            case .pending:
                Circle()
                    .strokeBorder(Color.gray, lineWidth: 2)
                    .frame(width: 16, height: 16)
            case .running:
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
            case .cancelled:
                Image(systemName: "slash.circle")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
            }
        }
    }
}

// MARK: - Approval Dialog

struct AgentApprovalDialog: View {
    let decision: AgentDecision
    let reason: String
    let onApprove: () -> Void
    let onDeny: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 24))
                Text("Action Requires Approval")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Reason
            VStack(alignment: .leading, spacing: 8) {
                Text("Reason:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(reason)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Action Details
            VStack(alignment: .leading, spacing: 12) {
                Text("Action Details:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 6) {
                    LabeledRow(label: "Type:", value: decision.action.capitalized)
                    LabeledRow(label: "Description:", value: decision.description)
                    
                    if let command = decision.command {
                        LabeledRow(label: "Command:", value: command)
                    }
                    if let filePath = decision.filePath {
                        LabeledRow(label: "File:", value: filePath)
                    }
                    if let thought = decision.thought {
                        LabeledRow(label: "Reasoning:", value: thought)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Buttons
            HStack(spacing: 12) {
                Button("Deny") {
                    onDeny()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Spacer()
                
                Button("Approve") {
                    onApprove()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Attached Image Thumbnail

struct AttachedImageThumbnail: View {
    let image: AttachedImage
    let onRemove: () -> Void
    
    private var nsImage: NSImage? {
        guard let data = Data(base64Encoded: image.base64) else { return nil }
        return NSImage(data: data)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .cornerRadius(4)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 4, y: -4)
        }
    }
}
