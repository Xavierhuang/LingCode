//
//  CursorStreamingView.swift
//  LingCode
//
//  Exact Cursor-style streaming experience
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Cursor-style streaming view - shows everything as it happens
struct CursorStreamingView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var streamingText: String = ""
    @State private var parsedFiles: [StreamingFileInfo] = []
    @State private var expandedFiles: Set<String> = []
    @State private var showGraphiteView = false
    @State private var selectedFileForGraphite: StreamingFileInfo?
    @State private var lastUserRequest: String = ""
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var parsedCommands: [ParsedCommand] = []
    private let terminalService = TerminalExecutionService.shared
    @State private var showMentionPopup = false
    @State private var activeMentions: [Mention] = []
    
    var body: some View {
        VStack(spacing: 0) {
            streamingHeader
            Divider()
            streamingContent
            Divider()
            streamingInput
        }
        .background(backgroundView)
        .onChange(of: viewModel.conversation.messages.last?.content, perform: handleMessageChange)
        .onChange(of: viewModel.currentActions, perform: handleActionsChange)
        .onAppear(perform: handleAppear)
        .sheet(isPresented: $showGraphiteView) {
            if !parsedFiles.isEmpty {
                GraphiteStackView(
                    changes: parsedFiles.map { file in
                        CodeChange(
                            id: UUID(),
                            filePath: file.path,
                            fileName: file.name,
                            operationType: .update,
                            originalContent: nil,
                            newContent: file.content,
                            lineRange: nil,
                            language: file.language
                        )
                    }
                )
            }
        }
    }
    
    // MARK: - View Components
    
    private var backgroundView: some View {
        Color(NSColor.windowBackgroundColor).opacity(1.0)
    }
    
    private var streamingContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    // Terminal commands view
                    if !parsedCommands.isEmpty {
                        terminalCommandsView
                    }
                    
                    contentVStack
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: streamingText) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: parsedFiles.count) { oldCount, newCount in
                if let lastFile = parsedFiles.last {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        proxy.scrollTo(lastFile.id, anchor: .center)
                    }
                }

                // Auto-open the first file in the editor for preview
                if oldCount == 0 && newCount == 1, let firstFile = parsedFiles.first {
                    openFile(firstFile)
                }
            }
            .onChange(of: parsedCommands.count) { _, _ in
                if let lastCommand = parsedCommands.last {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        proxy.scrollTo(lastCommand.id.uuidString, anchor: .center)
                    }
                }
            }
        }
    }
    
    private var terminalCommandsView: some View {
        VStack(spacing: 8) {
            // Header with "Run All" button if multiple commands
            if parsedCommands.count > 1 {
                HStack {
                    Text("Terminal Commands")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: runAllCommands) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Run All")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.2, green: 0.6, blue: 1.0))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 4)
            }
            
            ForEach(parsedCommands) { command in
                TerminalCommandCard(
                    command: command,
                    workingDirectory: editorViewModel.rootFolderURL
                )
                .id(command.id.uuidString)
                .transition(.asymmetric(
                    insertion: .move(edge: .top)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.95))
                        .animation(.spring(response: 0.4, dampingFraction: 0.75)),
                    removal: .opacity
                        .combined(with: .scale(scale: 0.95))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8))
                ))
            }
        }
    }
    
    private func runAllCommands() {
        // Run all non-destructive commands sequentially
        let safeCommands = parsedCommands.filter { !$0.isDestructive }
        guard !safeCommands.isEmpty else { return }
        
        // For now, just run the first command
        // In a full implementation, we'd run them sequentially
        if let firstCommand = safeCommands.first {
            terminalService.execute(
                firstCommand.command,
                workingDirectory: editorViewModel.rootFolderURL,
                environment: nil,
                onOutput: { _ in },
                onError: { _ in },
                onComplete: { _ in
                    // Could chain next command here
                }
            )
        }
    }
    
    private var contentVStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            parsedFilesView
            actionsView
            rawStreamingView

            // Completion summary - show after AI has responded
            if !viewModel.isLoading && hasResponse {
                completionSummaryView
            }

            // Graphite recommendation for large changes
            if shouldShowGraphiteRecommendation && !viewModel.isLoading {
                graphiteRecommendationView
            }
        }
    }
    
    private var completionSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))

                Text(parsedFiles.isEmpty ? "Response Complete" : "Generation Complete")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()
            }

            Divider()

            // Generated summary description
            if let summaryText = generateSummaryText() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
            }

            // User request summary
            if !lastUserRequest.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(lastUserRequest)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
                .padding(.bottom, 4)
            }

            // Summary stats
            if !parsedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // File list
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files Modified:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        ForEach(parsedFiles.prefix(5)) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                Text(file.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }

                        if parsedFiles.count > 5 {
                            Text("+ \(parsedFiles.count - 5) more files")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    let totalAdded = parsedFiles.reduce(0) { $0 + $1.addedLines }
                    let totalRemoved = parsedFiles.reduce(0) { $0 + $1.removedLines }

                    if totalAdded > 0 || totalRemoved > 0 {
                        Divider()
                        HStack {
                            if totalAdded > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 10))
                                    Text("+\(totalAdded) lines")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.green)
                            }

                            if totalRemoved > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 10))
                                    Text("-\(totalRemoved) lines")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.red)
                            }

                            Spacer()
                        }
                    }
                }
            } else if !parsedCommands.isEmpty {
                // Show command summary if no files but commands were parsed
                VStack(alignment: .leading, spacing: 8) {
                    Text("Commands Provided:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(parsedCommands.prefix(3)) { command in
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Text(command.command)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                    }

                    if parsedCommands.count > 3 {
                        Text("+ \(parsedCommands.count - 3) more commands")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var parsedFilesView: some View {
        ForEach(parsedFiles) { file in
            fileCard(for: file)
                .id(file.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .top)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.95))
                        .animation(.spring(response: 0.4, dampingFraction: 0.75)),
                    removal: .opacity
                        .combined(with: .scale(scale: 0.95))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8))
                ))
        }
    }
    
    private func fileCard(for file: StreamingFileInfo) -> some View {
        CursorStreamingFileCard(
            file: file,
            isExpanded: expandedFiles.contains(file.id),
            projectURL: editorViewModel.rootFolderURL,
            onToggle: { toggleFile(file.id) },
            onOpen: { openFile(file) },
            onApply: { applyFile(file) },
            onReject: { rejectFile(file) }
        )
        .overlay(
            // Graphite recommendation for large changes
            Group {
                if shouldShowGraphiteRecommendationForFile(file) {
                    GraphiteRecommendationBadge {
                        showGraphiteStackViewForFile(file)
                    }
                }
            },
            alignment: .topTrailing
        )
    }
    
    
    private func rejectFile(_ file: StreamingFileInfo) {
        // Remove file from parsed files
        parsedFiles.removeAll { $0.id == file.id }
    }
    
    private var actionsView: some View {
        Group {
            if parsedFiles.isEmpty && !viewModel.currentActions.isEmpty {
                ForEach(viewModel.currentActions) { action in
                    actionCard(for: action)
                        .id(action.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.95))
                                .animation(.spring(response: 0.4, dampingFraction: 0.75)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95))
                                .animation(.spring(response: 0.3, dampingFraction: 0.8))
                        ))
                }
            }
        }
    }
    
    private func actionCard(for action: AIAction) -> some View {
        CursorActionCard(
            action: action,
            streamingContent: getStreamingContent(for: action),
            isStreaming: viewModel.isLoading && action.status == .executing,
            onOpen: { openAction(action) },
            onApply: { applyAction(action) }
        )
    }
    
    private var rawStreamingView: some View {
        Group {
            if viewModel.isLoading && parsedFiles.isEmpty && viewModel.currentActions.isEmpty {
                StreamingResponseView(
                    content: streamingText,
                    onContentChange: { newContent in
                        streamingText = newContent
                        parseStreamingContent(newContent)
                    }
                )
                .id("streaming")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func toggleFile(_ fileId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if expandedFiles.contains(fileId) {
                expandedFiles.remove(fileId)
            } else {
                expandedFiles.insert(fileId)
            }
        }
    }
    
    private func handleMessageChange(_ newContent: String?) {
        if let content = newContent {
            streamingText = content
            parseStreamingContent(content)
            
            // Re-parse when streaming completes to catch any final commands
            if !viewModel.isLoading {
                let commands = terminalService.extractCommands(from: content)
                if !commands.isEmpty {
                    parsedCommands = commands
                }
            }
        }
    }
    
    private func handleActionsChange(_: [AIAction]) {
        if viewModel.isLoading {
            parseStreamingContent(streamingText)
        }
    }
    
    private func handleAppear() {
        if let lastMessage = viewModel.conversation.messages.last,
           lastMessage.role == .assistant {
            streamingText = lastMessage.content
            if viewModel.isLoading {
                parseStreamingContent(lastMessage.content)
            }
        }
    }
    
    // MARK: - Header (Cursor-style)
    
    private var streamingHeader: some View {
        HStack(spacing: 12) {
            // AI Assistant title with icon
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.3, blue: 0.9)) // Cursor purple
                
                Text("AI Assistant")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                if viewModel.isLoading {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.2, green: 0.6, blue: 1.0)) // Cursor blue
                            .frame(width: 6, height: 6)
                            .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.5), radius: 3)
                        
                        Circle()
                            .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.4), lineWidth: 2)
                            .frame(width: 12, height: 12)
                            .scaleEffect(viewModel.isLoading ? 1.8 : 1.0)
                            .opacity(viewModel.isLoading ? 0.0 : 0.6)
                            .animation(
                                Animation.easeOut(duration: 1.2)
                                    .repeatForever(autoreverses: false),
                                value: viewModel.isLoading
                            )
                    }
                    Text("Working...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        ))
                } else {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.4)) // Cursor green
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.4), radius: 2)
                    Text("Ready")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isLoading)
            
            // Stop button (when loading)
            if viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    Text("Stop")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.1))
                )
                .scaleEffect(viewModel.isLoading ? 1.0 : 0.95)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: viewModel.isLoading)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor)
                .opacity(0.8)
        )
    }
    
    // MARK: - Parsing
    
    private func parseStreamingContent(_ content: String) {
        // First, extract terminal commands
        let commands = terminalService.extractCommands(from: content)
        if !commands.isEmpty {
            parsedCommands = commands
        }
        
        // Multiple patterns to catch different formats (including incomplete blocks during streaming)
        let patterns = [
            // Pattern 1: `filename.ext`:\n```lang\ncode\n``` (complete)
            #"`([^`\n]+\.[a-zA-Z0-9]+)`[:\s]*\n```(\w+)?\n([\s\S]*?)```"#,
            // Pattern 2: **filename.ext**:\n```lang\ncode\n``` (complete)
            #"\*\*([^*\n]+\.[a-zA-Z0-9]+)\*\*[:\s]*\n```(\w+)?\n([\s\S]*?)```"#,
            // Pattern 3: ### filename.ext\n```lang\ncode\n``` (complete)
            #"###\s+([^\n]+\.[a-zA-Z0-9]+)\s*\n```(\w+)?\n([\s\S]*?)```"#
        ]
        
        // Patterns for incomplete blocks (streaming)
        let streamingPatterns = [
            // Pattern 1: `filename.ext`:\n```lang\ncode (incomplete - no closing ```)
            #"`([^`\n]+\.[a-zA-Z0-9]+)`[:\s]*\n```(\w+)?\n([\s\S]*?)(?=\n```|$)"#,
            // Pattern 2: **filename.ext**:\n```lang\ncode (incomplete)
            #"\*\*([^*\n]+\.[a-zA-Z0-9]+)\*\*[:\s]*\n```(\w+)?\n([\s\S]*?)(?=\n```|$)"#,
            // Pattern 3: ### filename.ext\n```lang\ncode (incomplete)
            #"###\s+([^\n]+\.[a-zA-Z0-9]+)\s*\n```(\w+)?\n([\s\S]*?)(?=\n```|$)"#
        ]
        
        var newFiles: [StreamingFileInfo] = []
        var processedPaths = Set<String>()
        
        // First, process complete blocks
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                let matches = regex.matches(in: content, options: [], range: range)
                
                for match in matches where match.numberOfRanges >= 4 {
                    processMatch(match, in: content, isStreaming: false, newFiles: &newFiles, processedPaths: &processedPaths)
                }
            }
        }
        
        // Then, process incomplete blocks (for streaming)
        if viewModel.isLoading {
            for pattern in streamingPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(content.startIndex..<content.endIndex, in: content)
                    let matches = regex.matches(in: content, options: [], range: range)
                    
                    for match in matches where match.numberOfRanges >= 4 {
                        // Only process if not already processed as complete
                        let pathRange = match.range(at: 1)
                        if pathRange.location != NSNotFound,
                           let swiftRange = Range(pathRange, in: content) {
                            let filePath = String(content[swiftRange]).trimmingCharacters(in: .whitespaces)
                            if !processedPaths.contains(filePath) {
                                processMatch(match, in: content, isStreaming: true, newFiles: &newFiles, processedPaths: &processedPaths)
                            }
                        }
                    }
                }
            }
        }
        
        // Helper function to process a match
        func processMatch(_ match: NSTextCheckingResult, in content: String, isStreaming: Bool, newFiles: inout [StreamingFileInfo], processedPaths: inout Set<String>) {
            // File path
            var filePath: String? = nil
            if match.numberOfRanges > 1 {
                let pathRange = match.range(at: 1)
                if pathRange.location != NSNotFound,
                   let swiftRange = Range(pathRange, in: content) {
                    filePath = String(content[swiftRange]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            // Language
            var language = "text"
            if match.numberOfRanges > 2 {
                let langRange = match.range(at: 2)
                if langRange.location != NSNotFound,
                   let swiftRange = Range(langRange, in: content) {
                    let lang = String(content[swiftRange]).trimmingCharacters(in: .whitespaces)
                    if !lang.isEmpty {
                        language = lang
                    }
                }
            }
            
            // Code content
            var code = ""
            if match.numberOfRanges > 3 {
                let codeRange = match.range(at: 3)
                if codeRange.location != NSNotFound,
                   let swiftRange = Range(codeRange, in: content) {
                    code = String(content[swiftRange])
                }
            }
            
            if let path = filePath, !processedPaths.contains(path) {
                processedPaths.insert(path)
                let fileId = path
                
                // Calculate change summary
                let (summary, added, removed) = calculateChangeSummary(
                    filePath: path,
                    newContent: code,
                    projectURL: editorViewModel.rootFolderURL
                )
                
                // Update existing or create new
                if let existingIndex = newFiles.firstIndex(where: { $0.id == fileId }) {
                    let existing = newFiles[existingIndex]
                    // Replace the entire struct since it's immutable
                    newFiles[existingIndex] = StreamingFileInfo(
                        id: fileId,
                        path: path,
                        name: URL(fileURLWithPath: path).lastPathComponent,
                        language: language,
                        content: code,
                        isStreaming: isStreaming || viewModel.isLoading,
                        changeSummary: summary,
                        addedLines: added,
                        removedLines: removed
                    )
                } else {
                    newFiles.append(StreamingFileInfo(
                        id: fileId,
                        path: path,
                        name: URL(fileURLWithPath: path).lastPathComponent,
                        language: language,
                        content: code,
                        isStreaming: isStreaming || viewModel.isLoading,
                        changeSummary: summary,
                        addedLines: added,
                        removedLines: removed
                    ))
                }
            }
        }
        
        // Also check viewModel actions for files
        for action in viewModel.currentActions {
            if let path = action.filePath,
               !processedPaths.contains(path),
               let content = action.fileContent ?? action.result {
                processedPaths.insert(path)
                
                // Calculate change summary
                let (summary, added, removed) = calculateChangeSummary(
                    filePath: path,
                    newContent: content,
                    projectURL: editorViewModel.rootFolderURL
                )
                
                newFiles.append(StreamingFileInfo(
                    id: path,
                    path: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    language: detectLanguage(from: path),
                    content: content,
                    isStreaming: viewModel.isLoading && action.status == .executing,
                    changeSummary: summary,
                    addedLines: added,
                    removedLines: removed
                ))
            }
        }
        
        // Auto-expand new files that are streaming
        for file in newFiles {
            if file.isStreaming && !expandedFiles.contains(file.id) {
                expandedFiles.insert(file.id)
            }
        }
        
        parsedFiles = newFiles
    }
    
    private func detectLanguage(from path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        default: return "text"
        }
    }
    
    private func calculateChangeSummary(filePath: String, newContent: String, projectURL: URL?) -> (summary: String?, added: Int, removed: Int) {
        guard let projectURL = projectURL else {
            return ("New file", newContent.components(separatedBy: .newlines).count, 0)
        }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let newLines = newContent.components(separatedBy: .newlines)
        
        // Check if file exists
        if FileManager.default.fileExists(atPath: fileURL.path),
           let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            // File exists - calculate diff
            let existingLines = existingContent.components(separatedBy: .newlines)
            let added = max(0, newLines.count - existingLines.count)
            let removed = max(0, existingLines.count - newLines.count)
            
            if added > 0 && removed > 0 {
                return ("Modified: +\(added) -\(removed) lines", added, removed)
            } else if added > 0 {
                return ("Added \(added) line\(added == 1 ? "" : "s")", added, removed)
            } else if removed > 0 {
                return ("Removed \(removed) line\(removed == 1 ? "" : "s")", added, removed)
            } else {
                return ("No changes", 0, 0)
            }
        } else {
            // New file
            return ("New file: \(newLines.count) line\(newLines.count == 1 ? "" : "s")", newLines.count, 0)
        }
    }
    
    private func getStreamingContent(for action: AIAction) -> String? {
        if let filePath = action.filePath,
           let file = parsedFiles.first(where: { $0.path == filePath }) {
            return file.content
        }
        return action.fileContent
    }
    
    // MARK: - Actions
    
    private func openFile(_ file: StreamingFileInfo) {
        guard let projectURL = editorViewModel.rootFolderURL else { 
            print("⚠️ Cannot open file: No project folder selected")
            return 
        }
        
        // Handle both relative and absolute paths
        let fileURL: URL
        if file.path.hasPrefix("/") {
            // Absolute path
            fileURL = URL(fileURLWithPath: file.path)
        } else {
            // Relative path - append to project root
            fileURL = projectURL.appendingPathComponent(file.path)
        }
        
        // Check if file already exists
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

        // Read original content if file exists (for change highlighting)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil

        if fileExists {
            // File exists - overwrite and open with change highlighting
            print("📂 Updating existing file: \(fileURL.path)")
            do {
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                editorViewModel.openFile(at: fileURL, originalContent: originalContent)
            } catch {
                print("❌ Failed to update file: \(error)")
            }
        } else {
            // File doesn't exist - create it with generated content
            let directory = fileURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ Created and opened file: \(fileURL.path)")
                // New files: highlight everything as new (pass empty string as original)
                editorViewModel.openFile(at: fileURL, originalContent: "")
                // Refresh file tree to show new file immediately
                editorViewModel.refreshFileTree()
            } catch {
                print("❌ Failed to create file: \(error)")
                // Try to open anyway if it exists now
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    editorViewModel.openFile(at: fileURL)
                }
            }
        }
    }
    
    private func applyFile(_ file: StreamingFileInfo) {
        guard let projectURL = editorViewModel.rootFolderURL else { return }
        let fileURL = projectURL.appendingPathComponent(file.path)
        let directory = fileURL.deletingLastPathComponent()

        // Read original content if file exists (for change highlighting)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)

            // Open with change highlighting
            editorViewModel.openFile(at: fileURL, originalContent: originalContent ?? "")

            // Refresh file tree to show new file immediately
            editorViewModel.refreshFileTree()
        } catch {
            print("Failed to apply file: \(error)")
        }
    }
    
    private func openAction(_ action: AIAction) {
        guard let projectURL = editorViewModel.rootFolderURL,
              let filePath = action.filePath else { return }
        let fileURL = projectURL.appendingPathComponent(filePath)
        editorViewModel.openFile(at: fileURL)
    }
    
    private func applyAction(_ action: AIAction) {
        guard let content = action.fileContent ?? action.result,
              let projectURL = editorViewModel.rootFolderURL,
              let filePath = action.filePath else { return }

        let fileURL = projectURL.appendingPathComponent(filePath)
        let directory = fileURL.deletingLastPathComponent()

        // Read original content if file exists (for change highlighting)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            action.status = .completed

            // Open with change highlighting
            editorViewModel.openFile(at: fileURL, originalContent: originalContent ?? "")

            // Refresh file tree to show new file immediately
            editorViewModel.refreshFileTree()
        } catch {
            action.status = .failed
            action.error = error.localizedDescription
        }
    }
    
    // MARK: - Input (Cursor-style)
    
    private var streamingInput: some View {
        VStack(spacing: 0) {
            // Context files indicator
            if let contextFiles = getContextFiles(), !contextFiles.isEmpty {
                ContextFilesIndicator(files: contextFiles)
            }
            
            // Context file indicator (if active)
            if let file = editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(file)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(0.5)
                )
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
                .background(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(0.4)
                )
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
            
            // Input field (Cursor-style)
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
                
                // Paste image from clipboard button
                Button(action: {
                    _ = imageContextService.addFromClipboard()
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Paste image from clipboard")
                
                // Text input
                TextField("Ask AI anything...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .padding(.vertical, 8)
                    .onSubmit {
                        if !viewModel.currentInput.isEmpty && !viewModel.isLoading {
                            sendMessage()
                        }
                    }
                    .onChange(of: viewModel.currentInput) { _, newValue in
                        // Check for @ trigger
                        if newValue.hasSuffix("@") {
                            showMentionPopup = true
                        }
                    }
                
                // Send/Stop button
                Button(action: {
                    if viewModel.isLoading {
                        viewModel.cancelGeneration()
                    } else {
                        sendMessage()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                viewModel.isLoading 
                                    ? Color.red 
                                    : (viewModel.currentInput.isEmpty 
                                        ? Color.gray.opacity(0.3) 
                                        : Color(red: 0.5, green: 0.3, blue: 0.9))
                            )
                            .frame(width: 24, height: 24)
                            .shadow(
                                color: (!viewModel.isLoading && !viewModel.currentInput.isEmpty) 
                                    ? Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.4) 
                                    : Color.clear,
                                radius: 4
                            )
                        
                        Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(viewModel.isLoading || !viewModel.currentInput.isEmpty ? .white : .secondary)
                    }
                    .scaleEffect(viewModel.isLoading ? 1.0 : (viewModel.currentInput.isEmpty ? 0.95 : 1.0))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.isLoading && viewModel.currentInput.isEmpty)
                .help(viewModel.isLoading ? "Stop generation" : "Send message")
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: viewModel.isLoading)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: viewModel.currentInput.isEmpty)
                .onTapGesture {
                    if !viewModel.isLoading && !viewModel.currentInput.isEmpty {
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                            // Button press feedback
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.6)
            )
            .onDrop(of: [.image, .fileURL], isTargeted: .constant(false)) { providers in
                Task {
                    _ = await handleImageDrop(providers: providers)
                }
                return true
            }
        }
        .background(
            Color(NSColor.windowBackgroundColor)
        )
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
    
    private func getContextFiles() -> [String]? {
        var files: [String] = []
        
        // Add active file
        if let activeFile = editorViewModel.editorState.activeDocument?.filePath {
            files.append(activeFile.lastPathComponent)
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
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty else { return }
        
        // Store user request for completion summary
        lastUserRequest = viewModel.currentInput
        
        streamingText = ""
        parsedFiles = []
        parsedCommands = [] // Clear previous commands
        var context = editorViewModel.getContextForAI() ?? ""
        
        // Build context from mentions
        let mentionContext = MentionParser.shared.buildContextFromMentions(
            activeMentions,
            projectURL: editorViewModel.rootFolderURL,
            selectedText: editorViewModel.editorState.selectedText,
            terminalOutput: nil
        )
        context += mentionContext
        
        // Send message with images if any
        viewModel.sendMessage(
            context: context,
            projectURL: editorViewModel.rootFolderURL,
            images: imageContextService.attachedImages
        )
        
        // Clear images and mentions after sending
        imageContextService.clearImages()
        activeMentions.removeAll()
    }
    
    private var hasResponse: Bool {
        // Check if AI has provided any response
        return !parsedFiles.isEmpty ||
               !parsedCommands.isEmpty ||
               !lastUserRequest.isEmpty ||
               viewModel.conversation.messages.contains(where: { $0.role == .assistant })
    }

    private func generateSummaryText() -> String? {
        // Generate a human-readable summary of what was done
        if !parsedFiles.isEmpty {
            if parsedFiles.count == 1 {
                let file = parsedFiles[0]
                if let summary = file.changeSummary, !summary.isEmpty {
                    return summary
                }
                return "Generated \(file.name)"
            } else {
                // Multiple files
                let fileNames = parsedFiles.prefix(2).map { $0.name }.joined(separator: ", ")
                if parsedFiles.count == 2 {
                    return "Generated \(fileNames)"
                } else {
                    return "Generated \(fileNames) and \(parsedFiles.count - 2) more file\(parsedFiles.count - 2 == 1 ? "" : "s")"
                }
            }
        } else if !parsedCommands.isEmpty {
            if parsedCommands.count == 1 {
                return "Provided terminal command: \(parsedCommands[0].command)"
            } else {
                return "Provided \(parsedCommands.count) terminal commands"
            }
        } else if let lastMessage = viewModel.conversation.messages.last(where: { $0.role == .assistant }),
                  !lastMessage.content.isEmpty {
            // Try to extract a brief summary from the response
            let lines = lastMessage.content.components(separatedBy: .newlines)
            if let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 100 {
                    return String(trimmed.prefix(100)) + "..."
                }
                return trimmed
            }
        }

        return nil
    }

    private var shouldShowGraphiteRecommendation: Bool {
        let totalFiles = parsedFiles.count
        let totalLines = parsedFiles.reduce(0) { $0 + $1.addedLines }
        return totalFiles > 5 || totalLines > 200
    }
    
    private func shouldShowGraphiteRecommendationForFile(_ file: StreamingFileInfo) -> Bool {
        let lineCount = file.content.components(separatedBy: .newlines).count
        return lineCount > 200 || file.addedLines > 100
    }
    
    private func showGraphiteStackViewForFile(_ file: StreamingFileInfo) {
        selectedFileForGraphite = file
        showGraphiteView = true
    }
    
    private var graphiteRecommendationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.blue)
                Text("Large Change Detected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            let recommendation = ApplyCodeService.shared.getChangeRecommendation(
                parsedFiles.map { file in
                    CodeChange(
                        id: UUID(),
                        filePath: file.path,
                        fileName: file.name,
                        operationType: .update,
                        originalContent: nil,
                        newContent: file.content,
                        lineRange: nil,
                        language: file.language
                    )
                }
            )
            
            Text(recommendation.message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if case .useGraphiteStacking(_, let prs) = recommendation {
                Button("Create Stacked PRs (\(prs) PRs)") {
                    createGraphiteStack()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func createGraphiteStack() {
        showGraphiteView = true
    }
}

// MARK: - Streaming File Info

struct StreamingFileInfo: Identifiable {
    let id: String
    let path: String
    let name: String
    var language: String
    var content: String
    var isStreaming: Bool
    var changeSummary: String? // Summary of what changed
    var addedLines: Int = 0
    var removedLines: Int = 0
}

// MARK: - Streaming Response View (Cursor-style)

struct StreamingResponseView: View {
    let content: String
    let onContentChange: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.3, blue: 0.9))
                
                Text("AI Response")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                            .frame(width: 4, height: 4)
                            .opacity(0.9)
                            .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.6), radius: 2)
                        
                        Circle()
                            .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.5), lineWidth: 1)
                            .frame(width: 8, height: 8)
                            .scaleEffect(content.isEmpty ? 1.0 : 1.5)
                            .opacity(content.isEmpty ? 0.0 : 0.0)
                            .animation(
                                Animation.easeOut(duration: 0.8)
                                    .repeatForever(autoreverses: false),
                                value: content
                            )
                    }
                    Text("Streaming")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.4)
            )
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Streaming cursor
                    if !content.isEmpty {
                        HStack(spacing: 0) {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3))
                                    .frame(width: 2, height: 16)
                                
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                                    .frame(width: 2, height: 16)
                                    .opacity(0.9)
                                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.8), radius: 2)
                                    .animation(
                                        Animation.easeInOut(duration: 1.0)
                                            .repeatForever(autoreverses: true),
                                        value: content
                                    )
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 200)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onChange(of: content) { _, newValue in
            onContentChange(newValue)
        }
    }
}

// MARK: - Cursor Streaming File Card (Exact Cursor Style)

struct CursorStreamingFileCard: View {
    let file: StreamingFileInfo
    let isExpanded: Bool
    let projectURL: URL?
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onApply: () -> Void
    let onReject: (() -> Void)? // Optional reject callback
    
    @State private var isHovered = false
    @State private var isApplied = false
    @State private var isRejected = false
    @State private var validationResult: ValidationResult?
    
    init(
        file: StreamingFileInfo,
        isExpanded: Bool,
        projectURL: URL?,
        onToggle: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onReject: (() -> Void)? = nil
    ) {
        self.file = file
        self.isExpanded = isExpanded
        self.projectURL = projectURL
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.onApply = onApply
        self.onReject = onReject
    }
    
    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            if let validation = validationResult, !validation.isValid {
                validationWarningView(validation)
            }
            expandedContent
        }
        .background(fileCardBackground)
        .overlay(fileCardOverlay)
        .shadow(
            color: isHovered ? Color.black.opacity(0.15) : Color.black.opacity(0.05),
            radius: isHovered ? 6 : 2,
            x: 0,
            y: isHovered ? 3 : 1
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .onAppear {
            validateFile()
        }
        .onChange(of: file.content) { _, _ in
            validateFile()
        }
    }
    
    private func validateFile() {
        let change = CodeChange(
            id: UUID(),
            filePath: file.path,
            fileName: file.name,
            operationType: .update,
            originalContent: nil, // Would get from file system
            newContent: file.content,
            lineRange: nil,
            language: file.language
        )
        
        validationResult = CodeValidationService.shared.validateChange(
            change,
            requestedScope: "AI generated code",
            projectConfig: nil
        )
    }
    
    private func validationWarningView(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ValidationBadgeView(validationResult: validation)
            
            if !validation.issues.isEmpty {
                ValidationIssuesView(issues: validation.issues)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            validation.severity == .critical 
                ? Color.red.opacity(0.1)
                : Color.orange.opacity(0.1)
        )
    }
    
    // MARK: - View Components
    
    private var fileHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                fileIconView
                fileNameView
                filePathView
                Spacer()
                statusBadgeView
                actionButtonsView
                expandButton
            }
            
            // Change summary
            if let summary = file.changeSummary, !summary.isEmpty {
                HStack(spacing: 6) {
                    if file.addedLines > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 8))
                            Text("+\(file.addedLines)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.green)
                    }
                    if file.removedLines > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 8))
                            Text("-\(file.removedLines)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.leading, 24) // Align with file name
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(headerBackground)
        .overlay(headerOverlay)
        .onHover(perform: handleHover)
    }
    
    private var fileIconView: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: fileIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(fileIconColor)
            
            if file.isStreaming {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.6), radius: 2)
                    
                    Circle()
                        .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.4), lineWidth: 1)
                        .frame(width: 10, height: 10)
                        .scaleEffect(file.isStreaming ? 1.5 : 1.0)
                        .opacity(file.isStreaming ? 0.0 : 0.6)
                        .animation(
                            Animation.easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false),
                            value: file.isStreaming
                        )
                }
                .offset(x: 2, y: -2)
            }
        }
    }
    
    @State private var isFileNameHovered = false
    
    private var fileNameView: some View {
        Button(action: onOpen) {
            Text(file.name)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(isFileNameHovered ? Color(red: 0.2, green: 0.6, blue: 1.0) : .primary)
                .lineLimit(1)
                .underline(isFileNameHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Click to open file in editor")
        .scaleEffect(isFileNameHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFileNameHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isFileNameHovered = hovering
            }
            // Change cursor to pointer on hover
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    @State private var isFilePathHovered = false
    
    private var filePathView: some View {
        Button(action: onOpen) {
            Text(file.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isFilePathHovered ? Color(red: 0.2, green: 0.6, blue: 1.0) : .secondary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Click to open file in editor")
        .scaleEffect(isFilePathHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFilePathHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isFilePathHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private var statusBadgeView: some View {
        Group {
            if file.isStreaming {
                streamingBadge
            } else {
                readyBadge
            }
        }
    }
    
    private var streamingBadge: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .shadow(color: Color.white.opacity(0.8), radius: 1)
                
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .scaleEffect(file.isStreaming ? 1.5 : 1.0)
                    .opacity(file.isStreaming ? 0.0 : 0.8)
                    .animation(
                        Animation.easeOut(duration: 0.8)
                            .repeatForever(autoreverses: false),
                        value: file.isStreaming
                    )
            }
            Text("Generating")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3), radius: 2)
        )
    }
    
    private var readyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Text("Ready")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(red: 0.2, green: 0.8, blue: 0.4))
        )
    }
    
    @State private var isButtonPressed = false
    
    @ViewBuilder
    private var actionButtonsView: some View {
        if isHovered || isExpanded {
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isButtonPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isButtonPressed = false
                        }
                    }
                    onOpen()
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isButtonPressed ? 0.9 : 1.0)
                .help("Open file")
                
                if !isRejected {
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isApplied = true
                        }
                        onApply()
                    }) {
                        Image(systemName: isApplied ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isApplied ? Color(red: 0.2, green: 0.8, blue: 0.4) : Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isApplied ? 1.1 : 1.0)
                    .help(isApplied ? "Applied" : "Apply changes")
                    .disabled(isApplied)
                }
                
                if let reject = onReject, !isApplied {
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isRejected = true
                        }
                        reject()
                    }) {
                        Image(systemName: isRejected ? "xmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isRejected ? Color.red : Color.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isRejected ? 1.1 : 1.0)
                    .help(isRejected ? "Rejected" : "Reject changes")
                    .disabled(isRejected)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .scale(scale: 0.8))
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
    }
    
    @State private var isExpandButtonHovered = false
    
    private var expandButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onToggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isExpandButtonHovered ? Color(red: 0.2, green: 0.6, blue: 1.0) : .secondary)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isExpandButtonHovered ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isExpandButtonHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isExpandButtonHovered = hovering
            }
        }
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor).opacity(0.4))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }
    
    private var headerOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                file.isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: file.isStreaming ? 1.5 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: file.isStreaming)
    }
    
    @ViewBuilder
    private var expandedContent: some View {
        if isExpanded {
            Divider()
                .padding(.horizontal, 12)
                .transition(.opacity)
            codePreview
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
        }
    }
    
    private var codePreview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                codeLinesView
                    .padding(.vertical, 8)
                    .id("bottom")
            }
            .frame(height: 300) // Fixed height, scrollable
            .background(
                Color(NSColor.textBackgroundColor)
                    .opacity(0.5)
            )
            .onChange(of: file.content) { _, _ in
                // Auto-scroll to bottom when content changes
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                // Scroll to bottom on appear
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
    
    private var codeLinesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = file.content.components(separatedBy: .newlines)
            let lineTypes = calculateLineTypes()
            
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                codeLineView(
                    index: index,
                    line: line,
                    type: index < lineTypes.count ? lineTypes[index] : .added
                )
            }
            if file.isStreaming {
                streamingCursorView(lineCount: lines.count)
            }
        }
    }
    
    private func calculateLineTypes() -> [DiffLineType] {
        guard let projectURL = projectURL else {
            // New file - all lines are additions
            return file.content.components(separatedBy: .newlines).map { _ in .added }
        }
        
        let fileURL = projectURL.appendingPathComponent(file.path)
        
        // If file doesn't exist, all lines are new (green)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return file.content.components(separatedBy: .newlines).map { _ in .added }
        }
        
        // Compare existing vs new content
        let existingLines = existingContent.components(separatedBy: .newlines)
        let newLines = file.content.components(separatedBy: .newlines)
        
        var lineTypes: [DiffLineType] = []
        
        // Simple line-by-line comparison
        let maxLines = max(existingLines.count, newLines.count)
        for i in 0..<maxLines {
            let existingLine = i < existingLines.count ? existingLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            
            if let existing = existingLine, let new = newLine {
                if existing == new {
                    lineTypes.append(.unchanged)
                } else {
                    // Line was modified - show as added (green)
                    lineTypes.append(.added)
                }
            } else if newLine != nil {
                // New line added
                lineTypes.append(.added)
            } else if existingLine != nil {
                // Line removed - but we're showing new content, so skip
                // (removed lines won't appear in new content)
            }
        }
        
        // If we have more new lines than we processed, they're all additions
        while lineTypes.count < newLines.count {
            lineTypes.append(.added)
        }
        
        return lineTypes
    }
    
    enum DiffLineType {
        case added
        case removed
        case unchanged
    }
    
    private func codeLineView(index: Int, line: String, type: DiffLineType) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number
            Text("\(index + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            // Change indicator
            Text(changeIndicator(for: type))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(indicatorColor(for: type))
                .frame(width: 14)
            
            // Code content
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(textColor(for: type))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor(for: type))
    }
    
    private func changeIndicator(for type: DiffLineType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }
    
    private func indicatorColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .clear
        }
    }
    
    private func textColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return Color(red: 0.2, green: 0.6, blue: 0.2) // Dark green
        case .removed: return Color(red: 0.7, green: 0.2, blue: 0.2) // Dark red
        case .unchanged: return .primary
        }
    }
    
    private func backgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return Color.green.opacity(0.1)
        case .removed: return Color.red.opacity(0.1)
        case .unchanged: return Color.clear
        }
    }
    
    private func streamingCursorView(lineCount: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineCount + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3))
                    .frame(width: 2, height: 14)
                
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                    .frame(width: 2, height: 14)
                    .opacity(0.9)
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.8), radius: 2)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: file.isStreaming
                    )
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
    }
    
    private var fileCardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
    
    private var fileCardOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                file.isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: file.isStreaming ? 1.5 : 0
            )
            .shadow(
                color: file.isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2) : Color.clear,
                radius: file.isStreaming ? 4 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: file.isStreaming)
    }
    
    // MARK: - Helpers
    
    private func handleHover(_ hovering: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: file.name).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        case "html": return "globe"
        case "css": return "paintbrush"
        case "md": return "doc.text"
        default: return "doc"
        }
    }
    
    private var fileIconColor: Color {
        let ext = URL(fileURLWithPath: file.name).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 1.0, green: 0.4, blue: 0.2)
        case "js", "jsx": return Color(red: 1.0, green: 0.8, blue: 0.0)
        case "ts", "tsx": return Color(red: 0.0, green: 0.5, blue: 0.8)
        case "py": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "json": return Color(red: 0.9, green: 0.9, blue: 0.9)
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

// MARK: - Cursor Action Card (Cursor-style)

struct CursorActionCard: View {
    let action: AIAction
    let streamingContent: String?
    let isStreaming: Bool
    let onOpen: () -> Void
    let onApply: () -> Void
    
    @State private var isHovered = false
    
    private var fileName: String {
        action.filePath ?? action.name
            .replacingOccurrences(of: "Create ", with: "")
            .replacingOccurrences(of: "Modify ", with: "")
    }
    
    private var displayContent: String {
        streamingContent ?? action.fileContent ?? action.result ?? ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerRow
            contentView
        }
        .background(backgroundShape)
        .overlay(overlayShape)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - View Components
    
    private var headerRow: some View {
        HStack(spacing: 10) {
            statusIcon
            fileNameText
            pathText
            Spacer()
            statusBadge
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(headerBackground)
        .overlay(headerOverlay)
        .onHover(perform: handleHover)
    }
    
    private var statusIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: fileIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(fileIconColor)
            
            if isStreaming {
                Circle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -2)
            }
        }
    }
    
    private var fileNameText: some View {
        Text(fileName)
            .font(.system(size: 13, weight: .medium, design: .default))
            .foregroundColor(.primary)
            .lineLimit(1)
    }
    
    @ViewBuilder
    private var pathText: some View {
        if let path = action.filePath {
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            if isStreaming {
                streamingIndicator
                Text("Generating")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text("Ready")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeBackground)
    }
    
    private var streamingIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 4)
                .shadow(color: Color.white.opacity(0.8), radius: 1)
            
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 6, height: 6)
                .scaleEffect(isStreaming ? 1.5 : 1.0)
                .opacity(isStreaming ? 0.0 : 0.8)
                .animation(
                    Animation.easeOut(duration: 0.8)
                        .repeatForever(autoreverses: false),
                    value: isStreaming
                )
        }
    }
    
    private var badgeBackground: some View {
        Capsule()
            .fill(isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0) : Color(red: 0.2, green: 0.8, blue: 0.4))
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        if isHovered {
            HStack(spacing: 4) {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Open file")
                
                Button(action: onApply) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Apply changes")
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .scale(scale: 0.8))
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor).opacity(0.4))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }
    
    private var headerOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: isStreaming ? 1.5 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }
    
    @ViewBuilder
    private var contentView: some View {
        if !displayContent.isEmpty {
            Divider()
                .padding(.horizontal, 12)
            codePreview
        }
    }
    
    private var codePreview: some View {
        ScrollView {
            codeLines
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 300)
        .background(
            Color(NSColor.textBackgroundColor)
                .opacity(0.5)
        )
    }
    
    private var codeLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = displayContent.components(separatedBy: .newlines)
            ForEach(Array(lines.prefix(30).enumerated()), id: \.offset) { index, line in
                codeLine(index: index, line: line)
            }
            if isStreaming {
                streamingCursorLine(lineCount: lines.count)
            }
        }
    }
    
    private func codeLine(index: Int, line: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(index + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func streamingCursorLine(lineCount: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineCount + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3))
                    .frame(width: 2, height: 14)
                
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                    .frame(width: 2, height: 14)
                    .opacity(0.9)
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.8), radius: 2)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: isStreaming
                    )
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
    }
    
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var overlayShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: isStreaming ? 1.5 : 0
            )
            .shadow(
                color: isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2) : Color.clear,
                radius: isStreaming ? 4 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }
    
    // MARK: - Helpers
    
    private func handleHover(_ hovering: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        case "html": return "globe"
        case "css": return "paintbrush"
        case "md": return "doc.text"
        default: return "doc"
        }
    }
    
    private var fileIconColor: Color {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 1.0, green: 0.4, blue: 0.2)
        case "js", "jsx": return Color(red: 1.0, green: 0.8, blue: 0.0)
        case "ts", "tsx": return Color(red: 0.0, green: 0.5, blue: 0.8)
        case "py": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "json": return Color(red: 0.9, green: 0.9, blue: 0.9)
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

