//
//  InlineSuggestionView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import Combine

struct InlineSuggestion {
    let id: UUID
    let text: String
    let insertPosition: Int
    let source: SuggestionSource
    
    enum SuggestionSource {
        case ai
        case snippet
        case history
    }
    
    init(id: UUID = UUID(), text: String, insertPosition: Int, source: SuggestionSource = .ai) {
        self.id = id
        self.text = text
        self.insertPosition = insertPosition
        self.source = source
    }
}

class InlineSuggestionService: ObservableObject {
    static let shared = InlineSuggestionService()
    
    @Published var currentSuggestion: InlineSuggestion?
    @Published var isLoading: Bool = false
    
    private var debounceTimer: Timer?
    private let aiService: AIProviderProtocol = ServiceContainer.shared.ai
    
    private init() {}
    
    func requestSuggestion(
        for text: String,
        at position: Int,
        language: String?,
        context: String?
    ) {
        // Debounce requests
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.fetchSuggestion(for: text, at: position, language: language, context: context)
        }
    }
    
    func cancelSuggestion() {
        debounceTimer?.invalidate()
        currentSuggestion = nil
        isLoading = false
    }
    
    func acceptSuggestion() -> String? {
        defer { currentSuggestion = nil }
        return currentSuggestion?.text
    }
    
    private func fetchSuggestion(
        for text: String,
        at position: Int,
        language: String?,
        context: String?
    ) {
        guard !text.isEmpty else {
            currentSuggestion = nil
            return
        }
        
        isLoading = true
        
        let beforeCursor = String(text.prefix(position))
        let lines = beforeCursor.components(separatedBy: .newlines)
        let currentLine = lines.last ?? ""
        
        // Don't suggest on empty lines or comments
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
            isLoading = false
            return
        }
        
        let prompt = """
        Complete this \(language ?? "code"). Return ONLY the completion text, nothing else. No explanations.
        
        Current code:
        \(beforeCursor.suffix(500))
        
        Complete the current line or add the next logical line.
        """
        
        Task { @MainActor in
            do {
                let response = try await aiService.sendMessage(prompt, context: context, images: [])
                
                isLoading = false
                
                // Clean up the response
                var suggestion = response
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```\(language ?? "")", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Limit suggestion length
                if suggestion.count > 200 {
                    if let firstNewline = suggestion.firstIndex(of: "\n") {
                        suggestion = String(suggestion[..<firstNewline])
                    } else {
                        suggestion = String(suggestion.prefix(200))
                    }
                }
                
                if !suggestion.isEmpty {
                    currentSuggestion = InlineSuggestion(
                        text: suggestion,
                        insertPosition: position,
                        source: .ai
                    )
                }
            } catch {
                isLoading = false
                currentSuggestion = nil
            }
        }
    }
}

struct GhostTextView: View {
    let suggestion: InlineSuggestion?
    let fontSize: CGFloat
    let fontName: String
    
    var body: some View {
        if let suggestion = suggestion {
            Text(suggestion.text)
                .font(.custom(fontName, size: fontSize))
                .foregroundColor(.secondary.opacity(0.5))
                .italic()
        }
    }
}

