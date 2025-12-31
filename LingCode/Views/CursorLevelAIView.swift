//
//  CursorLevelAIView.swift
//  LingCode
//
//  Cursor-level polished UI with smooth animations and modern design
//

import SwiftUI

/// Cursor-level polished AI assistant view
struct CursorLevelAIView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var hoveredFileId: UUID?
    @State private var expandedFiles: Set<UUID> = []
    @State private var showContextFiles = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Polished header
            polishedHeader
            
            Divider()
            
            // Main content with smooth scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Messages
                        ForEach(viewModel.conversation.messages) { message in
                            PolishedMessageBubble(
                                message: message,
                                isStreaming: viewModel.isLoading && message.id == viewModel.conversation.messages.last?.id
                            )
                            .id(message.id)
                        }
                        
                        // File changes with polish
                        if !viewModel.currentActions.isEmpty {
                            PolishedFileChangesSection(
                                actions: viewModel.currentActions,
                                hoveredFileId: $hoveredFileId,
                                expandedFiles: $expandedFiles,
                                onOpen: { action in openFile(action) },
                                onApply: { action in applyFile(action) },
                                onReject: { action in rejectFile(action) }
                            )
                        }
                        
                        // Loading state
                        if viewModel.isLoading && viewModel.currentActions.isEmpty {
                            PolishedLoadingState()
                                .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .onChange(of: viewModel.conversation.messages.count) { _, _ in
                    if let lastMessage = viewModel.conversation.messages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Polished input area
            PolishedInputArea(
                input: $viewModel.currentInput,
                isLoading: viewModel.isLoading,
                contextFile: editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent,
                showContextFiles: $showContextFiles,
                onSend: sendMessage,
                onStop: { viewModel.cancelGeneration() }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var polishedHeader: some View {
        HStack(spacing: 12) {
            // Status with animation
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(viewModel.isLoading ? Color.blue : Color.green)
                        .frame(width: 8, height: 8)
                    
                    if viewModel.isLoading {
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                            .frame(width: 12, height: 12)
                            .scaleEffect(1.2)
                            .opacity(0.5)
                            .animation(
                                Animation.easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                value: viewModel.isLoading
                            )
                    }
                }
                
                Text(viewModel.isLoading ? "Working..." : "Ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Context files indicator
            if showContextFiles && !getContextFiles().isEmpty {
                Button(action: { showContextFiles.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("\(getContextFiles().count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Stop button (when loading)
            if viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                        Text("Stop")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
            
            // Menu
            Menu {
                Button(action: { viewModel.clearConversation() }) {
                    Label("Clear Chat", systemImage: "trash")
                }
                Divider()
                Toggle("Auto-apply", isOn: .constant(true))
                Toggle("Show Thinking", isOn: $viewModel.showThinkingProcess)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(NSColor.controlBackgroundColor)
                .opacity(0.6)
        )
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty else { return }
        let context = editorViewModel.getContextForAI() ?? ""
        viewModel.sendMessage(context: context, projectURL: editorViewModel.rootFolderURL)
    }
    
    private func openFile(_ action: AIAction) {
        guard let projectURL = editorViewModel.rootFolderURL,
              let filePath = action.filePath else { return }
        let fileURL = projectURL.appendingPathComponent(filePath)
        editorViewModel.openFile(at: fileURL)
    }
    
    private func applyFile(_ action: AIAction) {
        guard let content = action.fileContent ?? action.result,
              let projectURL = editorViewModel.rootFolderURL,
              let filePath = action.filePath else { return }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let directory = fileURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            action.status = .completed
            editorViewModel.openFile(at: fileURL)
        } catch {
            action.status = .failed
            action.error = error.localizedDescription
        }
    }
    
    private func rejectFile(_ action: AIAction) {
        action.status = .failed
    }
    
    private func getContextFiles() -> [String] {
        var files: [String] = []
        if let activeFile = editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent {
            files.append(activeFile)
        }
        return files
    }
}

// MARK: - Polished Message Bubble

struct PolishedMessageBubble: View {
    let message: AIMessage
    let isStreaming: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(message.role == .user ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(message.role == .user ? .blue : .purple)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Role label
                Text(message.role == .user ? "You" : "AI Assistant")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                // Content
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Streaming indicator
                if isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 4, height: 4)
                                .offset(y: i == 1 ? -2 : 0)
                                .animation(
                                    Animation.easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(i) * 0.2),
                                    value: isStreaming
                                )
                        }
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(message.role == .user ? Color.blue.opacity(0.05) : Color.purple.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    message.role == .user ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Polished File Changes Section

struct PolishedFileChangesSection: View {
    let actions: [AIAction]
    @Binding var hoveredFileId: UUID?
    @Binding var expandedFiles: Set<UUID>
    let onOpen: (AIAction) -> Void
    let onApply: (AIAction) -> Void
    let onReject: (AIAction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                Text("\(actions.count) file\(actions.count == 1 ? "" : "s") changed")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // File cards
            ForEach(actions) { action in
                PolishedFileCard(
                    action: action,
                    isHovered: hoveredFileId == action.id,
                    isExpanded: expandedFiles.contains(action.id),
                    onHover: { hovering in
                        hoveredFileId = hovering ? action.id : nil
                    },
                    onToggle: {
                        if expandedFiles.contains(action.id) {
                            expandedFiles.remove(action.id)
                        } else {
                            expandedFiles.insert(action.id)
                        }
                    },
                    onOpen: { onOpen(action) },
                    onApply: { onApply(action) },
                    onReject: { onReject(action) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Polished File Card

struct PolishedFileCard: View {
    let action: AIAction
    let isHovered: Bool
    let isExpanded: Bool
    let onHover: (Bool) -> Void
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onApply: () -> Void
    let onReject: () -> Void
    
    private var fileName: String {
        action.filePath ?? action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        default: return "doc.fill"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // File header
            HStack(spacing: 10) {
                // Status icon
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
                
                // File icon
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                
                // File name
                Text(fileName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                
                // Status badge
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor)
                    .cornerRadius(4)
                
                Spacer()
                
                // Action buttons (show on hover)
                if isHovered {
                    HStack(spacing: 6) {
                        Button(action: onOpen) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.blue)
                        
                        Button(action: onReject) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.red)
                        
                        Button(action: onApply) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Expand button
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(10)
            .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            .onHover { hovering in onHover(hovering) }
            .onTapGesture { onOpen() }
            
            // Expanded content
            if isExpanded, let content = action.fileContent ?? action.result {
                Divider()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(content.components(separatedBy: .newlines).prefix(30).enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .frame(width: 30, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isExpanded)
    }
    
    private var statusIcon: String {
        switch action.status {
        case .pending: return "circle.dotted"
        case .executing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch action.status {
        case .pending: return .orange
        case .executing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private var statusText: String {
        switch action.status {
        case .pending: return "PENDING"
        case .executing: return "APPLYING"
        case .completed: return "APPLIED"
        case .failed: return "FAILED"
        }
    }
}

// MARK: - Polished Loading State

struct PolishedLoadingState: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(
                            Animation.linear(duration: 1)
                                .repeatForever(autoreverses: false)
                        ) {
                            rotation = 360
                        }
                    }
            }
            
            Text("Generating...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Polished Input Area

struct PolishedInputArea: View {
    @Binding var input: String
    let isLoading: Bool
    let contextFile: String?
    @Binding var showContextFiles: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Context file indicator
            if let file = contextFile {
                HStack {
                    Image(systemName: "doc")
                        .font(.system(size: 10))
                    Text(file)
                        .font(.system(size: 11))
                    Spacer()
                    Button(action: { showContextFiles.toggle() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal, 12)
            }
            
            // Input field
            HStack(spacing: 10) {
                // @ mention button
                Button(action: {}) {
                    Image(systemName: "at")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Text field
                TextField("Ask AI...", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !input.isEmpty {
                            onSend()
                        }
                    }
                
                // Send/Stop button
                Button(action: {
                    if isLoading {
                        onStop()
                    } else {
                        onSend()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isLoading ? Color.red : (input.isEmpty ? Color.gray : Color.accentColor))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isLoading && input.isEmpty)
                .animation(.easeOut(duration: 0.2), value: isLoading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear {
            isFocused = true
        }
    }
}

