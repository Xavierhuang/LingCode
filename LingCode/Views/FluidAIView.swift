//
//  FluidAIView.swift
//  LingCode
//
//  Cursor-like fluid AI experience - auto-applies changes, no batch approval
//

import SwiftUI

/// Fluid AI view that auto-applies changes like Cursor
struct FluidAIView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    @StateObject private var rulesService = LingCodeRulesService.shared
    @StateObject private var indexService = CodebaseIndexService.shared
    
    @State private var autoApply = true
    @State private var appliedFiles: Set<String> = []
    @State private var showDiffFor: AIAction?
    @State private var originalContents: [String: String] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimal header
            fluidHeader
            
            // Main content - simple scrolling list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Show conversation messages inline
                        ForEach(viewModel.conversation.messages) { message in
                            FluidMessageRow(
                                message: message,
                                isStreaming: viewModel.isLoading && message.id == viewModel.conversation.messages.last?.id
                            )
                        }
                        
                        // Show file changes as they happen
                        ForEach(viewModel.currentActions) { action in
                            FluidFileChange(
                                action: action,
                                isApplied: appliedFiles.contains(action.id.uuidString),
                                onOpen: { openAndApply(action) },
                                onUndo: { undoChange(action) }
                            )
                            .id(action.id)
                            .onAppear {
                                // Auto-apply when file appears
                                if autoApply && !appliedFiles.contains(action.id.uuidString) {
                                    applyChange(action)
                                }
                            }
                        }
                        
                        // Loading indicator
                        if viewModel.isLoading {
                            FluidLoadingView()
                                .id("loading")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.currentActions.count) { _, _ in
                    if let lastAction = viewModel.currentActions.last {
                        withAnimation {
                            proxy.scrollTo(lastAction.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        withAnimation {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Simple input
            fluidInput
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var fluidHeader: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(viewModel.isLoading ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
            
            Text(viewModel.isLoading ? "Working..." : "Ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if viewModel.isLoading {
                Button("Stop") {
                    viewModel.cancelGeneration()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.red)
            }
            
            // Auto-apply toggle
            Toggle("Auto-apply", isOn: $autoApply)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)
            
            Button(action: { viewModel.clearConversation() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Input
    
    private var fluidInput: some View {
        HStack(spacing: 8) {
            // Context indicator
            if let file = editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent {
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 10))
                    Text(file)
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
            
            TextField("What do you want to do?", text: $viewModel.currentInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { sendMessage() }
            
            Button(action: {
                if viewModel.isLoading {
                    viewModel.cancelGeneration()
                } else {
                    sendMessage()
                }
            }) {
                Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(viewModel.isLoading ? Color.red : (viewModel.currentInput.isEmpty ? Color.gray : Color.accentColor))
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!viewModel.isLoading && viewModel.currentInput.isEmpty)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(8)
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty else { return }
        appliedFiles.removeAll() // Reset for new request
        originalContents.removeAll()
        
        // FIX: Build context asynchronously
        Task { @MainActor in
            var context = await editorViewModel.getContextForAI() ?? ""
            
            // Add project rules if available
            if let rules = rulesService.getRulesForAI() {
                context = rules + "\n\n" + context
            }
            
            // Add codebase overview for smarter responses
            if indexService.totalSymbolCount > 0 {
                context = indexService.generateCodebaseOverview() + "\n\n" + context
            }
            
            viewModel.sendMessage(context: context, projectURL: editorViewModel.rootFolderURL)
        }
    }
    
    private func applyChange(_ action: AIAction) {
        // Get content from fileContent (preferred) or result
        guard let content = action.fileContent ?? action.result,
              let projectURL = editorViewModel.rootFolderURL else { return }
        
        // Use filePath if available, otherwise extract from name
        let fileName: String
        if let path = action.filePath, !path.isEmpty {
            fileName = path
        } else {
            fileName = action.name
                .replacingOccurrences(of: "Create ", with: "")
                .replacingOccurrences(of: "Modify ", with: "")
        }
        
        let fileURL = projectURL.appendingPathComponent(fileName)
        let directory = fileURL.deletingLastPathComponent()
        
        // Store original content for undo
        if FileManager.default.fileExists(atPath: fileURL.path) {
            originalContents[action.id.uuidString] = try? String(contentsOf: fileURL, encoding: .utf8)
        }
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            appliedFiles.insert(action.id.uuidString)
            action.status = .completed
            action.result = "Applied"
            
            // Auto-open the file
            editorViewModel.openFile(at: fileURL)
        } catch {
            print("Failed to apply: \(error)")
            action.status = .failed
            action.error = error.localizedDescription
        }
    }
    
    private func openAndApply(_ action: AIAction) {
        if !appliedFiles.contains(action.id.uuidString) {
            applyChange(action)
        } else if let projectURL = editorViewModel.rootFolderURL {
            let fileName: String
            if let path = action.filePath, !path.isEmpty {
                fileName = path
            } else {
                fileName = action.name
                    .replacingOccurrences(of: "Create ", with: "")
                    .replacingOccurrences(of: "Modify ", with: "")
            }
            let fileURL = projectURL.appendingPathComponent(fileName)
            editorViewModel.openFile(at: fileURL)
        }
    }
    
    private func undoChange(_ action: AIAction) {
        guard let projectURL = editorViewModel.rootFolderURL else { return }
        
        let fileName = action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
        let fileURL = projectURL.appendingPathComponent(fileName)
        
        // Restore original or delete if new
        if let original = originalContents[action.id.uuidString] {
            try? original.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
        appliedFiles.remove(action.id.uuidString)
    }
    
    private func showDiff(for action: AIAction) {
        showDiffFor = action
    }
}

// MARK: - Diff Sheet

struct FluidDiffSheet: View {
    let action: AIAction
    let originalContent: String?
    let onAccept: () -> Void
    let onReject: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private var fileName: String {
        action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let newContent = action.result {
                CursorStyleDiffView(
                    originalContent: originalContent,
                    newContent: newContent,
                    fileName: fileName,
                    onAccept: {
                        onAccept()
                        dismiss()
                    },
                    onReject: {
                        onReject()
                        dismiss()
                    }
                )
            } else {
                Text("No content available")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 700, height: 500)
    }
}

// MARK: - Fluid Message Row

struct FluidMessageRow: View {
    let message: AIMessage
    let isStreaming: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Avatar
            Circle()
                .fill(message.role == .user ? Color.secondary.opacity(0.3) : Color.purple.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: message.role == .user ? "person" : "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(message.role == .user ? .secondary : .purple)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Role
                Text(message.role == .user ? "You" : "AI")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                // Content
                Text(message.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                
                if isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Fluid File Change

struct FluidFileChange: View {
    let action: AIAction
    let isApplied: Bool
    let onOpen: () -> Void
    let onUndo: () -> Void
    
    @State private var isExpanded = false
    @State private var isHovered = false
    
    private var fileName: String {
        if let path = action.filePath, !path.isEmpty {
            return path
        }
        return action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    private var hasContent: Bool {
        action.fileContent != nil || action.result != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // File row
            HStack(spacing: 8) {
                // Status
                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.system(size: 14))
                    .foregroundColor(isApplied ? .green : .orange)
                
                // File icon
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                
                // File name
                Text(fileName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                
                // Status text
                Text(isApplied ? "Applied" : "Pending")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isApplied ? .green : .orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isApplied ? Color.green : Color.orange).opacity(0.15))
                    .cornerRadius(4)
                
                Spacer()
                
                // Actions on hover
                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onOpen) {
                            Text("Open")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        if isApplied {
                            Button(action: onUndo) {
                                Text("Undo")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.red)
                        }
                    }
                }
                
                // Expand
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            .onHover { hovering in isHovered = hovering }
            .onTapGesture { onOpen() }
            
            // Preview - show actual file content from AI
            if isExpanded, let content = action.fileContent ?? action.result {
                FluidCodePreview(content: content, fileName: fileName)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "html": return "chevron.left.slash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        default: return "doc.fill"
        }
    }
}

// MARK: - Fluid Code Preview

struct FluidCodePreview: View {
    let content: String
    let fileName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(languageName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: copyCode) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    let lines = content.components(separatedBy: .newlines)
                    ForEach(Array(lines.prefix(20).enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(width: 24, alignment: .trailing)
                                .padding(.trailing, 8)
                            
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.vertical, 1)
                    }
                    
                    if lines.count > 20 {
                        Text("+ \(lines.count - 20) more lines...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                            .padding(.leading, 32)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(NSColor.textBackgroundColor))
        }
        .cornerRadius(4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
    
    private var languageName: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "py": return "Python"
        case "json": return "JSON"
        default: return ext.uppercased()
        }
    }
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}

// MARK: - Fluid Loading View

struct FluidLoadingView: View {
    @State private var dots = ""
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            
            Text("Generating\(dots)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .onAppear {
            animateDots()
        }
    }
    
    private func animateDots() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { timer in
            if dots.count >= 3 {
                dots = ""
            } else {
                dots += "."
            }
        }
    }
}

