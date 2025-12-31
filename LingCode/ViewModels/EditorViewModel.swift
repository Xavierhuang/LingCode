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
        // Resolve symlinks and standardize the URL
        let resolvedURL = (try? url.resolvingSymlinksInPath()) ?? url
        let standardizedURL = URL(fileURLWithPath: resolvedURL.path)

        // Check if file is already open (compare by path to handle URL variations)
        if let existingDocument = editorState.documents.first(where: { doc in
            guard let docPath = doc.filePath else { return false }
            return docPath.path == standardizedURL.path
        }) {
            // File already open - update it if we have new content with original for highlighting
            print("📄 File already open, activating: \(standardizedURL.path)")

            if let original = originalContent {
                // Read current content from disk
                if let diskContent = try? String(contentsOf: standardizedURL, encoding: .utf8) {
                    existingDocument.content = diskContent
                    existingDocument.markAsAIGenerated(originalContent: original)
                    print("🎨 Applied AI change highlighting to open file")
                }
            }

            editorState.setActiveDocument(existingDocument.id)
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
                print("🎨 Applied AI change highlighting to new document")
            }

            editorState.addDocument(document)
            print("✅ Opened file: \(standardizedURL.path)")
        } catch {
            print("❌ Failed to open file: \(error.localizedDescription)")
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
    func refreshFileTree() {
        fileTreeRefreshTrigger.toggle()
    }

    // MARK: - Context for AI
    
    func getContextForAI(query: String? = nil) -> String? {
        var context = ""
        let indexService = CodebaseIndexService.shared
        
        // Add codebase overview if indexed
        if indexService.totalSymbolCount > 0 {
            context += indexService.generateCodebaseOverview()
            context += "\n\n"
        }
        
        // Add relevant files from codebase based on query
        if let query = query, !query.isEmpty, let projectURL = rootFolderURL {
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
           let projectURL = rootFolderURL,
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
