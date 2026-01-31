//
//  ContextMentionView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

enum MentionType: String, CaseIterable {
    case file = "@file"
    case folder = "@folder"
    case codebase = "@codebase"
    case selection = "@selection"
    case terminal = "@terminal"
    case web = "@web"
    case docs = "@docs"
    case notepad = "@notepad"
    
    var icon: String {
        switch self {
        case .file: return "doc"
        case .folder: return "folder"
        case .codebase: return "doc.text.magnifyingglass"
        case .selection: return "selection.pin.in.out"
        case .terminal: return "terminal"
        case .web: return "globe"
        case .docs: return "book"
        case .notepad: return "note.text"
        }
    }
    
    var description: String {
        switch self {
        case .file: return "Include specific file"
        case .folder: return "Include folder contents"
        case .codebase: return "Search entire codebase"
        case .selection: return "Include selected code"
        case .terminal: return "Include terminal output"
        case .web: return "Search the web"
        case .docs: return "Fetch documentation"
        case .notepad: return "Include notepad content"
        }
    }
}

struct Mention: Identifiable {
    let id = UUID()
    let type: MentionType
    let value: String
    let displayName: String
}

class MentionParser {
    static let shared = MentionParser()
    
    private init() {}
    
    func parseMentions(from text: String) -> [Mention] {
        var mentions: [Mention] = []
        
        // Pattern: @type:value or @type
        let pattern = #"@(file|folder|codebase|selection|terminal|web|docs|notepad)(?::([^\s]+))?"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return mentions
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            if match.numberOfRanges >= 2 {
                let typeRange = Range(match.range(at: 1), in: text)!
                let typeString = String(text[typeRange])
                
                var value = ""
                var displayName = "@\(typeString)"
                
                if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
                    let valueRange = Range(match.range(at: 2), in: text)!
                    value = String(text[valueRange])
                    displayName = "@\(typeString):\(value)"
                }
                
                if let type = MentionType(rawValue: "@\(typeString)") {
                    mentions.append(Mention(type: type, value: value, displayName: displayName))
                }
            }
        }
        
        return mentions
    }
    
    func removeMentions(from text: String) -> String {
        let pattern = #"@(file|folder|codebase|selection|terminal|web|docs|notepad)(?::[^\s]+)?\s*"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    
    func buildContextFromMentions(
        _ mentions: [Mention],
        projectURL: URL?,
        selectedText: String?,
        terminalOutput: String?
    ) -> String {
        var context = ""
        
        for mention in mentions {
            switch mention.type {
            case .file:
                if let projectURL = projectURL, !mention.value.isEmpty {
                    let fileURL = projectURL.appendingPathComponent(mention.value)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        context += "\n\n--- File: \(mention.value) ---\n\(content)"
                    }
                }
                
            case .folder:
                if let projectURL = projectURL {
                    let folderURL = mention.value.isEmpty ? projectURL : projectURL.appendingPathComponent(mention.value)
                    if let files = getFilesInFolder(folderURL) {
                        context += "\n\n--- Folder: \(mention.value.isEmpty ? "root" : mention.value) ---\n"
                        for file in files.prefix(10) {
                            if let content = try? String(contentsOf: file, encoding: .utf8) {
                                context += "\n--- \(file.lastPathComponent) ---\n\(String(content.prefix(1000)))"
                            }
                        }
                    }
                }
                
            case .codebase:
                if let projectURL = projectURL {
                    // Use CodebaseIndexService for smart codebase search
                    let indexService = CodebaseIndexService.shared
                    
                    // Index if not already indexed
                    if indexService.lastIndexDate == nil {
                        indexService.indexProject(at: projectURL) { _, _ in }
                    }
                    
                    // Get relevant files and symbols
                    let relevantFiles = indexService.getRelevantFiles(for: mention.value, limit: 10)
                    let matchingSymbols = indexService.findSymbol(named: mention.value)
                    
                    var codebaseContext = "\n\n--- Codebase Context: \(mention.value) ---\n"
                    
                    // Add matching symbols
                    if !matchingSymbols.isEmpty {
                        codebaseContext += "\n### Matching Symbols:\n"
                        for symbol in matchingSymbols.prefix(5) {
                            codebaseContext += "- \(symbol.kind.rawValue) \(symbol.name) in \(symbol.filePath):\(symbol.line)\n"
                            if let sig = symbol.signature {
                                codebaseContext += "  \(sig)\n"
                            }
                        }
                    }
                    
                    // Add relevant files
                    if !relevantFiles.isEmpty {
                        codebaseContext += "\n### Relevant Files:\n"
                        for file in relevantFiles.prefix(5) {
                            codebaseContext += "\n\(file.relativePath):\n"
                            if let summary = file.summary {
                                codebaseContext += "Summary: \(summary)\n"
                            }
                            codebaseContext += "Symbols: \(file.symbols.count), Lines: \(file.lineCount)\n"
                            
                            // Add key symbols
                            let keySymbols = file.symbols.prefix(3)
                            if !keySymbols.isEmpty {
                                codebaseContext += "Key symbols: \(keySymbols.map { $0.name }.joined(separator: ", "))\n"
                            }
                        }
                    }
                    
                    context += codebaseContext
                }
                
            case .selection:
                if let selected = selectedText, !selected.isEmpty {
                    context += "\n\n--- Selected Code ---\n\(selected)"
                }
                
            case .terminal:
                if let terminal = terminalOutput {
                    context += "\n\n--- Terminal Output ---\n\(terminal)"
                }
                
            case .web:
                // Web search handled by WebSearchService
                if !mention.value.isEmpty {
                    context += "\n\n[Web search for: \(mention.value)]"
                }
                
            case .docs:
                // Documentation fetching - sync version just adds placeholder
                // Use buildContextFromMentionsAsync for actual fetching
                if !mention.value.isEmpty {
                    context += "\n\n[Documentation: \(mention.value) - use async method for full content]"
                }
                
            case .notepad:
                // Include notepad content
                let notepadContext = NotepadService.shared.buildContext(notepadName: mention.value.isEmpty ? nil : mention.value)
                context += "\n\n" + notepadContext
            }
        }
        
        return context
    }
    
    /// Async version that fetches @docs and @web content
    func buildContextFromMentionsAsync(
        _ mentions: [Mention],
        projectURL: URL?,
        selectedText: String?,
        terminalOutput: String?
    ) async -> String {
        var context = ""
        
        for mention in mentions {
            switch mention.type {
            case .file:
                if let projectURL = projectURL, !mention.value.isEmpty {
                    let fileURL = projectURL.appendingPathComponent(mention.value)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        context += "\n\n--- File: \(mention.value) ---\n\(content)"
                    }
                }
                
            case .folder:
                if let projectURL = projectURL {
                    let folderURL = mention.value.isEmpty ? projectURL : projectURL.appendingPathComponent(mention.value)
                    if let files = getFilesInFolder(folderURL) {
                        context += "\n\n--- Folder: \(mention.value.isEmpty ? "root" : mention.value) ---\n"
                        for file in files.prefix(10) {
                            if let content = try? String(contentsOf: file, encoding: .utf8) {
                                context += "\n--- \(file.lastPathComponent) ---\n\(String(content.prefix(1000)))"
                            }
                        }
                    }
                }
                
            case .codebase:
                if let projectURL = projectURL {
                    let indexService = CodebaseIndexService.shared
                    if indexService.lastIndexDate == nil {
                        indexService.indexProject(at: projectURL) { _, _ in }
                    }
                    
                    let relevantFiles = indexService.getRelevantFiles(for: mention.value, limit: 10)
                    let matchingSymbols = indexService.findSymbol(named: mention.value)
                    
                    var codebaseContext = "\n\n--- Codebase Context: \(mention.value) ---\n"
                    
                    if !matchingSymbols.isEmpty {
                        codebaseContext += "\n### Matching Symbols:\n"
                        for symbol in matchingSymbols.prefix(5) {
                            codebaseContext += "- \(symbol.kind.rawValue) \(symbol.name) in \(symbol.filePath):\(symbol.line)\n"
                            if let sig = symbol.signature {
                                codebaseContext += "  \(sig)\n"
                            }
                        }
                    }
                    
                    if !relevantFiles.isEmpty {
                        codebaseContext += "\n### Relevant Files:\n"
                        for file in relevantFiles.prefix(5) {
                            codebaseContext += "\n\(file.relativePath):\n"
                            if let summary = file.summary {
                                codebaseContext += "Summary: \(summary)\n"
                            }
                            codebaseContext += "Symbols: \(file.symbols.count), Lines: \(file.lineCount)\n"
                            
                            let keySymbols = file.symbols.prefix(3)
                            if !keySymbols.isEmpty {
                                codebaseContext += "Key symbols: \(keySymbols.map { $0.name }.joined(separator: ", "))\n"
                            }
                        }
                    }
                    
                    context += codebaseContext
                }
                
            case .selection:
                if let selected = selectedText, !selected.isEmpty {
                    context += "\n\n--- Selected Code ---\n\(selected)"
                }
                
            case .terminal:
                if let terminal = terminalOutput {
                    context += "\n\n--- Terminal Output ---\n\(terminal)"
                }
                
            case .web:
                // Fetch web search results using continuation
                if !mention.value.isEmpty {
                    let results = await withCheckedContinuation { continuation in
                        WebSearchService.shared.search(query: mention.value) { results in
                            continuation.resume(returning: results)
                        }
                    }
                    
                    if !results.isEmpty {
                        var webContext = "\n\n--- Web Search: \(mention.value) ---\n"
                        for result in results.prefix(5) {
                            webContext += "\n### \(result.title)\n"
                            webContext += "URL: \(result.url)\n"
                            webContext += "\(result.snippet)\n"
                        }
                        context += webContext
                    } else {
                        context += "\n\n[No web results found for: \(mention.value)]"
                    }
                }
                
            case .docs:
                // Fetch documentation using DocsService
                if !mention.value.isEmpty {
                    do {
                        let docsResult = try await fetchDocumentation(query: mention.value)
                        context += "\n\n" + docsResult
                    } catch {
                        context += "\n\n[Documentation fetch failed for '\(mention.value)': \(error.localizedDescription)]"
                    }
                }
                
            case .notepad:
                let notepadContext = NotepadService.shared.buildContext(notepadName: mention.value.isEmpty ? nil : mention.value)
                context += "\n\n" + notepadContext
            }
        }
        
        return context
    }
    
    private func getFilesInFolder(_ url: URL) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if !fileURL.hasDirectoryPath {
                files.append(fileURL)
            }
            if files.count >= 20 {
                break
            }
        }
        
        return files
    }
    
    private func searchCodebase(_ projectURL: URL, query: String) -> String {
        // Use semantic search service
        var results = ""
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }
        
        let keywords = query.lowercased().components(separatedBy: " ")
        
        for case let fileURL as URL in enumerator {
            if fileURL.hasDirectoryPath { continue }
            
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let lowerContent = content.lowercased()
                var matches = false
                
                for keyword in keywords {
                    if lowerContent.contains(keyword) {
                        matches = true
                        break
                    }
                }
                
                if matches {
                    results += "\n--- \(fileURL.lastPathComponent) ---\n\(String(content.prefix(500)))\n"
                    if results.count > 5000 {
                        break
                    }
                }
            }
        }
        
        return results
    }
    
    /// Fetch documentation from various sources
    private func fetchDocumentation(query: String) async throws -> String {
        // Try to fetch from URL if it looks like a URL
        if query.hasPrefix("http://") || query.hasPrefix("https://") {
            return try await fetchDocumentationFromURL(query)
        }
        
        // Try GitHub README format (owner/repo)
        if query.contains("/") && !query.contains(" ") {
            return try await fetchGitHubReadme(query)
        }
        
        // Default: search DuckDuckGo for documentation
        return await searchForDocumentation(query)
    }
    
    private func fetchDocumentationFromURL(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "DocsError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DocsError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not decode content"])
        }
        
        // Strip HTML tags for basic readability
        let stripped = content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return "## Documentation from \(urlString)\n\n\(String(stripped.prefix(5000)))"
    }
    
    private func fetchGitHubReadme(_ repo: String) async throws -> String {
        let readmeURL = "https://raw.githubusercontent.com/\(repo)/main/README.md"
        guard let url = URL(string: readmeURL) else {
            throw NSError(domain: "DocsError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid repo format"])
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                return "## Documentation: \(repo)\n\n\(String(content.prefix(5000)))"
            }
        } catch {
            // Try master branch
            let masterURL = "https://raw.githubusercontent.com/\(repo)/master/README.md"
            if let url = URL(string: masterURL) {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let content = String(data: data, encoding: .utf8) {
                    return "## Documentation: \(repo)\n\n\(String(content.prefix(5000)))"
                }
            }
        }
        
        throw NSError(domain: "DocsError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not fetch README"])
    }
    
    private func searchForDocumentation(_ query: String) async -> String {
        let results = await withCheckedContinuation { continuation in
            WebSearchService.shared.search(query: "\(query) documentation") { results in
                continuation.resume(returning: results)
            }
        }
        
        if let first = results.first {
            return "## Documentation for \(query)\n\nSource: \(first.url)\n\n\(first.snippet)"
        }
        
        return "[No documentation found for: \(query)]"
    }
}

struct MentionPopupView: View {
    @Binding var isVisible: Bool
    let onSelect: (MentionType) -> Void
    var editorViewModel: EditorViewModel?
    var onFileSelected: ((String) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MentionType.allCases, id: \.self) { type in
                Button(action: {
                    if type == .file, let editorViewModel = editorViewModel, let onFileSelected = onFileSelected {
                        // Show file picker for @file
                        // This will be handled by parent view
                        onSelect(type)
                    } else {
                        onSelect(type)
                        isVisible = false
                    }
                }) {
                    HStack {
                        Image(systemName: type.icon)
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(.headline)
                            Text(type.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if type == .file {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
        .frame(width: 300)
    }
}

struct MentionBadgeView: View {
    let mention: Mention
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mention.type.icon)
                .font(.caption)
            Text(mention.displayName)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.2))
        .cornerRadius(4)
    }
}

