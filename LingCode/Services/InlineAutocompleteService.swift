//
//  InlineAutocompleteService.swift
//  LingCode
//
//  AI-powered inline autocomplete with FIM (Fill-in-Middle) support
//  Provides Copilot-style ghost text suggestions
//

import Foundation

struct InlineAutocompleteSuggestion: Equatable {
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
    
    static func == (lhs: InlineAutocompleteSuggestion, rhs: InlineAutocompleteSuggestion) -> Bool {
        lhs.text == rhs.text
    }
}

struct AutocompleteContext {
    let fileContent: String
    let cursorPosition: Int
    let last200Lines: String
    let language: String
    let filePath: String?
    
    init(fileContent: String, cursorPosition: Int, last200Lines: String, language: String, filePath: String? = nil) {
        self.fileContent = fileContent
        self.cursorPosition = cursorPosition
        self.last200Lines = last200Lines
        self.language = language
        self.filePath = filePath
    }
}

// MARK: - Autocomplete Configuration

struct AutocompleteConfig {
    var enabled: Bool = true
    var maxLatency: TimeInterval = 2.0  // Max wait time for suggestion
    var minPrefixLength: Int = 3        // Minimum chars before triggering
    var maxSuggestionLength: Int = 200  // Max chars in suggestion
    var debounceInterval: TimeInterval = 0.3  // Debounce typing
    var useLocalModel: Bool = true      // Prefer local models when available
}

// MARK: - Main Service

class InlineAutocompleteService {
    static let shared = InlineAutocompleteService()
    
    private var currentTask: Task<Void, Never>?
    private var config = AutocompleteConfig()
    private var cache: [String: InlineAutocompleteSuggestion] = [:]
    private let cacheLimit = 50
    
    private init() {
        loadConfig()
    }
    
    // MARK: - Configuration
    
    private func loadConfig() {
        config.enabled = UserDefaults.standard.object(forKey: "autocomplete_enabled") as? Bool ?? true
        config.useLocalModel = UserDefaults.standard.object(forKey: "autocomplete_use_local") as? Bool ?? true
    }
    
    func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autocomplete_enabled")
    }
    
    func isEnabled() -> Bool { config.enabled }
    
    // MARK: - Request Suggestion
    
    func requestSuggestion(
        context: AutocompleteContext,
        onSuggestion: @escaping (InlineAutocompleteSuggestion?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // 1. Check if enabled
        guard config.enabled else {
            onSuggestion(nil)
            return
        }
        
        // 2. Cancel previous task
        currentTask?.cancel()
        currentTask = nil
        
        // 3. Check minimum prefix
        let prefix = extractPrefix(from: context)
        guard prefix.count >= config.minPrefixLength else {
            onSuggestion(nil)
            return
        }
        
        // 4. Check cache
        let cacheKey = buildCacheKey(context: context)
        if let cached = cache[cacheKey] {
            onSuggestion(cached)
            return
        }
        
        let startTime = Date()
        
        currentTask = Task {
            do {
                // 5. Generate suggestion via AI
                let suggestion = try await generateAISuggestion(context: context)
                
                // 6. Check latency
                let latency = Date().timeIntervalSince(startTime)
                if latency > config.maxLatency {
                    await MainActor.run { onCancel() }
                    return
                }
                
                // 7. Cache and return
                if let suggestion = suggestion, !Task.isCancelled {
                    await MainActor.run {
                        self.cacheResult(key: cacheKey, suggestion: suggestion)
                        onSuggestion(suggestion)
                    }
                } else if !Task.isCancelled {
                    await MainActor.run { onSuggestion(nil) }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { onSuggestion(nil) }
                }
            }
        }
    }
    
    // MARK: - AI Suggestion Generation
    
    private func generateAISuggestion(context: AutocompleteContext) async throws -> InlineAutocompleteSuggestion? {
        // Build FIM (Fill-in-Middle) prompt
        let prompt = buildFIMPrompt(context: context)
        
        // Try local model first if available, then fall back to cloud
        let completion: String
        if config.useLocalModel && LocalModelService.shared.isLocalModelAvailable(for: .autocomplete) {
            completion = try await LocalModelService.shared.complete(
                prompt: prompt,
                maxTokens: config.maxSuggestionLength,
                temperature: 0.2,
                stopSequences: ["\n\n", "```", "//", "/*"]
            )
        } else {
            // Use fast cloud model (streaming disabled for speed)
            completion = try await requestCloudCompletion(prompt: prompt, context: context)
        }
        
        // Parse and validate completion
        guard !completion.isEmpty else { return nil }
        
        let cleanedCompletion = cleanCompletion(completion, context: context)
        guard !cleanedCompletion.isEmpty else { return nil }
        
        // Tokenize for incremental acceptance
        let tokens = tokenize(cleanedCompletion)
        
        return InlineAutocompleteSuggestion(
            text: cleanedCompletion,
            confidence: 0.8,
            tokens: tokens
        )
    }
    
    // MARK: - FIM Prompt Building
    
    private func buildFIMPrompt(context: AutocompleteContext) -> String {
        // FIM format: <prefix><cursor><suffix>
        // Most models use special tokens: <fim_prefix>, <fim_suffix>, <fim_middle>
        
        let content = context.fileContent
        let position = min(context.cursorPosition, content.count)
        
        let startIndex = content.startIndex
        let cursorIndex = content.index(startIndex, offsetBy: position, limitedBy: content.endIndex) ?? content.endIndex
        
        let prefix = String(content[startIndex..<cursorIndex])
        let suffix = String(content[cursorIndex..<content.endIndex])
        
        // Truncate for context window
        let maxPrefixChars = 2000
        let maxSuffixChars = 500
        
        let truncatedPrefix = prefix.count > maxPrefixChars 
            ? String(prefix.suffix(maxPrefixChars)) 
            : prefix
        let truncatedSuffix = suffix.count > maxSuffixChars 
            ? String(suffix.prefix(maxSuffixChars)) 
            : suffix
        
        // Build prompt based on language
        let languageHint = "// Language: \(context.language)\n"
        let fileHint = context.filePath.map { "// File: \($0)\n" } ?? ""
        
        return """
        \(languageHint)\(fileHint)// Complete the code at the cursor position. Only output the completion, no explanation.

        \(truncatedPrefix)<CURSOR>\(truncatedSuffix)

        // Completion (output ONLY the code that goes at <CURSOR>):
        """
    }
    
    // MARK: - Cloud Completion
    
    private func requestCloudCompletion(prompt: String, context: AutocompleteContext) async throws -> String {
        // Use a fast model for completions
        var result = ""
        
        let stream = await MainActor.run {
            AIService.shared.streamMessage(
                prompt,
                context: nil,
                images: [],
                maxTokens: config.maxSuggestionLength,
                systemPrompt: "You are a code completion assistant. Output ONLY the code completion, nothing else. No markdown, no explanation, no comments about what you're doing. Just the raw code that should be inserted.",
                tools: nil
            )
        }
        
        for try await chunk in stream {
            result += chunk
            // Early termination for performance
            if result.count > config.maxSuggestionLength {
                break
            }
        }
        
        return result
    }
    
    // MARK: - Completion Cleaning
    
    private func cleanCompletion(_ completion: String, context: AutocompleteContext) -> String {
        var cleaned = completion
        
        // Remove markdown code blocks
        if cleaned.hasPrefix("```") {
            if let endIndex = cleaned.range(of: "\n")?.upperBound {
                cleaned = String(cleaned[endIndex...])
            }
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        // Remove leading/trailing whitespace but preserve internal formatting
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove any "explanation" text that might have slipped through
        if let explanationStart = cleaned.range(of: "//", options: .backwards) {
            let afterSlash = cleaned[explanationStart.upperBound...]
            if afterSlash.contains("complete") || afterSlash.contains("insert") || afterSlash.contains("output") {
                cleaned = String(cleaned[..<explanationStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Limit length
        if cleaned.count > config.maxSuggestionLength {
            // Try to cut at a sensible boundary
            let truncated = String(cleaned.prefix(config.maxSuggestionLength))
            if let lastNewline = truncated.lastIndex(of: "\n") {
                cleaned = String(truncated[..<lastNewline])
            } else {
                cleaned = truncated
            }
        }
        
        return cleaned
    }
    
    // MARK: - Tokenization
    
    private func tokenize(_ text: String) -> [String] {
        // Simple tokenization by logical code units
        var tokens: [String] = []
        var current = ""
        
        for char in text {
            if char == "\n" || char == "(" || char == ")" || char == "{" || char == "}" || char == ";" || char == "," {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else if char == " " && current.count > 10 {
                // Break long sequences at spaces
                tokens.append(current + " ")
                current = ""
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            tokens.append(current)
        }
        
        return tokens.isEmpty ? [text] : tokens
    }
    
    // MARK: - Helpers
    
    private func extractPrefix(from context: AutocompleteContext) -> String {
        let lines = context.last200Lines.components(separatedBy: .newlines)
        return lines.last ?? ""
    }
    
    private func buildCacheKey(context: AutocompleteContext) -> String {
        // Cache key based on recent content hash
        let recent = String(context.last200Lines.suffix(500))
        return "\(context.language):\(recent.hashValue)"
    }
    
    private func cacheResult(key: String, suggestion: InlineAutocompleteSuggestion) {
        cache[key] = suggestion
        // Evict old entries if needed
        if cache.count > cacheLimit {
            let keysToRemove = Array(cache.keys.prefix(cache.count - cacheLimit))
            for k in keysToRemove {
                cache.removeValue(forKey: k)
            }
        }
    }
    
    // MARK: - Token Acceptance
    
    func acceptToken(_ token: String, suggestion: inout InlineAutocompleteSuggestion) -> Bool {
        suggestion.currentTokenIndex += 1
        return true
    }
    
    // MARK: - Cancel
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        cache.removeAll()
    }
}
