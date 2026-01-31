//  AIService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Security

// MARK: - Enums

enum AIProvider: String, Codable {
    case openAI = "openai"
    case anthropic = "anthropic"
}

enum AnthropicModel: String, CaseIterable, Hashable {
    case sonnet45 = "claude-sonnet-4-5"
    case haiku45 = "claude-haiku-4-5"
    case opus45 = "claude-opus-4-5"
    // Fallback versions
    case sonnet45Dated = "claude-sonnet-4-5-20250929"
    case haiku45Dated = "claude-haiku-4-5-20251001"
    case opus45Dated = "claude-opus-4-5-20251101"
    
    var displayName: String {
        switch self {
        case .sonnet45, .sonnet45Dated: return "Claude Sonnet 4.5"
        case .haiku45, .haiku45Dated: return "Claude Haiku 4.5"
        case .opus45, .opus45Dated: return "Claude Opus 4.5"
        }
    }
}

// MARK: - Main Service

/// Single AI provider: streaming, tools, TTFT timeout, config.
/// Contains the full implementation (no delegation).
@MainActor
class AIService: AIProviderProtocol {
    static let shared = AIService()
    
    private var apiKey: String?
    private var provider: AIProvider = .anthropic
    private var anthropicModel: AnthropicModel = .sonnet45
    
    private var currentTask: Task<Void, Never>?
    private var isCancelled: Bool = false
    
    public private(set) var lastHTTPStatusCode: Int?
    
    var currentModel: String { anthropicModel.rawValue }
    
    private init() {
        loadAPIKey()
        loadModel()
    }
    
    // MARK: - Configuration & Key Management
    
    func setAPIKey(_ key: String, provider: AIProvider) {
        apiKey = key
        self.provider = provider
        saveAPIKey()
    }
    
    func getAPIKey() -> String? { apiKey }
    func getProvider() -> AIProvider { provider }
    
    func setAnthropicModel(_ model: AnthropicModel) {
        anthropicModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "anthropic_model")
    }
    
    func getAnthropicModel() -> AnthropicModel { anthropicModel }
    
    func cancelCurrentRequest() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - AIProviderProtocol
    
    func streamMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage] = [],
        maxTokens: Int? = nil,
        systemPrompt: String? = nil,
        tools: [AITool]? = nil,
        forceToolName: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            currentTask?.cancel()
            isCancelled = false
            lastHTTPStatusCode = nil
            
            let task = Task { @MainActor in
                do {
                    guard let apiKey = apiKey else {
                        continuation.finish(throwing: NSError(domain: "AIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not set"]))
                        return
                    }
                    
                    if LocalOnlyService.shared.isLocalModeEnabled && LocalOnlyService.shared.isLocalModelAvailable() {
                        try await handleLocalStreaming(message: message, context: context, continuation: continuation)
                        return
                    }
                    
                    switch provider {
                    case .openAI:
                        try await streamOpenAIMessage(message: message, context: context, images: images, apiKey: apiKey, maxTokens: maxTokens ?? 4096, systemPrompt: systemPrompt, continuation: continuation)
                    case .anthropic:
                        try await streamAnthropicWithFailover(message: message, context: context, images: images, apiKey: apiKey, maxTokens: maxTokens ?? 4096, systemPrompt: systemPrompt, tools: tools, forceToolName: forceToolName, continuation: continuation)
                    }
                } catch {
                    if !Task.isCancelled { continuation.finish(throwing: error) }
                }
            }
            
            currentTask = task
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    
    func sendMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage] = [],
        tools: [AITool]? = nil
    ) async throws -> String {
        var accumulatedText = ""
        for try await chunk in streamMessage(message, context: context, images: images, tools: tools) {
            accumulatedText += chunk
        }
        return accumulatedText
    }
    
    // MARK: - Legacy Compatibility Overloads
    
    func sendMessage(
        _ message: String,
        context: String? = nil,
        images: [AttachedImage] = [],
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task {
            do {
                let result = try await sendMessage(message, context: context, images: images, tools: nil)
                onResponse(result)
            } catch {
                onError(error)
            }
        }
    }
    
    func streamMessage(
        _ message: String,
        context: String? = nil,
        images: [AttachedImage] = [],
        maxTokens: Int? = nil,
        systemPrompt: String? = nil,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task {
            do {
                let stream = streamMessage(message, context: context, images: images, maxTokens: maxTokens, systemPrompt: systemPrompt, tools: nil, forceToolName: nil)
                for try await chunk in stream {
                    onChunk(chunk)
                }
                onComplete()
            } catch {
                onError(error)
            }
        }
    }
    
    // MARK: - Anthropic Streaming & Failover
    
    private func streamAnthropicWithFailover(
        message: String, context: String?, images: [AttachedImage], apiKey: String,
        maxTokens: Int, systemPrompt: String?, tools: [AITool]?, forceToolName: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let modelToUse = getAvailableModel()
        do {
            try await performAnthropicRequest(message: message, context: context, images: images, apiKey: apiKey, maxTokens: maxTokens, systemPrompt: systemPrompt, tools: tools, forceToolName: forceToolName, model: modelToUse, continuation: continuation)
        } catch {
            if (error as NSError).code == 429 || (error as NSError).code == 404 {
                continuation.yield("[Switching to Fallback Model...]\n")
                try await performAnthropicRequest(message: message, context: context, images: images, apiKey: apiKey, maxTokens: maxTokens, systemPrompt: systemPrompt, tools: tools, forceToolName: forceToolName, model: AnthropicModel.haiku45.rawValue, continuation: continuation)
            } else {
                throw error
            }
        }
    }
    
    private func performAnthropicRequest(
        message: String, context: String?, images: [AttachedImage], apiKey: String,
        maxTokens: Int, systemPrompt: String?, tools: [AITool]?, forceToolName: String?,
        model: String, continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var currentToolUse: (id: String, name: String, partialJson: String)?
        var hasReceivedChunks = false
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [["role": "user", "content": [["type": "text", "text": context != nil ? "Context:\n\(context!)\n\nQuestion: \(message)" : message]]]]
        ]
        if let system = systemPrompt { body["system"] = system }
        
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": recursiveUnwrap($0.inputSchema)] }
            body["tool_choice"] = forceToolName != nil ? ["type": "tool", "name": forceToolName!] : ["type": "any"]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let isDeepSearch = message.contains("codebase_search") || (context?.count ?? 0) > 50000
        let timeoutLimit: TimeInterval = isDeepSearch ? 60.0 : 30.0
        let requestStartTime = Date()
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: nil)
        }
        lastHTTPStatusCode = httpResponse.statusCode
        
        for try await line in bytes.lines {
            if !hasReceivedChunks && Date().timeIntervalSince(requestStartTime) > timeoutLimit {
                throw NSError(domain: "AIService", code: 408, userInfo: [NSLocalizedDescriptionKey: "AI is taking too long to think. Try a smaller context."])
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data: ") {
                let jsonStr = String(trimmed.dropFirst(6))
                if jsonStr == "[DONE]" { break }
                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else { continue }
                switch type {
                case "content_block_start":
                    if let cb = json["content_block"] as? [String: Any], cb["type"] as? String == "tool_use" {
                        currentToolUse = (id: cb["id"] as! String, name: cb["name"] as! String, partialJson: "")
                        continuation.yield("TOOL_STARTING:\(cb["name"]!)\n")
                    }
                case "content_block_delta":
                    hasReceivedChunks = true
                    if let delta = json["delta"] as? [String: Any] {
                        if let text = delta["text"] as? String { continuation.yield(text) }
                        if let part = delta["partial_json"] as? String { currentToolUse?.partialJson += part }
                    }
                case "content_block_stop":
                    if let tool = currentToolUse {
                        continuation.yield("TOOL_CALL:\(tool.id):\(tool.name):\(encodeToolInput(tool.partialJson))\n")
                        currentToolUse = nil
                    }
                case "message_stop":
                    continuation.finish()
                case "error":
                    throw NSError(domain: "AIService", code: 500, userInfo: nil)
                default: break
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func handleLocalStreaming(message: String, context: String?, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        guard LocalOnlyService.shared.isOllamaRunning else {
            throw NSError(domain: "Local", code: 5, userInfo: [NSLocalizedDescriptionKey: "Ollama not running"])
        }
        LocalOnlyService.shared.streamLocally(prompt: message, context: context,
            onChunk: { continuation.yield($0) },
            onComplete: { continuation.finish() },
            onError: { continuation.finish(throwing: $0) }
        )
    }
    
    private func getAvailableModel() -> String {
        let model = anthropicModel.rawValue
        return model.contains("-202") ? String(model.prefix(upTo: model.range(of: "-202")!.lowerBound)) : model
    }
    
    private func encodeToolInput(_ json: String) -> String {
        var finalJson = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalJson.hasSuffix("}") { finalJson += "}" }
        return Data(finalJson.utf8).base64EncodedString()
    }
    
    /// Unwraps AnyCodable and nested collections so JSONSerialization can encode the payload.
    private func recursiveUnwrap(_ value: Any) -> Any {
        if let anyCodable = value as? AnyCodable {
            return recursiveUnwrap(anyCodable.value)
        }
        if let dict = value as? [String: AnyCodable] {
            return dict.mapValues { recursiveUnwrap($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { recursiveUnwrap($0) }
        }
        if let array = value as? [Any] {
            return array.map { recursiveUnwrap($0) }
        }
        return value
    }
    
    // MARK: - Persistence
    
    private func loadAPIKey() {
        if let key = KeychainHelper.shared.load(forKey: "ai_api_key") { apiKey = key }
        if let prov = UserDefaults.standard.string(forKey: "ai_provider") { provider = prov == "openai" ? .openAI : .anthropic }
    }
    
    private func loadModel() {
        if let m = UserDefaults.standard.string(forKey: "anthropic_model"), let valid = AnthropicModel(rawValue: m) { anthropicModel = valid }
    }
    
    private func saveAPIKey() {
        if let key = apiKey { KeychainHelper.shared.save(key, forKey: "ai_api_key") }
    }
    
    private func streamOpenAIMessage(message: String, context: String?, images: [AttachedImage], apiKey: String, maxTokens: Int, systemPrompt: String?, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        continuation.finish(throwing: NSError(domain: "AIService", code: 501, userInfo: [NSLocalizedDescriptionKey: "OpenAI Stream Not Optimized Yet"]))
    }
}
