//
//  AutocompleteService.swift
//  LingCode
//
//  LSP-powered IntelliSense autocomplete
//  Uses Language Server Protocol for accurate, type-aware completions
//

import Foundation

struct AutocompleteSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let range: NSRange
    let displayText: String
    let detail: String?
    let documentation: String?
    
    init(from lspItem: LSPCompletionItem, at range: NSRange) {
        self.text = lspItem.insertText ?? lspItem.label
        self.range = range
        self.displayText = lspItem.label
        self.detail = lspItem.detail
        self.documentation = lspItem.documentation
    }
}

class AutocompleteService {
    static let shared = AutocompleteService()
    
    private init() {}
    
    /// Get LSP-powered completions at a position
    func getLSPCompletions(
        at position: LSPPosition,
        in fileURL: URL,
        fileContent: String?,
        projectURL: URL
    ) async -> [AutocompleteSuggestion] {
        do {
            let lspClient = try LanguageServerManager.shared.getServer(for: fileURL, workspaceURL: projectURL)
            let completions = try await lspClient.getCompletions(at: position, in: fileURL, fileContent: fileContent)
            
            // Convert LSP completions to AutocompleteSuggestion
            // Note: Range calculation would need proper line/character to offset conversion
            let range = NSRange(location: 0, length: 0) // Placeholder
            return completions.map { AutocompleteSuggestion(from: $0, at: range) }
        } catch {
            // Fallback to simple token matching
            // Fallback to simple token matching
            return []
        }
    }
    
    /// Helper: Get simple suggestions at LSP position (fallback)
    private func getSuggestions(for text: String, at position: LSPPosition) -> [AutocompleteSuggestion] {
        // Convert LSP position to character offset
        let lines = text.components(separatedBy: .newlines)
        var offset = 0
        for i in 0..<min(position.line, lines.count) {
            offset += lines[i].count + 1 // +1 for newline
        }
        if position.line < lines.count {
            offset += min(position.character, lines[position.line].count)
        }
        
        // Return empty for now - legacy method would provide token-based suggestions
        return []
    }
    
    /// Fallback: Simple token-based suggestions (legacy method)
    func getSuggestions(
        for text: String,
        at position: Int,
        language: String?,
        context: String?,
        completion: @escaping ([AutocompleteSuggestion]) -> Void
    ) {
        // Get text before cursor
        let beforeCursor = String(text.prefix(position))
        
        // Simple keyword-based autocomplete for common languages
        var suggestions: [AutocompleteSuggestion] = []
        
        if let language = language {
            suggestions.append(contentsOf: getLanguageKeywords(for: language, prefix: getCurrentWord(beforeCursor)))
        }
        
        // AI-based suggestions (async)
        if let context = context {
            getAISuggestions(
                prefix: getCurrentWord(beforeCursor),
                context: context,
                language: language
            ) { aiSuggestions in
                suggestions.append(contentsOf: aiSuggestions)
                completion(suggestions)
            }
        } else {
            completion(suggestions)
        }
    }
    
    private func getCurrentWord(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.last ?? ""
    }
    
    private func getLanguageKeywords(for language: String, prefix: String) -> [AutocompleteSuggestion] {
        let keywords: [String: [String]] = [
            "swift": ["func", "var", "let", "class", "struct", "enum", "protocol", "extension", "if", "else", "for", "while", "guard", "return", "import", "public", "private", "internal"],
            "python": ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "import", "from", "return", "yield", "async", "await"],
            "javascript": ["function", "const", "let", "var", "if", "else", "for", "while", "async", "await", "import", "export", "return", "class", "extends"],
            "typescript": ["function", "const", "let", "var", "interface", "type", "class", "if", "else", "for", "while", "async", "await", "import", "export", "return"]
        ]
        
        guard let langKeywords = keywords[language.lowercased()] else { return [] }
        
        let filtered = langKeywords.filter { $0.hasPrefix(prefix.lowercased()) && $0 != prefix }
        return filtered.prefix(5).map { keyword in
            // Create a simple LSP completion item for legacy support
            let lspItem = LSPCompletionItem(
                label: keyword,
                kind: nil,
                detail: nil,
                documentation: nil,
                insertText: keyword,
                textEdit: nil
            )
            return AutocompleteSuggestion(from: lspItem, at: NSRange(location: 0, length: 0))
        }
    }
    
    private func getAISuggestions(
        prefix: String,
        context: String,
        language: String?,
        completion: @escaping ([AutocompleteSuggestion]) -> Void
    ) {
        guard !prefix.isEmpty else {
            completion([])
            return
        }
        
        let prompt = "Complete this code. Only return the completion text, nothing else:\n\n\(context)\n\nComplete: \(prefix)"
        
        Task {
            do {
                let aiService: AIProviderProtocol = ServiceContainer.shared.ai
                let response = try await aiService.sendMessage(prompt, context: context, images: [])
                
                let suggestions = response
                    .components(separatedBy: "\n")
                    .prefix(3)
                    .map { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        let lspItem = LSPCompletionItem(
                            label: trimmed,
                            kind: nil,
                            detail: nil,
                            documentation: nil,
                            insertText: trimmed,
                            textEdit: nil
                        )
                        return AutocompleteSuggestion(from: lspItem, at: NSRange(location: 0, length: 0))
                    }
                completion(Array(suggestions))
            } catch {
                completion([])
            }
        }
    }
}

