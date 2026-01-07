//
//  PremiumAIView.swift
//  LingCode
//
//  Premium Cursor-level AI experience with polished UI
//

import SwiftUI

/// Premium AI assistant view with Cursor-level polish
struct PremiumAIView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var expandedSections: Set<String> = ["thinking", "files"]
    @State private var selectedFileId: String?
    @State private var hoveredFileId: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Premium header
            premiumHeader
            
            // Main content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Status card
                        if viewModel.isLoading || !viewModel.currentActions.isEmpty {
                            StatusCard(viewModel: viewModel)
                                .id("status")
                        }
                        
                        // Thinking steps
                        if !viewModel.thinkingSteps.isEmpty || viewModel.isLoading {
                            ThinkingCard(
                                steps: viewModel.thinkingSteps,
                                isLoading: viewModel.isLoading,
                                isExpanded: expandedSections.contains("thinking"),
                                onToggle: { toggleSection("thinking") },
                                onStop: { viewModel.cancelGeneration() }
                            )
                        }
                        
                        // File changes
                        if !viewModel.currentActions.isEmpty {
                            FileChangesCard(
                                actions: viewModel.currentActions,
                                selectedFileId: $selectedFileId,
                                hoveredFileId: $hoveredFileId,
                                isExpanded: expandedSections.contains("files"),
                                onToggle: { toggleSection("files") },
                                onOpen: { action in openFile(action) },
                                onApply: { action in applyFile(action) },
                                onReject: { action in rejectFile(action) },
                                onApplyAll: applyAll,
                                onRejectAll: rejectAll
                            )
                        }
                        
                        // Response streaming
                        if viewModel.isLoading {
                            StreamingCard(viewModel: viewModel)
                                .id("streaming")
                        }
                        
                        // Empty state
                        if !viewModel.isLoading && viewModel.currentActions.isEmpty && viewModel.thinkingSteps.isEmpty {
                            EmptyStateCard()
                        }
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.thinkingSteps.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            
            // Input area
            PremiumInputArea(
                input: $viewModel.currentInput,
                isLoading: viewModel.isLoading,
                contextFile: editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent,
                onSend: sendMessage,
                onStop: { viewModel.cancelGeneration() }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Premium Header
    
    private var premiumHeader: some View {
        HStack(spacing: 12) {
            // Logo/Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Assistant")
                    .font(.system(size: 14, weight: .semibold))
                
                if viewModel.isLoading {
                    Text("Working...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if !viewModel.currentActions.isEmpty {
                    Text("\(viewModel.currentActions.count) changes ready")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                HeaderButton(icon: "plus", tooltip: "New Chat") {
                    viewModel.clearConversation()
                }
                
                HeaderButton(icon: "ellipsis", tooltip: "Options") {
                    // Show menu
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.primary.opacity(0.05)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Actions
    
    private func toggleSection(_ section: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        }
    }
    
    private func sendMessage() {
        let context = editorViewModel.getContextForAI()
        viewModel.sendMessage(context: context, projectURL: editorViewModel.rootFolderURL)
    }
    
    private func openFile(_ action: AIAction) {
        let fileName = action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
        
        if let content = action.result, let projectURL = editorViewModel.rootFolderURL {
            let fileURL = projectURL.appendingPathComponent(fileName)
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            editorViewModel.openFile(at: fileURL)
        }
    }
    
    private func applyFile(_ action: AIAction) {
        openFile(action)
    }
    
    private func rejectFile(_ action: AIAction) {
        // Just remove from view, don't write file
    }
    
    private func applyAll() {
        for action in viewModel.currentActions {
            applyFile(action)
        }
    }
    
    private func rejectAll() {
        viewModel.currentActions.removeAll()
    }
}

// MARK: - Header Button

struct HeaderButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    @ObservedObject var viewModel: AIViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                if viewModel.isLoading {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.isLoading)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isLoading ? "Processing..." : "Changes Ready")
                    .font(.system(size: 13, weight: .semibold))
                
                if !viewModel.currentActions.isEmpty {
                    Text("\(viewModel.currentActions.count) file\(viewModel.currentActions.count == 1 ? "" : "s") modified")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    Text("Stop")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
    }
}

// MARK: - Thinking Card

struct ThinkingCard: View {
    let steps: [AIThinkingStep]
    let isLoading: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                    
                    Text("Thinking")
                        .font(.system(size: 13, weight: .semibold))
                    
                    if isLoading {
                        LoadingDots()
                    }
                    
                    Spacer()
                    
                    if isLoading {
                        Button(action: onStop) {
                            Text("Stop")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(14)
            .background(Color.purple.opacity(0.08))
            
            // Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps) { step in
                        PremiumThinkingStepView(step: step)
                    }
                    
                    if steps.isEmpty && isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Analyzing your request...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PremiumThinkingStepView: View {
    let step: AIThinkingStep
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stepTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(iconColor)
                
                Text(step.content)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if step.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
            }
        }
    }
    
    private var iconName: String {
        switch step.type {
        case .planning: return "list.bullet"
        case .thinking: return "brain"
        case .action: return "gearshape"
        case .result: return "doc.text"
        case .complete: return "checkmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch step.type {
        case .planning: return .blue
        case .thinking: return .purple
        case .action: return .orange
        case .result, .complete: return .green
        }
    }
    
    private var stepTitle: String {
        switch step.type {
        case .planning: return "Planning"
        case .thinking: return "Thinking"
        case .action: return "Action"
        case .result: return "Result"
        case .complete: return "Complete"
        }
    }
}

// MARK: - File Changes Card

struct FileChangesCard: View {
    let actions: [AIAction]
    @Binding var selectedFileId: String?
    @Binding var hoveredFileId: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: (AIAction) -> Void
    let onApply: (AIAction) -> Void
    let onReject: (AIAction) -> Void
    let onApplyAll: () -> Void
    let onRejectAll: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    Text("File Changes")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("\(actions.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(14)
            .background(Color.orange.opacity(0.08))
            
            // Content
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        PremiumFileRow(
                            action: action,
                            isSelected: selectedFileId == action.id.uuidString,
                            isHovered: hoveredFileId == action.id.uuidString,
                            onSelect: { selectedFileId = action.id.uuidString },
                            onHover: { hovering in
                                hoveredFileId = hovering ? action.id.uuidString : nil
                            },
                            onOpen: { onOpen(action) },
                            onApply: { onApply(action) },
                            onReject: { onReject(action) }
                        )
                    }
                    
                    // Bulk actions
                    HStack(spacing: 8) {
                        Spacer()
                        
                        Button(action: onRejectAll) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Reject All")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: onApplyAll) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Accept All")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.top, 8)
                }
                .padding(14)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PremiumFileRow: View {
    let action: AIAction
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    let onOpen: () -> Void
    let onApply: () -> Void
    let onReject: () -> Void
    
    @State private var showContent = false
    
    private var fileName: String {
        action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    private var isNew: Bool {
        action.name.hasPrefix("Create ")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // File header
            HStack(spacing: 10) {
                // File icon
                Image(systemName: fileIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                // File name
                Text(fileName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                
                // Badge
                Text(isNew ? "NEW" : "MODIFIED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isNew ? Color.green : Color.orange)
                    .cornerRadius(3)
                
                Spacer()
                
                // Actions
                if isHovered || isSelected {
                    HStack(spacing: 6) {
                        MiniButton(icon: "arrow.up.right.square", color: .blue) {
                            onOpen()
                        }
                        
                        MiniButton(icon: "xmark", color: .red) {
                            onReject()
                        }
                        
                        MiniButton(icon: "checkmark", color: .green, filled: true) {
                            onApply()
                        }
                    }
                }
                
                // Expand
                Button(action: { showContent.toggle() }) {
                    Image(systemName: showContent ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered || isSelected ? Color.primary.opacity(0.04) : Color.clear)
            )
            .onTapGesture { onSelect() }
            .onHover { hovering in onHover(hovering) }
            
            // Code preview
            if showContent, let content = action.result {
                CodePreviewView(content: content, fileName: fileName, isNew: isNew)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showContent)
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces.square"
        case "py": return "terminal"
        case "html": return "chevron.left.slash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        case "md": return "text.justify"
        default: return "doc.fill"
        }
    }
}

struct MiniButton: View {
    let icon: String
    let color: Color
    var filled: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(filled ? .white : color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(filled ? color : (isHovered ? color.opacity(0.15) : Color.clear))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in isHovered = hovering }
    }
}

struct CodePreviewView: View {
    let content: String
    let fileName: String
    let isNew: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language bar
            HStack {
                Text(languageName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Code
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let lines = content.components(separatedBy: .newlines)
                    ForEach(Array(lines.prefix(30).enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 28, alignment: .trailing)
                                .padding(.trailing, 8)
                            
                            Text(isNew ? "+" : " ")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(width: 12)
                            
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.vertical, 1)
                        .background(isNew ? Color.green.opacity(0.08) : Color.clear)
                    }
                    
                    if lines.count > 30 {
                        Text("... \(lines.count - 30) more lines")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                            .padding(.leading, 48)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 200)
            .background(Color(NSColor.textBackgroundColor))
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
    
    private var languageName: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift"
        case "js", "jsx": return "JavaScript"
        case "ts", "tsx": return "TypeScript"
        case "py": return "Python"
        case "html": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "md": return "Markdown"
        default: return ext.uppercased()
        }
    }
}

// MARK: - Streaming Card

struct StreamingCard: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 10) {
                    LoadingDots()
                    
                    Text("Generating response...")
                        .font(.system(size: 13, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(14)
            .background(Color.blue.opacity(0.08))
            
            if isExpanded, let message = viewModel.conversation.messages.last(where: { $0.role == .assistant }) {
                ScrollView {
                    Text(message.content)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: 150)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Empty State Card

struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 4) {
                Text("Ready to help")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("Ask me to edit, explain, or generate code")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Premium Input Area

struct PremiumInputArea: View {
    @Binding var input: String
    let isLoading: Bool
    let contextFile: String?
    let onSend: () -> Void
    let onStop: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Context indicator
            if let file = contextFile {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    
                    Text(file)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            
            // Input
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask AI to edit your code...", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .onSubmit {
                        if !input.isEmpty && !isLoading {
                            onSend()
                        }
                    }
                
                Button(action: {
                    if isLoading {
                        onStop()
                    } else if !input.isEmpty {
                        onSend()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isLoading ? Color.red : (input.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isLoading && input.isEmpty)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Loading Dots

struct LoadingDots: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

