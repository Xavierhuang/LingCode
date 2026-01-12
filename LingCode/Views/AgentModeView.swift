//
//  AgentModeView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// Agent Mode UI - Autonomous task execution like Cursor
struct AgentModeView: View {
    @StateObject private var agent = AgentService.shared
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var taskInput: String = ""
    @State private var showAgentPanel: Bool = false
    @State private var activeMentions: [Mention] = []
    @StateObject private var imageContextService = ImageContextService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.purple)
                Text("Agent Mode")
                    .font(.headline)
                
                Spacer()
                
                if agent.isRunning {
                    Button(action: { agent.cancel() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            
            Divider()
            
            // Steps display
            if !agent.steps.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(agent.steps) { step in
                            AgentStepRow(step: step)
                        }
                    }
                    .padding()
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Agent Mode")
                        .font(.headline)
                    
                    Text("Let AI autonomously complete multi-step tasks.\nIt can generate code, run commands, and search the web.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Example tasks
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example tasks:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(exampleTasks, id: \.self) { task in
                            Button(action: { taskInput = task }) {
                                HStack {
                                    Image(systemName: "arrow.right.circle")
                                        .font(.caption)
                                    Text(task)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .foregroundColor(.purple)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            
            Divider()
            
            // Input with support for @ mentions and images
            VStack(spacing: 0) {
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
                
                // Input field with @ mention support
                HStack(alignment: .bottom) {
                    Button(action: { }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add context")
                    
                    TextField("Describe your task...", text: $taskInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .onSubmit { runTask() }
                        .onChange(of: taskInput) { _, newValue in
                            // Check for @ trigger for mentions
                            if newValue.hasSuffix("@") {
                                // Could show mention popup here if needed
                            }
                        }
                    
                    Button(action: runTask) {
                        Image(systemName: agent.isRunning ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(agent.isRunning ? .red : .purple)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(taskInput.isEmpty && activeMentions.isEmpty && imageContextService.attachedImages.isEmpty || agent.isRunning)
                    .help(agent.isRunning ? "Stop" : "Run task")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onDrop(of: [.image, .fileURL], isTargeted: .constant(false)) { providers in
                    Task {
                        _ = await handleImageDrop(providers: providers)
                    }
                    return true
                }
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
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
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
    
    private var exampleTasks: [String] {
        [
            "Create a simple REST API with Express",
            "Set up a React project with TypeScript",
            "Create a Python CLI tool for file renaming",
            "Initialize a Swift package with tests",
            "Add authentication to my project"
        ]
    }
    
    private func runTask() {
        guard !taskInput.isEmpty || !activeMentions.isEmpty || !imageContextService.attachedImages.isEmpty else { return }
        
        // Build context from mentions
        var context = editorViewModel.getContextForAI() ?? ""
        let mentionContext = MentionParser.shared.buildContextFromMentions(
            activeMentions,
            projectURL: editorViewModel.rootFolderURL,
            selectedText: editorViewModel.editorState.selectedText,
            terminalOutput: nil
        )
        context += mentionContext
        
        // Combine task input with context
        var fullTask = taskInput
        if !context.isEmpty {
            fullTask += "\n\nContext:\n\(context)"
        }
        
        let task = fullTask
        taskInput = ""
        activeMentions.removeAll()
        imageContextService.clearImages()
        
        agent.runTask(
            task,
            projectURL: editorViewModel.rootFolderURL,
            context: context.isEmpty ? nil : context,
            onStepUpdate: { step in
                // Steps are updated in agent.steps automatically
            },
            onComplete: { result in
                if result.success {
                    // Notify about created files
                    if !result.createdFiles.isEmpty {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("FilesCreated"),
                            object: nil,
                            userInfo: ["files": result.createdFiles]
                        )
                    }
                }
            }
        )
    }
}

struct AgentStepRow: View {
    let step: AgentStep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Status icon
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .frame(width: 20)
                
                // Type icon
                Image(systemName: step.type.icon)
                    .foregroundColor(.purple)
                
                Text(step.type.rawValue)
                    .font(.headline)
                
                Spacer()
                
                if step.status == .running {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            Text(step.description)
                .font(.body)
                .foregroundColor(.secondary)
            
            // Output
            if let output = step.output, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }
            
            // Result or error
            if let result = step.result {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            if let error = step.error {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var statusIcon: String {
        switch step.status {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "slash.circle"
        }
    }
    
    private var statusColor: Color {
        switch step.status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

// MARK: - Terminal Execution View

struct TerminalExecutionView: View {
    @StateObject private var terminal = TerminalExecutionService.shared
    @State private var commandInput: String = ""
    let projectURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            // Output
            ScrollView {
                Text(terminal.output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Input
            HStack {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                
                TextField("Enter command...", text: $commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { runCommand() }
                
                if terminal.isExecuting {
                    Button(action: { terminal.cancel() }) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button(action: runCommand) {
                        Image(systemName: "return")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(commandInput.isEmpty)
                }
            }
            .padding()
        }
    }
    
    private func runCommand() {
        guard !commandInput.isEmpty else { return }
        
        let command = commandInput
        commandInput = ""
        
        terminal.execute(
            command,
            workingDirectory: projectURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { _ in }
        )
    }
}

// MARK: - Apply Changes View

struct ApplyChangesView: View {
    @StateObject private var applyService = ApplyCodeService.shared
    @Environment(\.dismiss) private var dismiss
    
    let changes: [CodeChange]
    let onApply: ([URL]) -> Void
    
    @State private var selectedChanges: Set<UUID>
    
    init(changes: [CodeChange], onApply: @escaping ([URL]) -> Void) {
        self.changes = changes
        self.onApply = onApply
        self._selectedChanges = State(initialValue: Set(changes.map { $0.id }))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.badge.plus")
                    .foregroundColor(.accentColor)
                Text("Apply Changes")
                    .font(.headline)
                
                Spacer()
                
                Text("\(selectedChanges.count)/\(changes.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Changes list
            List {
                ForEach(changes) { change in
                    ChangeRow(
                        change: change,
                        isSelected: selectedChanges.contains(change.id),
                        onToggle: {
                            if selectedChanges.contains(change.id) {
                                selectedChanges.remove(change.id)
                            } else {
                                selectedChanges.insert(change.id)
                            }
                        }
                    )
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Select All") {
                    selectedChanges = Set(changes.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("Apply Selected") {
                    applyChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedChanges.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
    
    private func applyChanges() {
        let selectedChangesList = changes.filter { selectedChanges.contains($0.id) }
        applyService.setPendingChanges(selectedChangesList)
        
        applyService.applyAllChanges(
            onProgress: { _, _ in },
            onComplete: { result in
                onApply(result.appliedFiles)
                dismiss()
            }
        )
    }
}

struct ChangeRow: View {
    let change: CodeChange
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var showDiff: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Image(systemName: iconForOperation)
                    .foregroundColor(colorForOperation)
                
                VStack(alignment: .leading) {
                    Text(change.fileName)
                        .font(.headline)
                    Text(change.changeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Line changes
                HStack(spacing: 4) {
                    if change.addedLines > 0 {
                        Text("+\(change.addedLines)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if change.removedLines > 0 {
                        Text("-\(change.removedLines)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: { showDiff.toggle() }) {
                    Image(systemName: showDiff ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if showDiff {
                ScrollView {
                    Text(ApplyCodeService.shared.generateDiff(for: change))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var iconForOperation: String {
        switch change.operationType {
        case .create: return "plus.circle.fill"
        case .update: return "pencil.circle.fill"
        case .append: return "text.append"
        case .delete: return "minus.circle.fill"
        }
    }
    
    private var colorForOperation: Color {
        switch change.operationType {
        case .create: return .green
        case .update: return .blue
        case .append: return .orange
        case .delete: return .red
        }
    }
}

// MARK: - Image Attachment View

struct ImageAttachmentView: View {
    @StateObject private var imageService = ImageContextService.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if !imageService.attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageService.attachedImages) { image in
                            AttachedImageThumbnail(image: image) {
                                imageService.removeImage(image.id)
                            }
                        }
                    }
                }
                .frame(height: 60)
            }
            
            HStack(spacing: 8) {
                Button(action: { _ = imageService.addFromClipboard() }) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: selectFile) {
                    Label("Browse", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { imageService.takeScreenshot(type: .window) }) {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if !imageService.attachedImages.isEmpty {
                    Button(action: { imageService.clearImages() }) {
                        Label("Clear", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = imageService.addFromFile(url)
            }
        }
    }
}

struct AttachedImageThumbnail: View {
    let image: AttachedImage
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 4, y: -4)
        }
    }
}

