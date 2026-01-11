//
//  InlineAutocompleteService.swift
//  LingCode
//
//  Cursor-level inline autocomplete with streaming acceptance and confidence scoring
//

import Foundation

struct InlineAutocompleteSuggestion {
    let text: String
    let confidence: Double
    let tokens: [String]
    var currentTokenIndex: Int = 0
    
    var currentText: String {
        tokens.prefix(currentTokenIndex + 1).joined()
    }
    
    var isComplete: Bool {
        currentTokenIndex >= tokens.count - 1
    }
}

struct AutocompleteContext {
    let fileContent: String
    let cursorPosition: Int
    let last200Lines: String
    let language: String
}

class InlineAutocompleteService {
    static let shared = InlineAutocompleteService()
    
    private var currentSuggestion: InlineAutocompleteSuggestion?
    private var currentTask: Task<Void, Never>?
    private let maxLatency: TimeInterval = 0.15 // 150ms
    
    private init() {}
    
    /// Request autocomplete suggestion
    func requestSuggestion(
        context: AutocompleteContext,
        onSuggestion: @escaping (InlineAutocompleteSuggestion?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // Cancel previous request
        currentTask?.cancel()
        currentTask = nil
        
        let startTime = Date()
        
        currentTask = Task {
            // Build minimal context (last 200 lines only)
            let prompt = buildAutocompletePrompt(context: context)
            
            // Use local model for speed (DeepSeek Coder, StarCoder2, or GPT-4o mini)
            // For now, placeholder - would call actual model
            let suggestion = await generateSuggestion(prompt: prompt, context: context)
            
            // Check latency
            let latency = Date().timeIntervalSince(startTime)
            if latency > maxLatency {
                onCancel()
                return
            }
            
            if !Task.isCancelled {
                onSuggestion(suggestion)
            }
        }
    }
    
    /// Generate suggestion (placeholder - would use actual model)
    private func generateSuggestion(
        prompt: String,
        context: AutocompleteContext
    ) async -> InlineAutocompleteSuggestion? {
        // Placeholder: would call local model or GPT-4o mini
        // For now, return nil (would be implemented with actual model)
        return nil
    }
    
    /// Build minimal autocomplete prompt
    private func buildAutocompletePrompt(context: AutocompleteContext) -> String {
        return """
        You are an IDE autocomplete engine.
        
        Continue the code at the cursor.
        Return ONLY the code to be inserted.
        Do not repeat existing code.
        Do not include explanations.
        
        Code context (last 200 lines):
        \(context.last200Lines)
        
        Cursor position: Line \(context.cursorPosition)
        
        Continue from cursor:
        """
    }
    
    /// Stream tokens and check confidence incrementally
    func acceptToken(
        _ token: String,
        suggestion: inout InlineAutocompleteSuggestion
    ) -> Bool {
        suggestion.currentTokenIndex += 1
        
        // Check confidence
        let confidence = calculateConfidence(suggestion: suggestion)
        suggestion = InlineAutocompleteSuggestion(
            text: suggestion.text,
            confidence: confidence,
            tokens: suggestion.tokens,
            currentTokenIndex: suggestion.currentTokenIndex
        )
        
        // Accept if confidence is high enough
        return confidence >= 0.8
    }
    
    /// Calculate confidence heuristic
    private func calculateConfidence(suggestion: InlineAutocompleteSuggestion) -> Double {
        var confidence: Double = 0.5 // Base confidence
        
        let currentText = suggestion.currentText
        
        // Check balanced brackets
        let openBrackets = currentText.filter { "([{".contains($0) }.count
        let closeBrackets = currentText.filter { ")]}".contains($0) }.count
        if openBrackets == closeBrackets {
            confidence += 0.2
        }
        
        // Check valid AST fragment (simplified)
        if isValidASTFragment(currentText) {
            confidence += 0.2
        }
        
        // Check indentation (if applicable)
        if hasConsistentIndentation(currentText) {
            confidence += 0.1
        }
        
        return min(confidence, 1.0)
    }
    
    private func isValidASTFragment(_ text: String) -> Bool {
        // Simplified check - would use proper AST validation
        // Check for balanced quotes, brackets, etc.
        let quotes = text.filter { "\"'`".contains($0) }.count
        return quotes % 2 == 0
    }
    
    private func hasConsistentIndentation(_ text: String) -> Bool {
        // Simplified check
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 1 else { return true }
        
        let firstIndent = lines[0].prefix(while: { $0 == " " || $0 == "\t" }).count
        for line in lines.dropFirst() {
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if abs(indent - firstIndent) > 4 {
                return false
            }
        }
        return true
    }
    
    /// Cancel current suggestion
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        currentSuggestion = nil
    }
    
    /// Check if should abort (user typed or latency too high)
    func shouldAbort(userTyped: Bool, latency: TimeInterval) -> Bool {
        return userTyped || latency > maxLatency
    }
}

// MARK: - Model Selection for Autocomplete

extension InlineAutocompleteService {
    /// Select best model for autocomplete
    func selectAutocompleteModel() -> String {
        // Priority: Local > Fast Cloud > Standard Cloud
        // DeepSeek Coder (local) - Best
        // StarCoder2 (local) - Lightweight
        // GPT-4o mini (cloud) - Fallback
        
        // For now, return placeholder
        return "local" // Would be "deepseek-coder" or "starcoder2" or "gpt-4o-mini"
    }
}
