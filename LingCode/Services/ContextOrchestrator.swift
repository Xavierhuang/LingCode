//
//  ContextOrchestrator.swift
//  LingCode
//
//  Single orchestrator for context lifecycle: Speculate (Background) -> Track (Live) -> Rank (on Request).
//  Replaces ContextTrackingService, SpeculativeContextService, and speculative parts of LatencyOptimizer.
//

import Foundation
import Combine

/// Context source for tracking what is included in AI requests
struct ContextSource: Identifiable, Hashable {
    let id = UUID()
    let type: ContextType
    let name: String
    let path: String?
    let relevanceScore: Double?
    let tokenCount: Int?
    let timestamp: Date
    
    enum ContextType: String, CaseIterable {
        case activeFile = "Active File"
        case selectedText = "Selection"
        case codebaseSearch = "Codebase Search"
        case fileMention = "File Mention"
        case folderMention = "Folder Mention"
        case terminalOutput = "Terminal Output"
        case webSearch = "Web Search"
        case diagnostics = "Diagnostics"
        case gitDiff = "Git Diff"
        case workspaceRules = "Workspace Rules"
        case codebaseOverview = "Codebase Overview"
    }
}

/// Single orchestrator: Speculate (background) -> Track (live) -> Rank (on request)
@MainActor
final class ContextOrchestrator: ObservableObject {
    static let shared = ContextOrchestrator()
    
    // MARK: - Track (Live) - from ContextTrackingService
    @Published private(set) var currentContextSources: [ContextSource] = []
    @Published private(set) var contextHistory: [ContextSource] = []
    @Published private(set) var totalTokenUsage: Int = 0
    @Published private(set) var contextBuildTime: TimeInterval = 0
    
    // MARK: - Speculate (Background) - from SpeculativeContextService + LatencyOptimizer
    @Published private(set) var preparedContext: String?
    @Published private(set) var isPreparing: Bool = false
    
    private var speculativeContext: String?
    private var speculativeContextTask: Task<Void, Never>?
    private var speculativeContextStartTime: Date?
    private var lastSpeculativeQuery: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let textSubject = PassthroughSubject<String, Never>()
    
    private init() {
        setupSpeculativePipeline()
    }
    
    // MARK: - Speculate (Background)
    
    /// Call when user types in chat/editor to trigger background context prep
    func onUserTyping(text: String) {
        textSubject.send(text)
    }
    
    /// Start building context speculatively (e.g. on pause, cursor stop, selection change)
    func startSpeculativeContext(
        activeFile: URL?,
        selectedText: String?,
        projectURL: URL?,
        query: String?,
        onComplete: (() -> Void)? = nil
    ) {
        speculativeContextTask?.cancel()
        speculativeContextStartTime = Date()
        lastSpeculativeQuery = query ?? ""
        
        let task = Task {
            let context = await ContextRankingService.shared.buildContext(
                activeFile: activeFile,
                selectedRange: selectedText,
                diagnostics: nil,
                projectURL: projectURL,
                query: query ?? "",
                tokenLimit: 8000
            )
            if !Task.isCancelled {
                await MainActor.run {
                    self.speculativeContext = context
                    self.speculativeContextStartTime = nil
                    self.isPreparing = false
                    onComplete?()
                }
            }
        }
        speculativeContextTask = task
    }
    
    /// Prepare context with full editor state (e.g. from AIViewModel)
    func prepareContext(
        query: String,
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?
    ) {
        lastSpeculativeQuery = query
        isPreparing = true
        speculativeContextTask?.cancel()
        
        let task = Task {
            let context = await ContextRankingService.shared.buildContext(
                activeFile: activeFile,
                selectedRange: selectedRange,
                diagnostics: diagnostics,
                projectURL: projectURL,
                query: query,
                tokenLimit: 8000
            )
            if !Task.isCancelled {
                await MainActor.run {
                    self.speculativeContext = context
                    self.preparedContext = context
                    self.isPreparing = false
                }
            }
        }
        speculativeContextTask = task
    }
    
    /// Get speculative context if available (no blocking wait)
    func getSpeculativeContext() -> String? {
        speculativeContext
    }
    
    /// Clear speculative/prepared context (e.g. after use or on send)
    func clearSpeculativeContext() {
        speculativeContext = nil
        preparedContext = nil
        lastSpeculativeQuery = ""
        speculativeContextTask?.cancel()
        speculativeContextTask = nil
    }
    
    private func setupSpeculativePipeline() {
        textSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.global(qos: .userInitiated))
            .removeDuplicates()
            .filter { $0.count > 5 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPreparing = true
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Track (Live)
    
    func trackContext(
        type: ContextSource.ContextType,
        name: String,
        path: String? = nil,
        relevanceScore: Double? = nil,
        tokenCount: Int? = nil
    ) {
        let source = ContextSource(
            type: type,
            name: name,
            path: path,
            relevanceScore: relevanceScore,
            tokenCount: tokenCount,
            timestamp: Date()
        )
        currentContextSources.append(source)
        contextHistory.append(source)
        if let tokens = tokenCount { totalTokenUsage += tokens }
    }
    
    func clearCurrentContext() {
        currentContextSources.removeAll()
    }
    
    func getContextSummary() -> String {
        var summary = "Context Sources:\n"
        for source in currentContextSources {
            summary += "- \(source.type.rawValue): \(source.name)"
            if let path = source.path { summary += " (\(path))" }
            if let score = source.relevanceScore { summary += " [Relevance: \(String(format: "%.1f", score))]" }
            if let tokens = source.tokenCount { summary += " [Tokens: \(tokens)]" }
            summary += "\n"
        }
        return summary
    }
    
    func getTokenUsageByType() -> [ContextSource.ContextType: Int] {
        var usage: [ContextSource.ContextType: Int] = [:]
        for source in currentContextSources {
            if let tokens = source.tokenCount { usage[source.type, default: 0] += tokens }
        }
        return usage
    }
    
    // MARK: - Rank (on Request)
    
    /// Build context: use speculative if query matches, else rank now. Tracks result.
    func buildContext(
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?,
        query: String?,
        tokenLimit: Int = 8000
    ) async -> String {
        let queryNorm = (query ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lastNorm = lastSpeculativeQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !queryNorm.isEmpty, queryNorm == lastNorm, let ready = getSpeculativeContext() {
            clearSpeculativeContext()
            return ready
        }
        let start = Date()
        let context = await ContextRankingService.shared.buildContext(
            activeFile: activeFile,
            selectedRange: selectedRange,
            diagnostics: diagnostics,
            projectURL: projectURL,
            query: query,
            tokenLimit: tokenLimit
        )
        contextBuildTime = Date().timeIntervalSince(start)
        return context
    }
    
    /// Build context with priority streaming (Tier 1 first, then full). Delegates to ranking service.
    func buildContextWithPriority(
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?,
        query: String?,
        tokenLimit: Int = 8000
    ) async -> (initial: String, full: String) {
        await ContextRankingService.shared.buildContextWithPriority(
            activeFile: activeFile,
            selectedRange: selectedRange,
            diagnostics: diagnostics,
            projectURL: projectURL,
            query: query,
            tokenLimit: tokenLimit
        )
    }
    
    // MARK: - Cursor-Style Context (merged from CursorContextBuilder)
    
    /// Build comprehensive Cursor-style context from editor state
    /// Includes: current file, related files, git diff, open files
    func buildCursorStyleContext(
        editorState: EditorState,
        cursorPosition: Int? = nil,
        selectedText: String? = nil,
        projectURL: URL? = nil,
        includeDiagnostics: Bool = true,
        includeGitDiff: Bool = true,
        includeFileGraph: Bool = true
    ) -> String {
        var contextParts: [String] = []
        
        // 1. Current file context
        if let activeDocument = editorState.activeDocument {
            contextParts.append("=== CURRENT FILE ===")
            if let filePath = activeDocument.filePath {
                contextParts.append("File: \(filePath.path)")
            }
            contextParts.append("Language: \(activeDocument.language ?? "unknown")")
            
            if let cursorPos = cursorPosition {
                let lineNumber = activeDocument.content.prefix(cursorPos).components(separatedBy: .newlines).count
                contextParts.append("Cursor: Line \(lineNumber), Column \(cursorPos)")
            }
            
            if let selected = selectedText, !selected.isEmpty {
                contextParts.append("Selected: \(selected.prefix(100))")
            }
            
            contextParts.append("\nFile Content:")
            contextParts.append(activeDocument.content)
            contextParts.append("")
        }
        
        // 2. File graph (related files)
        if includeFileGraph, let filePath = editorState.activeDocument?.filePath {
            let relatedFiles = getRelatedFiles(for: filePath.path)
            if !relatedFiles.isEmpty {
                contextParts.append("=== RELATED FILES ===")
                for file in relatedFiles.prefix(5) {
                    let fileURL = URL(fileURLWithPath: file)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        contextParts.append("File: \(file)")
                        contextParts.append(content)
                        contextParts.append("")
                    }
                }
            }
        }
        
        // 3. Diagnostics placeholder
        if includeDiagnostics {
            // Diagnostics would come from DiagnosticsService in future
            _ = editorState.activeDocument
        }
        
        // 4. Git diff (recent changes)
        if includeGitDiff {
            if let filePath = editorState.activeDocument?.filePath {
                if let diff = GitService.shared.getDiff(for: filePath) {
                    contextParts.append("=== RECENT CHANGES (Git Diff) ===")
                    contextParts.append(diff)
                    contextParts.append("")
                }
            }
            _ = projectURL
        }
        
        // 5. Open files context
        if editorState.documents.count > 1 {
            contextParts.append("=== OTHER OPEN FILES ===")
            for doc in editorState.documents where doc.id != editorState.activeDocument?.id {
                if let filePath = doc.filePath {
                    contextParts.append("File: \(filePath.path)")
                }
                contextParts.append(String(doc.content.prefix(500)) + (doc.content.count > 500 ? "..." : ""))
                contextParts.append("")
            }
        }
        
        return contextParts.joined(separator: "\n")
    }
    
    /// Get related files based on imports/dependencies
    private func getRelatedFiles(for filePath: String) -> [String] {
        guard let fileSummary = CodebaseIndexService.shared.getFileSummary(path: filePath) else {
            return []
        }
        
        var relatedFiles: Set<String> = []
        for symbol in fileSummary.symbols {
            let foundSymbols = CodebaseIndexService.shared.findSymbol(named: symbol.name)
            for foundSymbol in foundSymbols {
                if foundSymbol.filePath != filePath {
                    relatedFiles.insert(foundSymbol.filePath)
                }
            }
        }
        return Array(relatedFiles)
    }
}
