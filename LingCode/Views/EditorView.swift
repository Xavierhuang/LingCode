//
//  EditorView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
// ARCHITECTURE: This view does NOT import EditorCore.
// All EditorCore access goes through EditorCoreAdapter wrapper types.

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var showInlineEdit: Bool = false
    @State private var inlineEditInstruction: String = ""
    @StateObject private var suggestionService = InlineSuggestionService.shared
    @State private var editorScrollView: NSScrollView?
    
    // MARK: - Rename State
    @State private var showRenameSheet = false
    @State private var newNameInput = ""
    @State private var cursorOffsetForRename: Int = 0
    
    // MARK: - Diagnostics & Autocomplete State
    @ObservedObject private var diagnosticsService = DiagnosticsService.shared
    @State private var showAutocomplete = false
    @State private var autocompleteSuggestions: [AutocompleteSuggestion] = []
    @State private var autocompletePosition: CGPoint = .zero
    @State private var autocompleteDebounceTask: Task<Void, Never>?
    
    // EditorCore integration - SINGLE BRIDGE POINT
    // INVARIANT: EditorCoreAdapter is the only way to access EditorCore
    @StateObject private var editorCoreAdapter = EditorCoreAdapter()
    // Uses app-level wrapper type, not EditorCore type
    @State private var currentEditSession: InlineEditSession?
    
    var body: some View {
        Group {
            if let document = viewModel.editorState.activeDocument {
                ZStack {
                    // Combined editor with line numbers in a single scroll view
                    GhostTextEditorWithLineNumbers(
                        text: Binding(
                            get: { document.content },
                            set: { newValue in
                                document.content = newValue
                            }
                        ),
                        isModified: Binding(
                            get: { document.isModified },
                            set: { newValue in
                                document.isModified = newValue
                            }
                        ),
                        fontSize: viewModel.fontSize,
                        fontName: viewModel.fontName,
                        language: document.language,
                        aiGeneratedRanges: document.aiGeneratedRanges,
                        diagnostics: viewModel.currentDiagnostics,
                        onTextChange: { text in
                            viewModel.updateDocumentContent(text)
                            // Update diagnostics with current content (for unsaved changes)
                            if let fileURL = document.filePath {
                                // Send didChange to LSP to trigger diagnostics update
                                Task {
                                    // Ensure file is open and send didChange notification
                                    // LSP will send publishDiagnostics when content changes
                                    // DiagnosticsService will update automatically via callback
                                    do {
                                        try await SourceKitLSPClient.shared.ensureFileOpen(fileURL: fileURL, content: text)
                                    } catch {
                                        // Silently handle errors (LSP might not be available)
                                    }
                                }
                            }
                            // Request autocomplete after typing
                            requestAutocomplete(for: text, at: viewModel.editorState.cursorPosition, in: document)
                        },
                        onSelectionChange: { text, position in
                            viewModel.updateSelection(text, position: position)
                        },
                        onAutocompleteRequest: { position in
                            if let doc = viewModel.editorState.activeDocument {
                                requestAutocomplete(for: doc.content, at: position, in: doc)
                            }
                        },
                        onScrollViewCreated: { scrollView in
                            editorScrollView = scrollView
                        }
                    )
                    .contextMenu {
                        Button {
                            // Capture current cursor position
                            let currentOffset = viewModel.editorState.cursorPosition
                            self.cursorOffsetForRename = currentOffset
                            
                            // Pre-fill the input with the selected text if available
                            if !viewModel.editorState.selectedText.isEmpty {
                                // Extract word from selected text (remove whitespace)
                                self.newNameInput = viewModel.editorState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            } else {
                                self.newNameInput = ""
                            }
                            
                            // Show the dialog
                            self.showRenameSheet = true
                        } label: {
                            Label("Rename Symbol", systemImage: "pencil.and.outline")
                        }
                    }
                    
                    // Ghost text indicator
                    if suggestionService.isLoading {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Generating...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                                .cornerRadius(4)
                                .padding()
                            }
                        }
                    }
                    
                    // Rename loading overlay
                    if viewModel.isRenaming {
                        ZStack {
                            Color.black.opacity(0.4)
                            VStack {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Analyzing Project...")
                                    .foregroundColor(.white)
                                    .padding(.top, 8)
                            }
                            .padding(24)
                            .background(.regularMaterial)
                            .cornerRadius(12)
                        }
                    }
                    
                    // Autocomplete popup
                    if showAutocomplete && !autocompleteSuggestions.isEmpty {
                        AutocompletePopupView(
                            suggestions: autocompleteSuggestions,
                            onSelect: { suggestion in
                                insertAutocompleteSuggestion(suggestion)
                                showAutocomplete = false
                            },
                            position: autocompletePosition
                        )
                    }
                    
                    // Inline Edit (Cmd+K) overlay - EditorCore integration
                    if showInlineEdit {
                        if let session = currentEditSession {
                            // Show EditorCore session view
                            InlineEditSessionView(
                                sessionModel: session.model,
                                onAccept: {
                                    acceptEdits(from: session, continueAfter: false)
                                },
                                onAcceptAndContinue: {
                                    acceptEdits(from: session, continueAfter: true)
                                },
                                onReject: {
                                    rejectEdits(from: session)
                                },
                                onCancel: {
                                    cancelEditSession()
                                },
                                onReuseIntent: { intent in
                                    reuseIntent(intent: intent, from: session)
                                },
                                onFixSyntaxAndRetry: { intent in
                                    fixSyntaxAndRetry(intent: intent, from: session)
                                },
                                onRetry: {
                                    retryEditSession(session)
                                }
                            )
                            .padding()
                        } else {
                            // Show instruction input
                            InlineEditOverlay(
                                isPresented: $showInlineEdit,
                                instruction: $inlineEditInstruction,
                                selectedText: viewModel.editorState.selectedText,
                                onSubmit: { instruction in
                                    startInlineEditSession(instruction: instruction)
                                }
                            )
                        }
                    }
                }
                // Cmd+K shortcut for inline edit
                .keyboardShortcut("k", modifiers: .command)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerInlineEdit"))) { _ in
                    showInlineEdit = true
                }
                // Rename sheet
                .sheet(isPresented: $showRenameSheet) {
                    RenameSymbolSheet(
                        newName: $newNameInput,
                        errorMessage: viewModel.renameErrorMessage,
                        onRename: {
                            guard !newNameInput.isEmpty else { return }
                            Task {
                                await viewModel.performRename(
                                    at: cursorOffsetForRename,
                                    to: newNameInput
                                )
                                // Clear input and close sheet after rename
                                if viewModel.renameErrorMessage == nil {
                                    newNameInput = ""
                                    showRenameSheet = false
                                }
                            }
                        },
                        onCancel: {
                            newNameInput = ""
                            showRenameSheet = false
                        }
                    )
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No file open")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Open a file to start editing")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - EditorCore Integration (⌘K)
    
    private func startInlineEditSession(instruction: String) {
        guard let document = viewModel.editorState.activeDocument else {
            showInlineEdit = false
            return
        }
        
        if let workspaceURL = viewModel.rootFolderURL {
            let expansion = WorkspaceEditExpansion.shared.expandEditScope(
                prompt: instruction,
                workspaceURL: workspaceURL
            )
            
            if expansion.wasExpanded && !expansion.deterministicEdits.isEmpty {
                handleDeterministicEdits(expansion: expansion, workspaceURL: workspaceURL)
                return
            }
            
            if !expansion.matchedFiles.isEmpty {
                startInlineEditSessionWithExpandedFiles(
                    instruction: instruction,
                    matchedFiles: expansion.matchedFiles,
                    workspaceURL: workspaceURL
                )
                return
            }
        }
        
        startStandardEditSession(instruction: instruction, document: document)
    }
    
    private func handleDeterministicEdits(
        expansion: WorkspaceEditExpansion.ExpansionResult,
        workspaceURL: URL
    ) {
        let fileInfos = WorkspaceEditExpansion.shared.convertToStreamingFileInfo(
            edits: expansion.deterministicEdits,
            workspaceURL: workspaceURL
        )
        
        print("🔧 APPLYING DETERMINISTIC EDITS:")
        print("   Files matched: \(expansion.matchedFiles.count)")
        print("   Files to modify: \(fileInfos.count)")
        
        let fileActionHandler = FileActionHandler.shared
        for fileInfo in fileInfos {
            fileActionHandler.applyFile(
                fileInfo,
                projectURL: workspaceURL,
                editorViewModel: viewModel
            )
            print("✅ Applied deterministic edit: \(fileInfo.path)")
        }
        
        cancelEditSession()
        
        print("📊 DETERMINISTIC EDIT SUMMARY:")
        print("   Files matched: \(expansion.matchedFiles.count)")
        print("   Files modified: \(fileInfos.count)")
    }
    
    private func startInlineEditSessionWithExpandedFiles(
        instruction: String,
        matchedFiles: [URL],
        workspaceURL: URL
    ) {
        var fileStates: [FileStateInput] = []
        
        for fileURL in matchedFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            
            let relativePath = fileURL.path.replacingOccurrences(of: workspaceURL.path + "/", with: "")
            let language = detectLanguageFromPath(relativePath)
            
            fileStates.append(FileStateInput(
                id: relativePath,
                content: content,
                language: language
            ))
        }
        
        guard !fileStates.isEmpty else {
            guard let document = viewModel.editorState.activeDocument else { return }
            startStandardEditSession(instruction: instruction, document: document)
            return
        }
        
        let fileContexts = fileStates.map { file in
            """
            File: \(file.id)
            Content:
            ```
            \(file.content)
            ```
            """
        }.joined(separator: "\n\n")
        
        let fullInstruction = """
        Edit these files according to this instruction: \(instruction)
        
        \(fileContexts)
        
        Return the edited code in the same format.
        """
        
        let session = editorCoreAdapter.startInlineEditSession(
            instruction: fullInstruction,
            userIntent: instruction,
            files: fileStates
        )
        
        currentEditSession = session
        
        // FIX: Build context asynchronously with parallel file reading
        Task {
            var comprehensiveContext = await viewModel.getContextForAI() ?? ""
            if let projectURL = viewModel.rootFolderURL {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(
                    at: projectURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    var projectFiles: [String] = []
                    for case let fileURL as URL in enumerator {
                        guard !fileURL.hasDirectoryPath,
                              let content = try? String(contentsOf: fileURL, encoding: .utf8),
                              content.count > 0 else { continue }
                        
                        let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                        if !comprehensiveContext.contains(relativePath) {
                            projectFiles.append("--- \(relativePath) ---\n\(content)\n")
                        }
                    }
                    if !projectFiles.isEmpty {
                        comprehensiveContext += "\n\n--- ALL PROJECT FILES ---\n"
                        comprehensiveContext += projectFiles.joined(separator: "\n")
                    }
                }
            }
            
            await MainActor.run {
                streamAIResponse(for: session, instruction: fullInstruction, context: comprehensiveContext)
            }
        }
    }
    
    private func startStandardEditSession(instruction: String, document: Document) {
        let selectedText = viewModel.editorState.selectedText.isEmpty
            ? document.content
            : viewModel.editorState.selectedText
        
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        let fullInstruction: String
        if !viewModel.editorState.selectedText.isEmpty {
            fullInstruction = """
            Edit the selected code according to this instruction: \(instruction)
            
            Selected code:
            ```
            \(selectedText)
            ```
            
            Return the edited code in the same format.
            """
        } else {
            fullInstruction = """
            Edit this file according to this instruction: \(instruction)
            
            File content:
            ```
            \(document.content)
            ```
            """
        }
        
        let session = editorCoreAdapter.startInlineEditSession(
            instruction: fullInstruction,
            userIntent: instruction,
            files: [fileState]
        )
        
        currentEditSession = session
        
        // FIX: Build context asynchronously with parallel file reading
        Task {
            var comprehensiveContext = await viewModel.getContextForAI() ?? ""
            if let projectURL = viewModel.rootFolderURL {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(
                    at: projectURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    var projectFiles: [String] = []
                    for case let fileURL as URL in enumerator {
                        guard !fileURL.hasDirectoryPath,
                              let content = try? String(contentsOf: fileURL, encoding: .utf8),
                              content.count > 0 else { continue }
                        
                        let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                        if !comprehensiveContext.contains(relativePath) {
                            projectFiles.append("--- \(relativePath) ---\n\(content)\n")
                        }
                    }
                    if !projectFiles.isEmpty {
                        comprehensiveContext += "\n\n--- ALL PROJECT FILES ---\n"
                        comprehensiveContext += projectFiles.joined(separator: "\n")
                    }
                }
            }
            
            await MainActor.run {
                streamAIResponse(for: session, instruction: fullInstruction, context: comprehensiveContext)
            }
        }
    }
    
    private func streamAIResponse(for session: InlineEditSession, instruction: String, context: String?) {
        let editModePrompt = EditModePromptBuilder.shared.buildEditModeUserPrompt(instruction: instruction)
        let systemPrompt = EditModePromptBuilder.shared.buildEditModeSystemPrompt()
        
        var responseText = ""
        var isStreamBlocked = false // SAFETY FLAG: Stops feeding garbage to the editor
        
        // Use ModernAIService with async/await
        Task { @MainActor in
            do {
                let aiService: AIProviderProtocol = ServiceContainer.shared.ai
                let stream = aiService.streamMessage(
                    editModePrompt,
                    context: context,
                    images: [],
                    maxTokens: nil,
                    systemPrompt: systemPrompt,
                    tools: nil
                )
                
                // Process stream chunks
                for try await chunk in stream {
                    responseText += chunk
                    
                    // CRITICAL CRASH FIX: Guard against "## PLAN" output
                    // If we detect the AI is outputting a Plan (markdown), STOP updating the session.
                    // Sending 17k chars of markdown to the code editor crashes the ViewBridge.
                    if !isStreamBlocked {
                        let fullText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Check start of stream for forbidden headers
                        if fullText.count < 500 && (fullText.hasPrefix("##") || fullText.hasPrefix("**Plan") || fullText.contains("## PLAN")) {
                            print("⚠️ STREAM GUARD: Detected 'PLAN' output. Blocking stream to editor to prevent crash.")
                            isStreamBlocked = true
                            continue
                        }
                        
                        // Normal behavior
                        session.appendStreamingText(chunk)
                    }
                }
                
                // Stream completed - run validation in background
                Task.detached(priority: .userInitiated) {
                    let validation = await EditOutputValidator.shared.validateEditOutput(responseText)
                    
                    // Switch to MainActor for UI updates
                    await MainActor.run {
                        switch validation {
                        case .silentFailure:
                            let msg = "AI service returned an empty response. Please retry."
                            session.model.status = .error(msg)
                            session.model.errorMessage = msg
                            
                        case .invalidFormat(let reason):
                            let msg = "AI returned non-executable output. \(reason) Please retry."
                            session.model.status = .error(msg)
                            session.model.errorMessage = msg
                            
                        case .noOp:
                            print("ℹ️ NO-OP: AI indicated no changes needed")
                            session.completeStreaming()
                            
                        case .recovered(_):
                            // CRITICAL FIX: Do NOT proceed with dirty text.
                            // The session contains the original dirty text (with explanations).
                            // If we try to parse it, EditorCore will choke/crash.
                            // Since we can't replace the text in the session, we must fail safely.
                            print("⚠️ RECOVERED: AI output contained garbage. Failing safely.")
                            let msg = "AI output contained formatting errors (e.g. Plan/Reasoning). Please retry."
                            session.model.status = .error(msg)
                            session.model.errorMessage = msg

                        case .valid:
                            // Valid edit output - proceed to parsing
                            session.completeStreaming()
                        }
                    }
                }
            } catch {
                // Handle errors
                let nsError = error as NSError
                let errorMessage: String
                
                if nsError.code >= 400 && nsError.code < 500 {
                    if nsError.code == 429 {
                        errorMessage = "AI service temporarily unavailable. Rate limit exceeded. Please retry."
                    } else {
                        errorMessage = nsError.localizedDescription.isEmpty
                            ? "AI service temporarily unavailable. HTTP \(nsError.code). Please retry."
                            : nsError.localizedDescription
                    }
                } else if nsError.code >= 500 || nsError.code == 529 || nsError.code == 503 {
                    errorMessage = "AI service temporarily unavailable. Service overloaded. Please retry."
                } else {
                    errorMessage = nsError.localizedDescription.isEmpty
                        ? "AI request failed. Please retry."
                        : nsError.localizedDescription
                }
                
                print("❌ AI REQUEST FAILURE:")
                print("   Error code: \(nsError.code)")
                print("   Error message: \(errorMessage)")
                
                session.model.status = .error(errorMessage)
                session.model.errorMessage = errorMessage
            }
        }
    }
    
    private func acceptEdits(from session: InlineEditSession, continueAfter: Bool = false) {
        let selectedIds = session.model.selectedProposalIds
        guard !selectedIds.isEmpty else { return }
        
        let acceptedProposals = session.model.proposedEdits.filter { selectedIds.contains($0.id) }
        let fileNames = acceptedProposals.map { $0.fileName }
        
        let editsToApply = session.acceptSelected(selectedIds: selectedIds)
        let filesBefore = captureFileStatesBeforeEdits(editsToApply: editsToApply)
        
        session.model.recordAccept(count: selectedIds.count, fileNames: fileNames, andContinue: continueAfter)
        
        viewModel.applyEdits(editsToApply)
        
        let filesAfter = captureFileStatesAfterEdits(editsToApply: editsToApply)
        let outcome = ExecutionOutcomeValidator.shared.validateOutcome(
            editsToApply: editsToApply,
            filesBefore: filesBefore,
            filesAfter: filesAfter
        )
        
        session.model.executionOutcome = outcome
        
        if !outcome.changesApplied {
            let errorMessage = outcome.noOpExplanation ?? "No changes were applied"
            session.model.recordTimelineEvent(
                .error(message: errorMessage),
                description: "No changes applied",
                details: errorMessage
            )
        }
        
        if continueAfter {
            continueEditSession(session)
        } else {
            cancelEditSession()
        }
    }
    
    private func captureFileStatesBeforeEdits(editsToApply: [InlineEditToApply]) -> [String: String] {
        var filesBefore: [String: String] = [:]
        for edit in editsToApply {
            if let document = viewModel.editorState.documents.first(where: { doc in
                guard let docPath = doc.filePath else { return false }
                return docPath.path == edit.filePath || docPath.lastPathComponent == edit.filePath
            }) {
                filesBefore[edit.filePath] = document.content
            } else {
                let fileURL: URL
                if edit.filePath.hasPrefix("/") {
                    fileURL = URL(fileURLWithPath: edit.filePath)
                } else if let projectURL = viewModel.rootFolderURL {
                    fileURL = projectURL.appendingPathComponent(edit.filePath)
                } else { continue }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    filesBefore[edit.filePath] = content
                }
            }
        }
        return filesBefore
    }
    
    private func captureFileStatesAfterEdits(editsToApply: [InlineEditToApply]) -> [String: String] {
        var filesAfter: [String: String] = [:]
        for edit in editsToApply {
            if let document = viewModel.editorState.documents.first(where: { doc in
                guard let docPath = doc.filePath else { return false }
                return docPath.path == edit.filePath || docPath.lastPathComponent == edit.filePath
            }) {
                filesAfter[edit.filePath] = document.content
            } else {
                let fileURL: URL
                if edit.filePath.hasPrefix("/") {
                    fileURL = URL(fileURLWithPath: edit.filePath)
                } else if let projectURL = viewModel.rootFolderURL {
                    fileURL = projectURL.appendingPathComponent(edit.filePath)
                } else { continue }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    filesAfter[edit.filePath] = content
                }
            }
        }
        return filesAfter
    }
    
    private func retryEditSession(_ session: InlineEditSession) {
        guard let executionPlan = session.executionPlan else {
            if !session.userIntent.isEmpty {
                startInlineEditSession(instruction: session.userIntent)
            } else {
                cancelEditSession()
            }
            return
        }
        
        cancelEditSession()
        guard let document = viewModel.editorState.activeDocument else { return }
        
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        let instruction = buildInstructionFromPlan(executionPlan, fileState: fileState)
        
        let newSession = editorCoreAdapter.startInlineEditSession(
            instruction: instruction,
            userIntent: executionPlan.originalPrompt,
            files: [fileState],
            context: ExecutionPlanner.PlanningContext(
                selectedText: viewModel.editorState.selectedText.isEmpty ? nil : viewModel.editorState.selectedText,
                currentFilePath: fileState.id,
                allFilePaths: [fileState.id],
                limitToCurrentFile: true
            )
        )
        
        newSession.executionPlan = executionPlan
        currentEditSession = newSession
        
        // FIX: Build context asynchronously
        Task {
            let baseContext = await viewModel.getContextForAI() ?? ""
            let comprehensiveContext = buildComprehensiveContext(baseContext: baseContext)
            await MainActor.run {
                streamAIResponse(for: newSession, instruction: instruction, context: comprehensiveContext)
            }
        }
    }
    
    private func buildInstructionFromPlan(_ plan: ExecutionPlan, fileState: FileStateInput) -> String {
        let selectedText = viewModel.editorState.selectedText.isEmpty
            ? fileState.content
            : viewModel.editorState.selectedText
        
        if !viewModel.editorState.selectedText.isEmpty {
            return """
            Edit the selected code according to this instruction: \(plan.originalPrompt)
            
            Selected code:
            ```
            \(selectedText)
            ```
            
            Return the edited code in the same format.
            """
        } else {
            return """
            Edit this file according to this instruction: \(plan.originalPrompt)
            
            File content:
            ```
            \(fileState.content)
            ```
            
            Return the edited code in the same format.
            """
        }
    }
    
    private func detectLanguageFromPath(_ path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        case "rs": return "rust"
        case "go": return "go"
        default: return nil
        }
    }
    
    private func continueEditSession(_ session: InlineEditSession) {
        guard let document = viewModel.editorState.activeDocument else {
            cancelEditSession()
            return
        }
        
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        let continuationInstruction = inlineEditInstruction.isEmpty
            ? "Continue editing this file"
            : inlineEditInstruction
        
        session.continueWithUpdatedFiles(
            instruction: continuationInstruction,
            files: [fileState]
        )
        
        // FIX: Build context asynchronously
        Task {
            let context = await viewModel.getContextForAI() ?? ""
            await MainActor.run {
                streamAIResponse(
                    for: session,
                    instruction: continuationInstruction,
                    context: context
                )
            }
        }
    }
    
    private func rejectEdits(from session: InlineEditSession) {
        session.model.recordStateTransition(from: session.model.status, to: .rejected)
        session.rejectAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            cancelEditSession()
        }
    }
    
    private func cancelEditSession() {
        currentEditSession = nil
        showInlineEdit = false
        inlineEditInstruction = ""
    }
    
    private func reuseIntent(intent: String, from oldSession: InlineEditSession) {
        cancelEditSession()
        guard let document = viewModel.editorState.activeDocument else {
            inlineEditInstruction = intent
            startInlineEditSession(instruction: intent)
            return
        }
        
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        let fullInstruction: String
        if !viewModel.editorState.selectedText.isEmpty {
            fullInstruction = """
            Edit the selected code according to this instruction: \(intent)
            
            Selected code:
            ```
            \(viewModel.editorState.selectedText)
            ```
            
            Return the edited code in the same format.
            """
        } else {
            fullInstruction = """
            Edit this file according to this instruction: \(intent)
            
            File content:
            ```
            \(document.content)
            ```
            """
        }
        
        let newSession = editorCoreAdapter.reuseIntent(intent: intent, files: [fileState])
        currentEditSession = newSession
        
        // FIX: Build context asynchronously
        Task {
            let baseContext = await viewModel.getContextForAI() ?? ""
            let comprehensiveContext = buildComprehensiveContext(baseContext: baseContext)
            await MainActor.run {
                streamAIResponse(for: newSession, instruction: fullInstruction, context: comprehensiveContext)
            }
        }
        newSession.model.recordTimelineEvent(.intentReused, description: "Reapplying: \(intent)")
    }
    
    private func fixSyntaxAndRetry(intent: String, from oldSession: InlineEditSession) {
        cancelEditSession()
        guard let document = viewModel.editorState.activeDocument else {
            inlineEditInstruction = "Fix syntax errors only. Do not refactor or expand scope. \(intent)"
            startInlineEditSession(instruction: inlineEditInstruction)
            return
        }
        
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        let focusedIntent = "Fix syntax errors only. Do not refactor or expand scope. \(intent)"
        
        let fullInstruction: String
        if !viewModel.editorState.selectedText.isEmpty {
            fullInstruction = """
            Fix syntax errors in the selected code. Do not refactor or expand scope.
            
            Original instruction: \(intent)
            
            Selected code:
            ```
            \(viewModel.editorState.selectedText)
            ```
            
            Return the fixed code with syntax errors corrected only.
            """
        } else {
            fullInstruction = """
            Fix syntax errors in this file. Do not refactor or expand scope.
            
            Original instruction: \(intent)
            
            File content:
            ```
            \(document.content)
            ```
            
            Return the fixed code with syntax errors corrected only.
            """
        }
        
        let newSession = editorCoreAdapter.startInlineEditSession(
            instruction: fullInstruction,
            userIntent: focusedIntent,
            files: [fileState]
        )
        
        currentEditSession = newSession
        
        // FIX: Build context asynchronously
        Task {
            let baseContext = await viewModel.getContextForAI() ?? ""
            let comprehensiveContext = buildComprehensiveContext(baseContext: baseContext)
            await MainActor.run {
                streamAIResponse(for: newSession, instruction: fullInstruction, context: comprehensiveContext)
            }
        }
        newSession.model.recordTimelineEvent(.intentReused, description: "Fixing syntax errors: \(intent)")
    }
}

// MARK: - Inline Edit Overlay (Cmd+K)

struct InlineEditOverlay: View {
    @Binding var isPresented: Bool
    @Binding var instruction: String
    let selectedText: String
    let onSubmit: (String) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("Edit with AI")
                        .font(.headline)
                    Spacer()
                    Text("Cmd+K")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                if !selectedText.isEmpty {
                    ScrollView {
                        Text(selectedText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 100)
                    .background(Color(NSColor.textBackgroundColor))
                }
                
                Divider()
                
                HStack {
                    TextField("What do you want to change?", text: $instruction)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .onSubmit {
                            if !instruction.isEmpty {
                                onSubmit(instruction)
                            }
                        }
                    
                    Button(action: {
                        if !instruction.isEmpty {
                            onSubmit(instruction)
                        }
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(instruction.isEmpty ? .gray : .purple)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(instruction.isEmpty)
                }
                .padding()
                
                HStack(spacing: 8) {
                    QuickEditButton(title: "Add comments", icon: "text.bubble") {
                        instruction = "Add comments to explain this code"
                        onSubmit(instruction)
                    }
                    QuickEditButton(title: "Fix bugs", icon: "ladybug") {
                        instruction = "Fix any bugs in this code"
                        onSubmit(instruction)
                    }
                    QuickEditButton(title: "Optimize", icon: "bolt") {
                        instruction = "Optimize this code for performance"
                        onSubmit(instruction)
                    }
                    QuickEditButton(title: "Simplify", icon: "arrow.triangle.branch") {
                        instruction = "Simplify this code"
                        onSubmit(instruction)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 20)
            .frame(maxWidth: 600)
            .padding()
        }
        .background(Color.black.opacity(0.3))
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            isPresented = false
        }
    }
}

struct QuickEditButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Rename Symbol Sheet

struct RenameSymbolSheet: View {
    @Binding var newName: String
    let errorMessage: String?
    let onRename: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Symbol")
                .font(.headline)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("New Name:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Enter new name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !newName.isEmpty {
                            onRename()
                        }
                    }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                } else {
                    Text("Enter the new name for this symbol")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Rename") {
                    onRename()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding(.bottom)
        }
        .frame(width: 400)
        .padding()
        .onAppear {
            // Focus the text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - EditorView Autocomplete Extension

extension EditorView {
    // MARK: - Autocomplete Integration
    
    private func requestAutocomplete(for text: String, at position: Int, in document: Document) {
        // Cancel previous request
        autocompleteDebounceTask?.cancel()
        
        // Debounce autocomplete requests
        autocompleteDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            guard !Task.isCancelled,
                  let fileURL = document.filePath,
                  let projectURL = viewModel.rootFolderURL else {
                return
            }
            
            // Convert character offset to LSP position
            // Safe, fast O(n) calculation that doesn't create huge arrays
            let clampedPosition = min(max(0, position), text.count)
            let prefix = text.prefix(clampedPosition)
            let line = prefix.filter({ $0 == "\n" }).count
            let lastNewlineIndex = prefix.lastIndex(of: "\n")
            let character = lastNewlineIndex.map { prefix.distance(from: $0, to: prefix.endIndex) - 1 } ?? clampedPosition
            
            let lspPosition = LSPPosition(line: line, character: character)
            
            // Request LSP completions
            let suggestions = await AutocompleteService.shared.getLSPCompletions(
                at: lspPosition,
                in: fileURL,
                fileContent: text,
                projectURL: projectURL
            )
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if !suggestions.isEmpty {
                    autocompleteSuggestions = suggestions
                    // Calculate popup position (near cursor)
                    // This is a simplified calculation - in production, you'd get actual cursor rect
                    autocompletePosition = CGPoint(x: 200, y: 100) // Placeholder
                    showAutocomplete = true
                } else {
                    showAutocomplete = false
                }
            }
        }
    }
    
    private func insertAutocompleteSuggestion(_ suggestion: AutocompleteSuggestion) {
        guard let document = viewModel.editorState.activeDocument else { return }
        
        let currentText = document.content
        let position = viewModel.editorState.cursorPosition
        
        let beforeCursor = String(currentText.prefix(position))
        let afterCursor = String(currentText.suffix(currentText.count - position))
        
        // Replace the range with the suggestion text
        let newText = beforeCursor + suggestion.text + afterCursor
        viewModel.updateDocumentContent(newText)
        
        // Update cursor position
        let newPosition = position + suggestion.text.count
        viewModel.updateSelection("", position: newPosition)
    }
}
