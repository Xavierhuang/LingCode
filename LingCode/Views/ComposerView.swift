//
//  ComposerView.swift
//  LingCode
//
//  Cursor-style Composer Mode - Edit multiple files at once
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Composer Mode - Multi-file editing interface (like Cursor's Composer)
struct ComposerView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var composerInput: String = ""
    @State private var composerFiles: [ComposerFile] = []
    @State private var selectedFileId: UUID?
    @State private var isGenerating: Bool = false
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var showMentionPopup = false
    @State private var activeMentions: [Mention] = []
    
    
    struct ComposerFile: Identifiable {
        let id = UUID()
        var filePath: String
        var fileName: String
        var originalContent: String
        var newContent: String
        var language: String
        var isExpanded: Bool = true
        var changeSummary: String?
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            composerHeader
            
            Divider()
            
            // Main content area
            HStack(spacing: 0) {
                // File list sidebar
                fileListSidebar
                    .frame(width: 250)
                
                Divider()
                
                // Editor area
                if let selectedFile = selectedFile {
                    composerEditor(for: selectedFile)
                } else {
                    emptyStateView
                }
            }
            
            Divider()
            
            // FIX: Tool call progress indicators
            if !viewModel.toolCallProgresses.isEmpty {
                ToolCallProgressListView(
                    progresses: viewModel.toolCallProgresses,
                    onApprove: { toolCallId in
                        viewModel.approveToolCall(toolCallId)
                    },
                    onReject: { toolCallId in
                        viewModel.rejectToolCall(toolCallId)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
            }
            
            // Input area
            composerInputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // FIX: Set up notification listener for tool file writes
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ToolFileWritten"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let filePath = userInfo["filePath"] as? String,
                   let content = userInfo["content"] as? String {
                    // Update or add file to Composer
                    handleToolFileWrite(filePath: filePath, content: content)
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var composerHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .foregroundColor(.blue)
                .font(.system(size: 16, weight: .semibold))
            
            Text("Composer")
                .font(.system(size: 14, weight: .semibold))
            
            if !composerFiles.isEmpty {
                Text("\(composerFiles.count) file\(composerFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            if !composerFiles.isEmpty {
                Button("Apply All") {
                    applyAllFiles()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                
                Button("Discard All") {
                    discardAllFiles()
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - File List Sidebar
    
    private var fileListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search/Filter
            TextField("Filter files...", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .padding(8)
            
            Divider()
            
            // File list
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(composerFiles) { file in
                        fileListItem(file: file)
                    }
                }
                .padding(8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func fileListItem(file: ComposerFile) -> some View {
        Button(action: {
            selectedFileId = file.id
        }) {
            HStack(spacing: 8) {
                Image(systemName: iconForFile(file.fileName))
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let summary = file.changeSummary {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Change indicator
                if file.newContent != file.originalContent {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selectedFileId == file.id
                    ? Color.blue.opacity(0.1)
                    : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Editor
    
    private var selectedFile: ComposerFile? {
        guard let selectedFileId = selectedFileId else { return nil }
        return composerFiles.first { $0.id == selectedFileId }
    }
    
    private func composerEditor(for file: ComposerFile) -> some View {
        VStack(spacing: 0) {
            // File header
            HStack(spacing: 12) {
                Image(systemName: iconForFile(file.fileName))
                    .foregroundColor(.secondary)
                
                Text(file.fileName)
                    .font(.system(size: 13, weight: .semibold))
                
                Text(file.filePath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Diff view (includes Apply/Discard buttons in its header)
            ScrollView {
                DiffView(
                    originalContent: file.originalContent,
                    modifiedContent: file.newContent,
                    onAccept: {
                        applyFile(file)
                    },
                    onReject: {
                        discardFile(file)
                    }
                )
                .padding()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Composer Mode")
                .font(.system(size: 18, weight: .semibold))
            
            Text("Edit multiple files at once with AI assistance")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Type your request above to start editing files")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Input Area
    
    private var composerInputArea: some View {
        VStack(spacing: 0) {
            // Attached images
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
            }
            
            // Context badges
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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            // Input field
            HStack(spacing: 8) {
                // @ mention button
                Button(action: {
                    showMentionPopup = true
                }) {
                    Image(systemName: "at")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add context (@file, @codebase, etc.)")
                .popover(isPresented: $showMentionPopup, arrowEdge: .top) {
                    MentionPopupView(isVisible: $showMentionPopup) { type in
                        addMention(type)
                    }
                }
                
                // Image attachment button
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.image]
                    
                    if panel.runModal() == .OK {
                        for url in panel.urls {
                            _ = imageContextService.addFromFile(url)
                        }
                    }
                }) {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Attach image")
                
                // Text input
                TextField("Describe changes to make across files...", text: $composerInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .padding(.vertical, 8)
                    .onSubmit {
                        if !composerInput.isEmpty && !isGenerating {
                            generateComposerChanges()
                        }
                    }
                
                // Send button
                Button(action: {
                    if isGenerating {
                        viewModel.cancelGeneration()
                    } else {
                        generateComposerChanges()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                isGenerating
                                    ? Color.red
                                    : (composerInput.isEmpty
                                        ? Color.gray.opacity(0.3)
                                        : Color(red: 0.5, green: 0.3, blue: 0.9))
                            )
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isGenerating || !composerInput.isEmpty ? .white : .secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isGenerating && composerInput.isEmpty)
                .help(isGenerating ? "Stop generation" : "Generate changes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .onDrop(of: [.image, .fileURL], isTargeted: .constant(false)) { providers in
                Task {
                    _ = await handleImageDrop(providers: providers)
                }
                return true
            }
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
    
    // MARK: - Mentions
    
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
    
    // MARK: - Actions
    
    private func generateComposerChanges() {
        guard !composerInput.isEmpty else { return }
        
        isGenerating = true
        let _ = composerInput // FIX: Capture input value but don't use it (cleared immediately)
        composerInput = ""
        
        // FIX: Enable project mode for Composer (enables tools)
        viewModel.projectMode = true
        
        // Get context (async) - wrap in Task
        Task {
            var context = await editorViewModel.getContextForAI() ?? ""
            
            // Build context from mentions
            let mentionContext = MentionParser.shared.buildContextFromMentions(
                activeMentions,
                projectURL: editorViewModel.rootFolderURL,
                selectedText: editorViewModel.editorState.selectedText,
                terminalOutput: nil
            )
            context += mentionContext
            
            // Send to AI with tools enabled (projectMode = true enables tools)
            await MainActor.run {
                viewModel.sendMessage(
                    context: context,
                    projectURL: editorViewModel.rootFolderURL,
                    images: imageContextService.attachedImages
                )
                
                // Clear images and mentions after sending
                imageContextService.clearImages()
                activeMentions.removeAll()
            }
            
            // Parse response for multiple files
            // This will be handled by the streaming view parsing logic
            // For now, we'll listen to viewModel changes
        }
    }
    
    private func applyFile(_ file: ComposerFile) {
        guard let projectURL = editorViewModel.rootFolderURL else { return }

        let fileURL = projectURL.appendingPathComponent(file.filePath)
        let directory = fileURL.deletingLastPathComponent()

        // Read original content if file exists (for change highlighting)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.newContent.write(to: fileURL, atomically: true, encoding: .utf8)

            // Open with change highlighting (use originalContent from ComposerFile if available, otherwise use read content)
            let contentForHighlighting = file.originalContent.isEmpty ? (originalContent ?? "") : file.originalContent
            editorViewModel.openFile(at: fileURL, originalContent: contentForHighlighting)

            // Refresh file tree to show new file immediately
            editorViewModel.refreshFileTree()

            // Remove from composer
            composerFiles.removeAll { $0.id == file.id }
            if selectedFileId == file.id {
                selectedFileId = composerFiles.first?.id
            }
        } catch {
            print("Failed to apply file: \(error)")
        }
    }
    
    private func discardFile(_ file: ComposerFile) {
        composerFiles.removeAll { $0.id == file.id }
        if selectedFileId == file.id {
            selectedFileId = composerFiles.first?.id
        }
    }
    
    private func applyAllFiles() {
        for file in composerFiles {
            applyFile(file)
        }
    }
    
    private func discardAllFiles() {
        composerFiles.removeAll()
        selectedFileId = nil
    }
    
    // MARK: - FIX: Tool Integration
    
    /// Handle file writes from tool calls
    private func handleToolFileWrite(filePath: String, content: String) {
        // Check if file already exists in composer
        if let existingIndex = composerFiles.firstIndex(where: { $0.filePath == filePath }) {
            // Update existing file
            var updatedFile = composerFiles[existingIndex]
            updatedFile.newContent = content
            composerFiles[existingIndex] = updatedFile
        } else {
            // Add new file to composer
            let fileName = (filePath as NSString).lastPathComponent
            let language = detectLanguage(from: filePath)
            
            // Read original content if file exists
            var originalContent = ""
            if let projectURL = editorViewModel.rootFolderURL {
                let fileURL = projectURL.appendingPathComponent(filePath)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    originalContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                }
            }
            
            let newFile = ComposerFile(
                filePath: filePath,
                fileName: fileName,
                originalContent: originalContent,
                newContent: content,
                language: language,
                isExpanded: true,
                changeSummary: calculateChangeSummary(original: originalContent, new: content)
            )
            
            composerFiles.append(newFile)
            
            // Auto-select first file if none selected
            if selectedFileId == nil {
                selectedFileId = newFile.id
            }
        }
    }
    
    /// Detect language from file path
    private func detectLanguage(from filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "md": return "markdown"
        default: return "text"
        }
    }
    
    /// Calculate change summary for file
    private func calculateChangeSummary(original: String, new: String) -> String {
        let originalLines = original.components(separatedBy: .newlines).count
        let newLines = new.components(separatedBy: .newlines).count
        
        if original.isEmpty {
            return "+\(newLines) lines"
        } else if new.isEmpty {
            return "-\(originalLines) lines"
        } else {
            let diff = newLines - originalLines
            if diff > 0 {
                return "+\(diff) lines"
            } else if diff < 0 {
                return "\(diff) lines"
            } else {
                return "Modified"
            }
        }
    }
    
    // MARK: - Helpers
    
    private func iconForFile(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
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
}

