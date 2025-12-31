//
//  AutocompleteService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct AutocompleteSuggestion {
    let text: String
    let range: NSRange
    let displayText: String
}

class AutocompleteService {
    static let shared = AutocompleteService()
    
    private init() {}
    
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
            AutocompleteSuggestion(
                text: keyword,
                range: NSRange(location: 0, length: 0),
                displayText: keyword
            )
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
        
        AIService.shared.sendMessage(
            prompt,
            context: context,
            onResponse: { response in
                let suggestions = response
                    .components(separatedBy: "\n")
                    .prefix(3)
                    .map { line in
                        AutocompleteSuggestion(
                            text: line.trimmingCharacters(in: .whitespaces),
                            range: NSRange(location: 0, length: 0),
                            displayText: line.trimmingCharacters(in: .whitespaces)
                        )
                    }
                completion(Array(suggestions))
            },
            onError: { _ in
                completion([])
            }
        )
    }
}

