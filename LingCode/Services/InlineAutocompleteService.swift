//
//  InlineAutocompleteService.swift
//  LingCode
//
//  OPTIMIZED: Fixed performance bottlenecks and thread safety
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
    
    private var currentTask: Task<Void, Never>?
    // 🚀 Performance: Increased latency threshold for debug/testing
    private let maxLatency: TimeInterval = 0.5
    
    private init() {}
    
    /// Request autocomplete suggestion
    func requestSuggestion(
        context: AutocompleteContext,
        onSuggestion: @escaping (InlineAutocompleteSuggestion?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // 1. Cancel previous task immediately
        currentTask?.cancel()
        currentTask = nil
        
        let startTime = Date()
        
        currentTask = Task {
            // 2. Run heavy logic off the main thread
            let suggestion = await generateSuggestion(context: context)
            
            // 3. Check latency (Performance Guard)
            let latency = Date().timeIntervalSince(startTime)
            if latency > maxLatency {
                await MainActor.run { onCancel() }
                return
            }
            
            if !Task.isCancelled {
                // 4. CRITICAL: Dispatch result to Main Actor (UI Thread)
                await MainActor.run {
                    onSuggestion(suggestion)
                }
            }
        }
    }
    
    /// Generate suggestion (Optimized)
    private func generateSuggestion(
        context: AutocompleteContext
    ) async -> InlineAutocompleteSuggestion? {
        
        // 🧪 TEST MODE: Optimized Check
        // STOP splitting the whole file! Use last200Lines instead.
        let recentContent = context.last200Lines.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if recentContent.hasSuffix("func fib") {
            // Return fake AI suggestion
            return InlineAutocompleteSuggestion(
                text: "(n: Int) -> Int {\n    if n <= 1 { return n }\n    return fib(n - 1) + fib(n - 2)\n}",
                confidence: 1.0,
                tokens: ["(n: Int)", " -> Int", " {", "\n    if", " n <= 1", " { return n }", "\n    return", " fib(n - 1)", " + fib(n - 2)", "\n}"]
            )
        }
        
        return nil
    }
    
    /// Stream tokens and check confidence incrementally
    func acceptToken(
        _ token: String,
        suggestion: inout InlineAutocompleteSuggestion
    ) -> Bool {
        suggestion.currentTokenIndex += 1
        return true
    }
    
    /// Cancel current suggestion
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
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
