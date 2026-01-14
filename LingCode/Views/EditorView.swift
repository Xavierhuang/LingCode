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
                        onTextChange: { text in
                            viewModel.updateDocumentContent(text)
                        },
                        onSelectionChange: { text, position in
                            viewModel.updateSelection(text, position: position)
                        },
                        onScrollViewCreated: { scrollView in
                            editorScrollView = scrollView
                        }
                    )
                    
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
    
    /// Start inline edit session using EditorCore
    /// 
    /// WORKSPACE-AWARE EDIT EXPANSION:
    /// - Classifies intent BEFORE calling AI
    /// - For simple replacements: scans workspace and generates deterministic edits
    /// - For complex intents: passes expanded file list to AI
    private func startInlineEditSession(instruction: String) {
        guard let document = viewModel.editorState.activeDocument else {
            showInlineEdit = false
            return
        }
        
        // WORKSPACE EXPANSION: Check if this is a simple replace/rename intent
        // This happens BEFORE calling the AI
        if let workspaceURL = viewModel.rootFolderURL {
            let expansion = WorkspaceEditExpansion.shared.expandEditScope(
                prompt: instruction,
                workspaceURL: workspaceURL
            )
            
            // If expansion generated deterministic edits, apply them directly
            if expansion.wasExpanded && !expansion.deterministicEdits.isEmpty {
                handleDeterministicEdits(expansion: expansion, workspaceURL: workspaceURL)
                return
            }
            
            // If files were matched but no edits generated, pass file list to AI
            if !expansion.matchedFiles.isEmpty {
                // Pass expanded file list to AI for complex processing
                startInlineEditSessionWithExpandedFiles(
                    instruction: instruction,
                    matchedFiles: expansion.matchedFiles,
                    workspaceURL: workspaceURL
                )
                return
            }
        }
        
        // Default: Standard single-file edit session
        startStandardEditSession(instruction: instruction, document: document)
    }
    
    /// Handle deterministic edits (bypass AI for simple replacements)
    private func handleDeterministicEdits(
        expansion: WorkspaceEditExpansion.ExpansionResult,
        workspaceURL: URL
    ) {
        // Convert deterministic edits to StreamingFileInfo
        let fileInfos = WorkspaceEditExpansion.shared.convertToStreamingFileInfo(
            edits: expansion.deterministicEdits,
            workspaceURL: workspaceURL
        )
        
        // Apply edits directly (no AI needed)
        // Use FileActionHandler to ensure proper file writing and state management
        print("🔧 APPLYING DETERMINISTIC EDITS:")
        print("   Files matched: \(expansion.matchedFiles.count)")
        print("   Files to modify: \(fileInfos.count)")
        print("   Source: deterministic")
        
        // Note: Expansion result is logged but not stored in state
        // For deterministic edits, completion summary is shown via logging
        
        // Apply each edit using FileActionHandler
        let fileActionHandler = FileActionHandler.shared
        for fileInfo in fileInfos {
            fileActionHandler.applyFile(
                fileInfo,
                projectURL: workspaceURL,
                editorViewModel: viewModel
            )
            print("✅ Applied deterministic edit: \(fileInfo.path)")
        }
        
        // Close edit session (no AI streaming needed)
        cancelEditSession()
        
        // Show completion summary for deterministic edits
        // Note: For deterministic edits, we don't use the normal completion flow
        // The files are already applied, so we just log the summary
        print("📊 DETERMINISTIC EDIT SUMMARY:")
        print("   Files matched: \(expansion.matchedFiles.count)")
        print("   Files modified: \(fileInfos.count)")
        if expansion.matchedFiles.count != fileInfos.count {
            print("   ⚠️ WARNING: Matched \(expansion.matchedFiles.count) files but only modified \(fileInfos.count)")
        }
    }
    
    /// Start edit session with expanded file list (for complex intents)
    private func startInlineEditSessionWithExpandedFiles(
        instruction: String,
        matchedFiles: [URL],
        workspaceURL: URL
    ) {
        // Read file contents for matched files
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
            // Fallback to standard session
            guard let document = viewModel.editorState.activeDocument else { return }
            startStandardEditSession(instruction: instruction, document: document)
            return
        }
        
        // Build instruction with expanded file list
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
        
        // Start session with expanded files
        let session = editorCoreAdapter.startInlineEditSession(
            instruction: fullInstruction,
            userIntent: instruction,
            files: fileStates
        )
        
        currentEditSession = session
        
        // FILE CONTEXT INGESTION: Ensure all project files are in context
        // Build comprehensive context that includes all files in the project folder
        var comprehensiveContext = viewModel.getContextForAI() ?? ""
        
        // Add all project files to context if not already included
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
                    
                    // Check if file is already in context
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
        
        // Stream AI response with comprehensive context
        streamAIResponse(for: session, instruction: fullInstruction, context: comprehensiveContext)
    }
    
    /// Start standard single-file edit session
    private func startStandardEditSession(instruction: String, document: Document) {
        // Prepare file state for EditorCore
        let selectedText = viewModel.editorState.selectedText.isEmpty 
            ? document.content 
            : viewModel.editorState.selectedText
        
        // Create FileStateInput for the active document
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        // Build instruction with context
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
        
        // Start EditorCore session
        let session = editorCoreAdapter.startInlineEditSession(
            instruction: fullInstruction,
            userIntent: instruction,
            files: [fileState]
        )
        
        currentEditSession = session
        
        // FILE CONTEXT INGESTION: Ensure all project files are in context
        // Build comprehensive context that includes all files in the project folder
        var comprehensiveContext = viewModel.getContextForAI() ?? ""
        
        // Add all project files to context if not already included
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
                    
                    // Check if file is already in context
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
        
        // Stream AI response with comprehensive context
        streamAIResponse(for: session, instruction: fullInstruction, context: comprehensiveContext)
    }
    
    /// Show completion summary for deterministic edits
    private func showDeterministicEditSummary(filesMatched: Int, filesModified: Int) {
        // Store summary in a way that CompletionSummaryView can access it
        // For now, log it
        print("📊 DETERMINISTIC EDIT SUMMARY:")
        print("   Files matched: \(filesMatched)")
        print("   Files modified: \(filesModified)")
        if filesMatched != filesModified {
            print("   ⚠️ WARNING: Matched \(filesMatched) files but only modified \(filesModified)")
        }
    }
    
    /// Stream AI response to inline edit session
    /// Uses app-level wrapper type, not EditorCore type
    /// Handles network failures, empty responses, and tracks response state
    ///
    /// EDIT MODE: Enforces strict edit-only output, no explanations or reasoning
    ///
    /// ARCHITECTURAL INVARIANT: HARD SEPARATION OF PHASES
    /// - The Edit Mode prompt explicitly forbids reasoning output
    /// - Validation happens AFTER stream completion, not mid-stream
    /// - UI "Thinking..." state is driven by session state, NOT model text
    /// - Timeline events are derived from state transitions, NOT AI output
    private func streamAIResponse(for session: InlineEditSession, instruction: String, context: String?) {
        // EDIT MODE: Use strict Edit Mode prompt that enforces edit-only output
        // The prompt explicitly forbids reasoning, planning, or explanation output
        // If reasoning is required, it must be internal to the model and NEVER output
        let editModePrompt = EditModePromptBuilder.shared.buildEditModeUserPrompt(instruction: instruction)
        let systemPrompt = EditModePromptBuilder.shared.buildEditModeSystemPrompt()
        
        // Build context with Edit Mode system prompt
        // NOTE: Do NOT mix with CursorSystemPromptService or any prompt that includes "think out loud"
        let editModeContext = context != nil 
            ? "\(systemPrompt)\n\nContext:\n\(context!)" 
            : systemPrompt
        
        var responseText = ""
        var hasReceivedChunks = false
        
        // STREAM HANDLING: Never terminate a stream because of reasoning tokens
        // Reasoning tokens must never be emitted in the first place (enforced by prompt)
        // Validation happens AFTER stream completion, not mid-stream
        AIService.shared.streamMessage(
            editModePrompt,
            context: context, // Keep original context for file contents
            systemPrompt: systemPrompt, // Use Edit Mode system prompt (forbids reasoning output)
            onChunk: { chunk in
                hasReceivedChunks = true
                responseText += chunk
                session.appendStreamingText(chunk)
                // STREAM HANDLING: Do NOT validate mid-stream
                // Accept all chunks and validate only after completion
            },
            onComplete: {
                // VALIDATION RULES: Validation happens AFTER stream completion, not mid-stream
                // Empty output → error
                // NO_OP → valid
                // Any prose/markdown → invalid format error
                // Partial output must not be discarded silently
                let validation = EditOutputValidator.shared.validateEditOutput(responseText)
                
                switch validation {
                case .silentFailure:
                    // Empty response - transition to error state
                    // ARCHITECTURE: State mutations must happen asynchronously
                    let errorMessage = "AI service returned an empty response. Please retry."
                    Task { @MainActor in
                        session.model.status = .error(errorMessage)
                        session.model.errorMessage = errorMessage
                    }
                    print("❌ SILENT FAILURE: Empty response")
                    return
                    
                case .invalidFormat(let reason):
                    // Non-executable output detected - fail fast
                    // ARCHITECTURE: State mutations must happen asynchronously
                    let errorMessage = "AI returned non-executable output. \(reason) Please retry."
                    Task { @MainActor in
                        session.model.status = .error(errorMessage)
                        session.model.errorMessage = errorMessage
                    }
                    print("❌ INVALID FORMAT: \(reason)")
                    print("   Response preview: \(String(responseText.prefix(200)))")
                    return
                    
                case .noOp:
                    // Explicit no-op - valid, but no edits to apply
                    // Let parser handle this (will result in zero files, which is valid for no-op)
                    print("ℹ️ NO-OP: AI indicated no changes needed")
                    break
                    
                case .valid:
                    // Valid edit output - proceed to parsing
                    break
                }
                
                // Check if we have parsed proposals (completion gate)
                // This will be validated when proposals are ready
                session.completeStreaming()
            },
            onError: { error in
                let nsError = error as NSError
                let errorMessage: String
                
                // NETWORK FAILURE HANDLING: Distinguish failure types
                if nsError.code >= 400 && nsError.code < 500 {
                    // Client error (429, 401, etc.)
                    if nsError.code == 429 {
                        errorMessage = "AI service temporarily unavailable. Rate limit exceeded. Please retry."
                    } else {
                        errorMessage = nsError.localizedDescription.isEmpty 
                            ? "AI service temporarily unavailable. HTTP \(nsError.code). Please retry."
                            : nsError.localizedDescription
                    }
                } else if nsError.code >= 500 || nsError.code == 529 || nsError.code == 503 {
                    // Server error (503, 529, etc.)
                    errorMessage = "AI service temporarily unavailable. Service overloaded. Please retry."
                } else {
                    // Other errors
                    errorMessage = nsError.localizedDescription.isEmpty 
                        ? "AI request failed. Please retry."
                        : nsError.localizedDescription
                }
                
                // Log telemetry
                print("❌ AI REQUEST FAILURE:")
                print("   Error code: \(nsError.code)")
                print("   Error domain: \(nsError.domain)")
                print("   Error message: \(errorMessage)")
                print("   Failure category: network_failure")
                
                // Update session state
                session.model.status = .error(errorMessage)
                session.model.errorMessage = errorMessage
            }
        )
    }
    
    /// Accept edits from inline edit session
    /// 
    /// CORE INVARIANT: IDE may only show "Complete" if at least one edit was applied.
    /// Otherwise, show a failure or no-op explanation.
    ///
    /// INVARIANT: This is the only path that calls applyEdits()
    /// Applies only selected proposals (partial accept support)
    private func acceptEdits(from session: InlineEditSession, continueAfter: Bool = false) {
        // Get selected proposal IDs from session model
        let selectedIds = session.model.selectedProposalIds
        
        // If no proposals selected, don't apply anything
        guard !selectedIds.isEmpty else {
            return
        }
        
        // Get file names for timeline
        let acceptedProposals = session.model.proposedEdits.filter { selectedIds.contains($0.id) }
        let fileNames = acceptedProposals.map { $0.fileName }
        
        // Accept only selected proposals (atomic via EditorCore transaction)
        let editsToApply = session.acceptSelected(selectedIds: selectedIds)
        
        // Capture file states before applying edits (for outcome validation)
        let filesBefore = captureFileStatesBeforeEdits(editsToApply: editsToApply)
        
        // Record in timeline before applying
        session.model.recordAccept(count: selectedIds.count, fileNames: fileNames, andContinue: continueAfter)
        
        // Apply edits atomically using adapter function
        viewModel.applyEdits(editsToApply)
        
        // OUTCOME VALIDATION: Verify that changes were actually made
        // CORE INVARIANT: IDE may only show "Complete" if at least one edit was applied
        let filesAfter = captureFileStatesAfterEdits(editsToApply: editsToApply)
        let outcome = ExecutionOutcomeValidator.shared.validateOutcome(
            editsToApply: editsToApply,
            filesBefore: filesBefore,
            filesAfter: filesAfter
        )
        
        // Store outcome in session model for UI to display
        session.model.executionOutcome = outcome
        
        // If no changes were made, record in timeline
        if !outcome.changesApplied {
            let errorMessage = outcome.noOpExplanation ?? "No changes were applied"
            session.model.recordTimelineEvent(
                .error(message: errorMessage),
                description: "No changes applied",
                details: errorMessage
            )
        }
        
        if continueAfter {
            // Continue session with updated file snapshots
            continueEditSession(session)
        } else {
            // Close session
            cancelEditSession()
        }
    }
    
    /// Capture file states before applying edits (for outcome validation)
    private func captureFileStatesBeforeEdits(editsToApply: [InlineEditToApply]) -> [String: String] {
        var filesBefore: [String: String] = [:]
        
        for edit in editsToApply {
            // Get current content from editor
            if let document = viewModel.editorState.documents.first(where: { doc in
                guard let docPath = doc.filePath else { return false }
                return docPath.path == edit.filePath || docPath.lastPathComponent == edit.filePath
            }) {
                filesBefore[edit.filePath] = document.content
            } else {
                // File not open - try to read from disk
                let fileURL: URL
                if edit.filePath.hasPrefix("/") {
                    fileURL = URL(fileURLWithPath: edit.filePath)
                } else if let projectURL = viewModel.rootFolderURL {
                    fileURL = projectURL.appendingPathComponent(edit.filePath)
                } else {
                    continue
                }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    filesBefore[edit.filePath] = content
                }
            }
        }
        
        return filesBefore
    }
    
    /// Capture file states after applying edits (for outcome validation)
    private func captureFileStatesAfterEdits(editsToApply: [InlineEditToApply]) -> [String: String] {
        var filesAfter: [String: String] = [:]
        
        for edit in editsToApply {
            // Get updated content from editor
            if let document = viewModel.editorState.documents.first(where: { doc in
                guard let docPath = doc.filePath else { return false }
                return docPath.path == edit.filePath || docPath.lastPathComponent == edit.filePath
            }) {
                filesAfter[edit.filePath] = document.content
            } else {
                // File not open - try to read from disk
                let fileURL: URL
                if edit.filePath.hasPrefix("/") {
                    fileURL = URL(fileURLWithPath: edit.filePath)
                } else if let projectURL = viewModel.rootFolderURL {
                    fileURL = projectURL.appendingPathComponent(edit.filePath)
                } else {
                    continue
                }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    filesAfter[edit.filePath] = content
                }
            }
        }
        
        return filesAfter
    }
    
    /// Retry edit session with the same execution plan
    /// RETRY SEMANTICS: Reuse execution plan, do NOT reuse partial or empty AI responses
    private func retryEditSession(_ session: InlineEditSession) {
        // Get the original execution plan if available
        guard let executionPlan = session.executionPlan else {
            // No execution plan - fall back to user intent
            if !session.userIntent.isEmpty {
                startInlineEditSession(instruction: session.userIntent)
            } else {
                // Can't retry without plan or intent
                cancelEditSession()
            }
            return
        }
        
        // Close the old session
        cancelEditSession()
        
        // Get current file state
        guard let document = viewModel.editorState.activeDocument else {
            cancelEditSession()
            return
        }
        
        // Create FileStateInput for the active document
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        // Rebuild instruction from execution plan (same plan, fresh request)
        let instruction = buildInstructionFromPlan(executionPlan, fileState: fileState)
        
        // Create new session with same execution plan
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
        
        // Store execution plan in new session
        newSession.executionPlan = executionPlan
        
        currentEditSession = newSession
        
        // FILE CONTEXT INGESTION: Ensure all project files are in context
        let comprehensiveContext = buildComprehensiveContext(baseContext: viewModel.getContextForAI())
        
        // Stream AI response (fresh request, not reusing old response) with comprehensive context
        streamAIResponse(for: newSession, instruction: instruction, context: comprehensiveContext)
        
        // Log telemetry
        print("🔄 RETRY: Restarted edit session with same execution plan")
        print("   Original prompt: \(executionPlan.originalPrompt)")
        print("   Operation: \(executionPlan.operationType.rawValue)")
    }
    
    /// Build instruction from execution plan
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
    
    /// Helper to detect language from file path
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
    
    /// Continue edit session after applying edits
    /// Updates EditorCore file snapshots with current editor state
    private func continueEditSession(_ session: InlineEditSession) {
        guard let document = viewModel.editorState.activeDocument else {
            cancelEditSession()
            return
        }
        
        // Get updated file content from editor
        let selectedText = viewModel.editorState.selectedText.isEmpty 
            ? document.content 
            : viewModel.editorState.selectedText
        
        // Create FileStateInput with updated content
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content, // Updated content after applying edits
            language: document.language
        )
        
        // Build continuation instruction (same as original or allow refinement)
        let continuationInstruction = inlineEditInstruction.isEmpty 
            ? "Continue editing this file" 
            : inlineEditInstruction
        
        // Continue session with updated file snapshots
        session.continueWithUpdatedFiles(
            instruction: continuationInstruction,
            files: [fileState]
        )
        
        // Continue streaming AI response
        streamAIResponse(
            for: session, 
            instruction: continuationInstruction, 
            context: viewModel.getContextForAI()
        )
    }
    
    /// Reject edits from inline edit session
    /// INVARIANT: Rejection does not mutate editor content
    private func rejectEdits(from session: InlineEditSession) {
        // Record in timeline
        session.model.recordStateTransition(from: session.model.status, to: .rejected)
        
        session.rejectAll()
        
        // Close session after a brief delay to show rejection state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            cancelEditSession()
        }
    }
    
    /// Cancel edit session
    private func cancelEditSession() {
        currentEditSession = nil
        showInlineEdit = false
        inlineEditInstruction = ""
    }
    
    /// Reuse intent from an existing session to apply to current file or new files
    /// SAFETY: Creates a completely new session, preserving only the intent
    private func reuseIntent(intent: String, from oldSession: InlineEditSession) {
        // Close the old session
        cancelEditSession()
        
        // Use the current active document or allow file selection
        guard let document = viewModel.editorState.activeDocument else {
            // No active document - start a new session with the intent
            inlineEditInstruction = intent
            startInlineEditSession(instruction: intent)
            return
        }
        
        // Create FileStateInput for the active document
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        // Build instruction with context (same format as original)
        let selectedText = viewModel.editorState.selectedText.isEmpty 
            ? document.content 
            : viewModel.editorState.selectedText
        
        let fullInstruction: String
        if !viewModel.editorState.selectedText.isEmpty {
            fullInstruction = """
            Edit the selected code according to this instruction: \(intent)
            
            Selected code:
            ```
            \(selectedText)
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
        
        // Create new session with reused intent
        let newSession = editorCoreAdapter.reuseIntent(intent: intent, files: [fileState])
        
        currentEditSession = newSession
        
        // FILE CONTEXT INGESTION: Ensure all project files are in context
        let comprehensiveContext = buildComprehensiveContext(baseContext: viewModel.getContextForAI())
        
        // Stream AI response with comprehensive context
        streamAIResponse(for: newSession, instruction: fullInstruction, context: comprehensiveContext)
        
        // Record in timeline
        newSession.model.recordTimelineEvent(.intentReused, description: "Reapplying: \(intent)")
    }
    
    /// Fix syntax errors only and retry with same intent
    /// SAFETY: Creates a new session with focused instruction to fix syntax only
    private func fixSyntaxAndRetry(intent: String, from oldSession: InlineEditSession) {
        // Close the old session
        cancelEditSession()
        
        // Use the current active document
        guard let document = viewModel.editorState.activeDocument else {
            // Fallback: start new session
            inlineEditInstruction = "Fix syntax errors only. Do not refactor or expand scope. \(intent)"
            startInlineEditSession(instruction: inlineEditInstruction)
            return
        }
        
        // Create FileStateInput for the active document
        let fileState = FileStateInput(
            id: document.filePath?.path ?? document.id.uuidString,
            content: document.content,
            language: document.language
        )
        
        // Build focused instruction to fix syntax only
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
        
        // Create new session with focused intent
        let newSession = editorCoreAdapter.startInlineEditSession(
            instruction: fullInstruction,
            userIntent: focusedIntent,
            files: [fileState]
        )
        
        currentEditSession = newSession
        
        // FILE CONTEXT INGESTION: Ensure all project files are in context
        let comprehensiveContext = buildComprehensiveContext(baseContext: viewModel.getContextForAI())
        
        // Stream AI response with comprehensive context
        streamAIResponse(for: newSession, instruction: fullInstruction, context: comprehensiveContext)
        
        // Record in timeline
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
                // Header
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
                
                // Selected code preview
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
                
                // Instruction input
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
                
                // Quick actions
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

