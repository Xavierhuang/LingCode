//
//  EditorViewModel.swift
//  LingCode
//
//  Main view model for the editor with settings persistence
//

import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

class EditorViewModel: ObservableObject {
    @Published var editorState = EditorState()
    @Published var fontSize: CGFloat = EditorConstants.defaultFontSize
    @Published var fontName: String = EditorConstants.defaultFontName
    @Published var wordWrap: Bool = false
    @Published var includeRelatedFilesInContext: Bool = true
    
    // MARK: - Refactoring State
    @Published var isRenaming: Bool = false
    @Published var renameErrorMessage: String?
    
    // MARK: - Diagnostics State
    @Published var currentDiagnostics: [EditorDiagnostic] = []
    
    // AI
    let aiViewModel = AIViewModel()
    
    // Project - @Published so UI updates when folder changes
    @Published var rootFolderURL: URL? {
        didSet {
            // Index codebase when project opens
            if let url = rootFolderURL {
                print("rootFolderURL set to: \(url.path)")
                CodebaseIndexService.shared.indexProject(at: url) { _, _ in }
                // Also index for semantic search
                SemanticSearchService.shared.indexWorkspace(url)
            }
        }
    }

    // File tree refresh trigger - toggle this to force file tree refresh
    @Published var fileTreeRefreshTrigger: Bool = false
    
    private let settingsService = SettingsPersistenceService.shared
    private var cancellables = Set<AnyCancellable>()
    private var editorStateCancellable: AnyCancellable?
    
    init() {
        // Set editor reference in AIViewModel
        aiViewModel.editorViewModel = self
        // Forward editorState changes to this view model so SwiftUI updates
        editorStateCancellable = editorState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        // FIX: Listen for file creation/update notifications to refresh file tree AND open files
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FileCreated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            self.refreshFileTree()
            
            // FIX: Open file in editor with highlighting (like Cursor does)
            if let userInfo = notification.userInfo,
               let fileURL = userInfo["fileURL"] as? URL,
               let originalContent = userInfo["originalContent"] as? String {
                // Small delay to ensure file write is complete
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    print("🟢 [EditorViewModel] Opening newly created file: \(fileURL.lastPathComponent)")
                    self.openFile(at: fileURL, originalContent: originalContent)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FileUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            self.refreshFileTree()
            
            // FIX: Open file in editor with change highlighting (like Cursor does)
            if let userInfo = notification.userInfo,
               let fileURL = userInfo["fileURL"] as? URL,
               let originalContent = userInfo["originalContent"] as? String {
                // Small delay to ensure file write is complete
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    print("🟢 [EditorViewModel] Opening updated file with highlighting: \(fileURL.lastPathComponent)")
                    self.openFile(at: fileURL, originalContent: originalContent)
                }
            }
        }
        
        // Also listen for ToolFileWritten (from ToolExecutionService)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToolFileWritten"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            self.refreshFileTree()
            
            // FIX: Open file in editor when tool writes it
            if let userInfo = notification.userInfo,
               let fileURL = userInfo["fileURL"] as? URL {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    print("🟢 [EditorViewModel] Opening file written by tool: \(fileURL.lastPathComponent)")
                    // Try to get original content if available
                    let originalContent = userInfo["originalContent"] as? String
                    self.openFile(at: fileURL, originalContent: originalContent)
                }
            }
        }
        
        // Load settings from persistence
        loadSettings()
        
        // Save settings when they change
        $fontSize
            .dropFirst()
            .sink { [weak self] size in
                self?.settingsService.saveFontSize(size)
            }
            .store(in: &cancellables)
        
        $fontName
            .dropFirst()
            .sink { [weak self] name in
                self?.settingsService.saveFontName(name)
            }
            .store(in: &cancellables)
        
        $wordWrap
            .dropFirst()
            .sink { [weak self] enabled in
                self?.settingsService.saveWordWrap(enabled)
            }
            .store(in: &cancellables)
        
        $includeRelatedFilesInContext
            .dropFirst()
            .sink { [weak self] enabled in
                self?.settingsService.saveIncludeRelatedFiles(enabled)
            }
            .store(in: &cancellables)
        
        // Load AI settings
        aiViewModel.showThinkingProcess = settingsService.loadShowThinkingProcess()
        aiViewModel.autoExecuteCode = settingsService.loadAutoExecuteCode()
        
        // Save AI settings when they change
        aiViewModel.$showThinkingProcess
            .dropFirst()
            .sink { [weak self] enabled in
                self?.settingsService.saveShowThinkingProcess(enabled)
            }
            .store(in: &cancellables)
        
        aiViewModel.$autoExecuteCode
            .dropFirst()
            .sink { [weak self] enabled in
                self?.settingsService.saveAutoExecuteCode(enabled)
            }
            .store(in: &cancellables)
        
        // MARK: - Diagnostics Subscription
        // Update diagnostics when active document changes or diagnostics update
        setupDiagnosticsSubscription()
    }
    
    // MARK: - Diagnostics Integration
    
    /// Setup subscription to diagnostics service to update currentDiagnostics
    private func setupDiagnosticsSubscription() {
        let diagnosticsService = DiagnosticsService.shared
        
        // Combine active document changes with diagnostics updates
        Publishers.CombineLatest(
            editorState.$activeDocumentId,
            diagnosticsService.$diagnostics
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] activeDocumentId, _ in
            guard let self = self else { return }
            
            // Get active document
            guard let documentId = activeDocumentId,
                  let document = self.editorState.documents.first(where: { $0.id == documentId }),
                  let fileURL = document.filePath else {
                // No active document or no file path
                self.currentDiagnostics = []
                return
            }
            
            // Use DiagnosticsService.getDiagnostics which handles range conversion properly
            // This ensures ranges are accurate even for unsaved changes (dirty buffer)
            // Run heavy work off main thread to avoid blocking UI
            let fileURLCopy = fileURL
            let contentCopy = document.content
            Task.detached(priority: .userInitiated) { [weak self] in
                // Get diagnostics (may do array mapping/validation)
                // Note: getDiagnostics is @MainActor, so we call it on main actor
                let diagnostics = await MainActor.run {
                    return diagnosticsService.getDiagnostics(
                        for: fileURLCopy,
                        fileContent: contentCopy
                    )
                }
                // Dispatch result back to main thread
                // FIX: Capture self weakly and ensure main actor isolation
                await MainActor.run { [weak self] in
                    self?.currentDiagnostics = diagnostics
                }
            }
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Settings Loading
    
    private func loadSettings() {
        fontSize = settingsService.loadFontSize()
        fontName = settingsService.loadFontName()
        wordWrap = settingsService.loadWordWrap()
        includeRelatedFilesInContext = settingsService.loadIncludeRelatedFiles()
    }
    
    // MARK: - Document Management
    
    func createNewDocument() {
        let document = Document(
            id: UUID(),
            filePath: nil,
            content: "",
            isModified: false
        )
        editorState.addDocument(document)
    }
    
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        
        let response = panel.runModal()
        print("Panel response: \(response == .OK ? "OK" : "Cancel")")
        
        if response == .OK {
            if let url = panel.url {
                print("Selected folder: \(url.path)")
                self.rootFolderURL = url
                print("rootFolderURL is now: \(self.rootFolderURL?.path ?? "nil")")
            } else {
                print("panel.url was nil")
            }
        }
    }
    
    func openFile(at url: URL, originalContent: String? = nil) {
        // Precompute AST in background for performance
        if let projectURL = rootFolderURL {
            Task(priority: .utility) {
                await LatencyOptimizer.shared.precompute(for: url, projectURL: projectURL)
            }
        }
        // Resolve symlinks and standardize the URL
        let resolvedURL = url.resolvingSymlinksInPath()
        let standardizedURL = URL(fileURLWithPath: resolvedURL.path)

        // Check if file is already open (compare by path to handle URL variations)
        if let existingDocument = editorState.documents.first(where: { doc in
            guard let docPath = doc.filePath else { return false }
            return docPath.path == standardizedURL.path
        }) {
            // File already open - refresh it with latest content from disk
            // Defer state changes to avoid publishing during view updates
            Task { @MainActor in
                // Always read latest content from disk to ensure it's up to date
                if let diskContent = try? String(contentsOf: standardizedURL, encoding: .utf8) {
                    existingDocument.content = diskContent
                    existingDocument.isModified = false
                    
                    // Mark as AI-generated if we have original content for highlighting
                    if let original = originalContent {
                        existingDocument.markAsAIGenerated(originalContent: original)
                    }
                }
                editorState.setActiveDocument(existingDocument.id)
            }
            return
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            print("⚠️ File does not exist: \(standardizedURL.path)")
            return
        }

        do {
            let content = try String(contentsOf: standardizedURL, encoding: .utf8)
            let document = Document(
                id: UUID(),
                filePath: standardizedURL,
                content: content,
                isModified: false
            )
            document.language = detectLanguage(from: standardizedURL.pathExtension)

            // Mark as AI-generated if we have original content for comparison
            if let original = originalContent {
                document.markAsAIGenerated(originalContent: original)
            }

            // Defer state changes to avoid publishing during view updates
            Task { @MainActor in
                editorState.addDocument(document)
                editorState.setActiveDocument(document.id)
            }
        } catch {
            // Silently handle errors
        }
    }
    
    func closeDocument(_ documentId: UUID) {
        editorState.closeDocument(documentId)
    }
    
    func updateDocumentContent(_ content: String) {
        guard let document = editorState.activeDocument else { return }
        document.content = content
        document.isModified = true
        if let index = editorState.documents.firstIndex(where: { $0.id == document.id }) {
            editorState.documents[index] = document
        }
        
        // Refresh diagnostics with updated content to ensure ranges are valid
        refreshCurrentDiagnostics()
    }
    
    /// Refresh current diagnostics with the latest document content
    private func refreshCurrentDiagnostics() {
        guard let document = editorState.activeDocument,
              let fileURL = document.filePath else {
            currentDiagnostics = []
            return
        }
        
        // Run off main thread to avoid blocking UI during typing
        let fileURLCopy = fileURL
        let contentCopy = document.content
        let diagnosticsService = DiagnosticsService.shared
        Task.detached(priority: .userInitiated) { [weak self] in
            // Note: getDiagnostics is @MainActor, so we call it on main actor
            let diagnostics = await MainActor.run {
                return diagnosticsService.getDiagnostics(
                    for: fileURLCopy,
                    fileContent: contentCopy
                )
            }
            // FIX: Capture self weakly and ensure main actor isolation
            await MainActor.run { [weak self] in
                self?.currentDiagnostics = diagnostics
            }
        }
    }
    
    func updateSelection(_ text: String, position: Int) {
        editorState.selectedText = text
        editorState.cursorPosition = position
    }
    
    func saveCurrentDocument() {
        guard let document = editorState.activeDocument else { return }
        
        if let filePath = document.filePath {
            // Save existing document
            do {
                try document.content.write(to: filePath, atomically: true, encoding: .utf8)
                if let index = editorState.documents.firstIndex(where: { $0.id == document.id }) {
                    editorState.documents[index].isModified = false
                }
            } catch {
                print("Failed to save file: \(error)")
            }
        } else {
            // Show save dialog for new document
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.text]
            if panel.runModal() == .OK {
                if let url = panel.url {
                    do {
                        try document.content.write(to: url, atomically: true, encoding: .utf8)
                        // Update document with new path
                        if let index = editorState.documents.firstIndex(where: { $0.id == document.id }) {
                            editorState.documents[index].filePath = url
                            editorState.documents[index].isModified = false
                        }
                    } catch {
                        print("Failed to save file: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - File Tree Management

    /// Refresh the file tree view
    private var refreshDebounceTask: Task<Void, Never>?
    
    func refreshFileTree() {
        // Cancel any pending refresh
        refreshDebounceTask?.cancel()
        
        // Debounce refresh to avoid excessive updates
        refreshDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second debounce
            guard !Task.isCancelled else { return }
            fileTreeRefreshTrigger.toggle()
        }
    }

    // MARK: - Context for AI
    
    func getContextForAI(query: String? = nil) async -> String? {
        // Use new Cursor-style context ranking with token budget optimization
        let rankingService = ContextRankingService.shared
        
        let activeFile = editorState.activeDocument?.filePath
        let selectedRange = editorState.selectedText.isEmpty ? nil : editorState.selectedText
        let diagnostics: [String]? = nil // TODO: Integrate with diagnostics system
        
        // Start speculative context building if not already done
        if let activeFile = activeFile {
            Task {
                LatencyOptimizer.shared.startSpeculativeContext(
                    activeFile: activeFile,
                    selectedText: selectedRange,
                    projectURL: rootFolderURL,
                    query: query
                )
            }
        }
        
        // Try to use speculative context first
        if let speculative = LatencyOptimizer.shared.getSpeculativeContext() {
            return speculative
        }
        
        let rankedContext = await rankingService.buildContext(
            activeFile: activeFile,
            selectedRange: selectedRange,
            diagnostics: diagnostics,
            projectURL: rootFolderURL,
            query: query,
            tokenLimit: 8000
        )
        
        // Add codebase overview if indexed
        var context = ""
        let indexService = CodebaseIndexService.shared
        if indexService.totalSymbolCount > 0 {
            context += indexService.generateCodebaseOverview()
            context += "\n\n"
        }
        
        context += rankedContext
        
        // Check if this is a text replacement request (e.g., "change X to Y", "replace X with Y")
        let lowercasedQuery = query?.lowercased() ?? ""
        let isTextReplacement = (lowercasedQuery.contains("change") || 
                                 lowercasedQuery.contains("replace") || 
                                 lowercasedQuery.contains("rename")) &&
                                (lowercasedQuery.contains("to") || lowercasedQuery.contains("with"))
        
        // If text replacement, search all files for the text to replace
        if isTextReplacement, let projectURL = rootFolderURL, let query = query {
            // Extract the text to search for (the first word/phrase after "change"/"replace")
            let words = query.components(separatedBy: .whitespaces)
            var searchText: String? = nil
            if let changeIndex = words.firstIndex(where: { $0.lowercased() == "change" || $0.lowercased() == "replace" || $0.lowercased() == "rename" }),
               changeIndex + 1 < words.count {
                // Get the text after "change/replace/rename"
                let remainingWords = Array(words[(changeIndex + 1)...])
                if let toIndex = remainingWords.firstIndex(where: { $0.lowercased() == "to" || $0.lowercased() == "with" }),
                   toIndex > 0 {
                    searchText = remainingWords[0..<toIndex].joined(separator: " ")
                } else {
                    // No "to"/"with" found, use first word after change/replace
                    searchText = remainingWords.first
                }
            }
            
            if let searchText = searchText, !searchText.isEmpty {
                // Search all files for this text
                let matchingFiles = searchForText(searchText, in: projectURL)
                if !matchingFiles.isEmpty {
                    context += "--- FILES CONTAINING '\(searchText)' (MODIFY THESE FILES) ---\n"
                    context += "**IMPORTANT: The text '\(searchText)' appears in the following files. Modify ALL of them, prioritizing HTML files for text content.\n\n"
                    for (fileURL, occurrences) in matchingFiles {
                        if let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                            let fileName = fileURL.lastPathComponent
                            let isHTML = fileName.hasSuffix(".html") || fileName.hasSuffix(".htm")
                            let priority = isHTML ? "HIGH PRIORITY" : "CHECK IF NEEDED"
                            context += "\n--- \(fileName) (\(priority) - \(occurrences) occurrence(s)) ---\n"
                            context += fileContent
                            context += "\n"
                        }
                    }
                    context += "\n"
                }
            }
        }
        
        // Check if this is a website modification request
        let isWebsiteModification = (lowercasedQuery.contains("upgrade") || 
                                     lowercasedQuery.contains("modify") || 
                                     lowercasedQuery.contains("improve") ||
                                     lowercasedQuery.contains("update")) &&
                                    (lowercasedQuery.contains("website") || 
                                     lowercasedQuery.contains("site") ||
                                     lowercasedQuery.contains("web page"))
        
        // If website modification, automatically include all website files
        if isWebsiteModification, let projectURL = rootFolderURL {
            context += "--- EXISTING WEBSITE FILES (PRESERVE ALL CODE FROM THESE) ---\n"
            let websiteFiles = ["index.html", "styles.css", "script.js", "main.html", "style.css", "app.js", "main.js"]
            for fileName in websiteFiles {
                let fileURL = projectURL.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                    context += "\n--- \(fileName) (EXISTING - PRESERVE ALL CODE) ---\n"
                    context += fileContent
                    context += "\n"
                }
            }
            context += "\n"
        }
        
        // Add relevant files from codebase based on query
        if let query = query, !query.isEmpty, rootFolderURL != nil {
            let relevantFiles = indexService.getRelevantFiles(for: query, limit: 5)
            if !relevantFiles.isEmpty {
                context += "--- Relevant Files from Codebase ---\n"
                for indexedFile in relevantFiles {
                    let fileURL = URL(fileURLWithPath: indexedFile.path)
                    if FileManager.default.fileExists(atPath: fileURL.path),
                       let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                        context += "\n--- \(indexedFile.relativePath) ---\n"
                        context += fileContent
                        context += "\n"
                    }
                }
                context += "\n"
            }
        }
        
        // Add active file
        if let document = editorState.activeDocument {
            let fileName = document.filePath?.lastPathComponent ?? "Untitled"
            context += "--- Current File: \(fileName) ---\n"
            context += document.content
            context += "\n\n"
        }
        
        // Add selected text if any
        if !editorState.selectedText.isEmpty {
            context += "--- Selected Code ---\n"
            context += editorState.selectedText
            context += "\n\n"
        }
        
        // Add related files if enabled
        if includeRelatedFilesInContext,
           let document = editorState.activeDocument,
           let filePath = document.filePath,
           let projectURL = rootFolderURL {
            let relatedFiles = FileDependencyService.shared.findRelatedFiles(
                for: filePath,
                in: projectURL
            )
            
            if !relatedFiles.isEmpty {
                context += "--- Related Files ---\n"
                for fileURL in relatedFiles.prefix(5) {
                    if let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                        context += "\n--- \(fileURL.lastPathComponent) ---\n"
                        context += fileContent
                        context += "\n"
                    }
                }
            }
        }
        
        // If no active file but we have a project, include key files
        if editorState.activeDocument == nil,
           rootFolderURL != nil,
           indexService.totalSymbolCount > 0 {
            let keyFiles = indexService.getKeyFiles(limit: 3)
            
            if !keyFiles.isEmpty {
                context += "--- Key Project Files ---\n"
                for indexedFile in keyFiles {
                    let fileURL = URL(fileURLWithPath: indexedFile.path)
                    if FileManager.default.fileExists(atPath: fileURL.path),
                       let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                        context += "\n--- \(indexedFile.relativePath) ---\n"
                        context += fileContent
                        context += "\n"
                    }
                }
                context += "\n"
            }
        }
        
        return context.isEmpty ? nil : context
    }
    
    /// Search for text across all files in the project
    private func searchForText(_ text: String, in projectURL: URL) -> [(URL, Int)] {
        var matchingFiles: [(URL, Int)] = []
        let searchTextLower = text.lowercased()
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return matchingFiles
        }
        
        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath,
                  let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            
            // Count occurrences (case-insensitive)
            let contentLower = content.lowercased()
            let occurrences = contentLower.components(separatedBy: searchTextLower).count - 1
            
            if occurrences > 0 {
                matchingFiles.append((fileURL, occurrences))
            }
        }
        
        // Sort by: HTML files first, then by number of occurrences
        matchingFiles.sort { file1, file2 in
            let isHTML1 = file1.0.lastPathComponent.hasSuffix(".html") || file1.0.lastPathComponent.hasSuffix(".htm")
            let isHTML2 = file2.0.lastPathComponent.hasSuffix(".html") || file2.0.lastPathComponent.hasSuffix(".htm")
            
            if isHTML1 && !isHTML2 {
                return true
            } else if !isHTML1 && isHTML2 {
                return false
            } else {
                return file1.1 > file2.1 // More occurrences first
            }
        }
        
        return matchingFiles
    }
    
    // MARK: - Language Detection
    
    private func detectLanguage(from extension: String) -> String {
        switch `extension`.lowercased() {
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
        default: return "text"
        }
    }
    
    // MARK: - Refactoring / Rename Integration
    
    /// Trigger the Level 3 Semantic Rename
    /// Uses SourceKit-LSP with "Dirty Buffer" support (analyzing unsaved text)
    @MainActor
    func performRename(at cursorOffset: Int, to newName: String) async {
        // 1. Get the Active Document (The "Dirty Buffer")
        guard let document = editorState.activeDocument,
              let fileURL = document.filePath else {
            self.renameErrorMessage = "No active file to rename."
            return
        }
        
        self.isRenaming = true
        self.renameErrorMessage = nil
        
        defer { self.isRenaming = false }
        
        do {
            // 2. Resolve the symbol at the cursor
            // This checks what specific variable/function the user clicked on
            guard let symbol = RenameRefactorService.shared.resolveSymbol(
                at: cursorOffset,
                in: fileURL
            ) else {
                self.renameErrorMessage = "No symbol found at cursor."
                return
            }
            
            print("🔍 Resolving symbol: \(symbol.name)")
            
            // 3. Execute the Rename
            // CRITICAL: We pass 'document.content' (RAM) so LSP sees unsaved changes.
            // If we didn't pass this, LSP would read the old file from disk.
            let edits = try await RenameRefactorService.shared.rename(
                symbol: symbol,
                to: newName,
                in: getProjectRootURL(),
                currentContent: document.content // <--- THE KEY TO BEATING CURSOR
            )
            
            // 4. Apply the Edits
            applyEditsToWorkspace(edits)
            print("✅ Rename success: \(edits.count) changes applied.")
            
        } catch {
            print("❌ Rename failed: \(error.localizedDescription)")
            self.renameErrorMessage = "Rename failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Rename Helpers
    
    /// Returns the project root, or falls back to the file's directory
    private func getProjectRootURL() -> URL {
        return rootFolderURL ?? 
               editorState.activeDocument?.filePath?.deletingLastPathComponent() ?? 
               URL(fileURLWithPath: "/")
    }
    
    /// Applies edits to both Open Tabs (RAM) and Closed Files (Disk)
    private func applyEditsToWorkspace(_ edits: [Edit]) {
        for edit in edits {
            let editURL = URL(fileURLWithPath: edit.file)
            
            // Check if this file is currently open in a tab
            if let index = editorState.documents.firstIndex(where: { 
                guard let docPath = $0.filePath else { return false }
                return docPath.standardized.path == editURL.standardized.path
            }) {
                // CASE A: File is OPEN. Update the RAM buffer directly.
                // This updates the UI immediately without needing a reload.
                let newContent = applyEditToString(editorState.documents[index].content, edit: edit)
                
                // Since Document is a class, we can mutate directly
                editorState.documents[index].content = newContent
                editorState.documents[index].isModified = true // Mark as dirty so user can save later
                
            } else {
                // CASE B: File is CLOSED. Write directly to disk.
                // Using JSONEditSchemaService to apply the edit safely.
                if let projectURL = rootFolderURL {
                    try? JSONEditSchemaService.shared.apply(edit: edit, in: projectURL)
                } else {
                    // Fallback: Write directly if no project URL
                    let editURL = URL(fileURLWithPath: edit.file)
                    if let content = edit.content.first {
                        try? content.write(to: editURL, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
    }
    
    /// Applies a specific text change to a string content
    private func applyEditToString(_ source: String, edit: Edit) -> String {
        guard let range = edit.range else {
            // If no range specified, append content
            return source + "\n" + edit.content.joined(separator: "\n")
        }
        
        var lines = source.components(separatedBy: .newlines)
        
        // Safety check for line ranges
        let startLine = max(0, range.startLine)
        let endLine = min(lines.count, range.endLine)
        
        guard startLine <= endLine else { return source }
        
        // Replace the lines
        lines.replaceSubrange(startLine..<endLine, with: edit.content)
        
        return lines.joined(separator: "\n")
    }
}
