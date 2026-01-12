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
    
    // AI
    let aiViewModel = AIViewModel()
    
    // Project - @Published so UI updates when folder changes
    @Published var rootFolderURL: URL? {
        didSet {
            // Index codebase when project opens
            if let url = rootFolderURL {
                print("rootFolderURL set to: \(url.path)")
                CodebaseIndexService.shared.indexProject(at: url) { _, _ in }
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
    
    func getContextForAI(query: String? = nil) -> String? {
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
        
        let rankedContext = rankingService.buildContext(
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
        
        // Check if this is a website modification request
        let lowercasedQuery = query?.lowercased() ?? ""
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
}
