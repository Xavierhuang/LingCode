//
//  ModernAIService.swift
//  LingCode
//
//  Modern async/await implementation of AIService
//  Uses AsyncThrowingStream for streaming and eliminates callback hell
//

import Foundation

/// Modern AI Service using async/await and AsyncThrowingStream
/// This replaces the callback-based AIService for better Swift 6 concurrency
@MainActor
class ModernAIService: AIProviderProtocol {
    private var apiKey: String?
    private var provider: AIProvider = .anthropic
    private var anthropicModel: AnthropicModel = .sonnet45
    
    private(set) var lastHTTPStatusCode: Int?
    private var currentTask: Task<Void, Never>?
    private var isCancelled: Bool = false
    
    init(apiKey: String? = nil, provider: AIProvider = .anthropic) {
        self.apiKey = apiKey
        self.provider = provider
        loadAPIKey()
        loadModel()
    }
    
    // MARK: - AIProviderProtocol
    
    func streamMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage] = [],
        maxTokens: Int? = nil,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            // Cancel any existing request
            currentTask?.cancel()
            isCancelled = false
            lastHTTPStatusCode = nil
            
            let task = Task { @MainActor in
                do {
                    guard let apiKey = apiKey else {
                        continuation.finish(throwing: AIError.apiKeyNotSet)
                        return
                    }
                    
                    // Check local mode first
                    let localService = LocalOnlyService.shared
                    if localService.isLocalModeEnabled && localService.isLocalModelAvailable() {
                        // Use local streaming (convert callback to async stream)
                        // Use a thread-safe cancellation flag with NSLock
                        var localStreamCancelled = false
                        let cancellationLock = NSLock()
                        
                        localService.streamLocally(
                            prompt: message,
                            context: context,
                            onChunk: { chunk in
                                cancellationLock.lock()
                                let cancelled = localStreamCancelled
                                cancellationLock.unlock()
                                if !cancelled {
                                    continuation.yield(chunk)
                                }
                            },
                            onComplete: {
                                cancellationLock.lock()
                                let cancelled = localStreamCancelled
                                cancellationLock.unlock()
                                if !cancelled {
                                    continuation.finish()
                                }
                            },
                            onError: { error in
                                cancellationLock.lock()
                                let cancelled = localStreamCancelled
                                cancellationLock.unlock()
                                if !cancelled {
                                    continuation.finish(throwing: error)
                                }
                            }
                        )
                        
                        continuation.onTermination = { @Sendable _ in
                            cancellationLock.lock()
                            localStreamCancelled = true
                            cancellationLock.unlock()
                        }
                        return
                    }
                    
                    // Use cloud provider
                    switch provider {
                    case .openAI:
                        try await streamOpenAIMessage(
                            message: message,
                            context: context,
                            images: images,
                            apiKey: apiKey,
                            maxTokens: maxTokens ?? 4096,
                            systemPrompt: systemPrompt,
                            continuation: continuation
                        )
                    case .anthropic:
                        try await streamAnthropicMessage(
                            message: message,
                            context: context,
                            images: images,
                            apiKey: apiKey,
                            maxTokens: maxTokens ?? 4096,
                            systemPrompt: systemPrompt,
                            continuation: continuation
                        )
                    }
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            currentTask = task
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { @MainActor in
                    self.isCancelled = true
                }
            }
        }
    }
    
    func sendMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage] = []
    ) async throws -> String {
        var accumulatedText = ""
        
        for try await chunk in streamMessage(message, context: context, images: images) {
            accumulatedText += chunk
        }
        
        return accumulatedText
    }
    
    func cancelCurrentRequest() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Private Streaming Implementations
    
    private func streamAnthropicMessage(
        message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        maxTokens: Int,
        systemPrompt: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var fullMessage = message
        if let context = context {
            fullMessage = "Context:\n\(context)\n\nQuestion: \(message)"
        }
        
        // Build content array
        var content: [[String: Any]] = []
        content.append(["type": "text", "text": fullMessage])
        
        for image in images {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/png",
                    "data": image.base64
                ]
            ])
        }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var body: [String: Any] = [
            "model": anthropicModel.rawValue,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        
        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Use URLSession.bytes(for:) for modern async streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        lastHTTPStatusCode = httpResponse.statusCode
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = httpResponse.statusCode == 429
                ? "Rate limit exceeded"
                : httpResponse.statusCode == 529 || httpResponse.statusCode == 503
                ? "Service overloaded"
                : "HTTP \(httpResponse.statusCode)"
            throw AIError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Parse SSE stream - process line by line, detect complete events
        var currentEvent = ""
        var hasReceivedChunks = false
        
        for try await line in bytes.lines {
            if Task.isCancelled {
                continuation.finish(throwing: AIError.cancelled)
                return
            }
            
            // Empty line indicates end of SSE event
            if line.isEmpty {
                // Process the accumulated event
                let trimmed = currentEvent.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("data: ") {
                    let jsonString = String(trimmed.dropFirst(6))
                    if jsonString == "[DONE]" {
                        if !hasReceivedChunks {
                            continuation.finish(throwing: AIError.emptyResponse)
                        } else {
                            continuation.finish()
                        }
                        return
                    }
                    
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let type = json["type"] as? String {
                        
                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String,
                           !text.isEmpty {
                            hasReceivedChunks = true
                            continuation.yield(text)
                        } else if type == "message_stop" {
                            if !hasReceivedChunks {
                                continuation.finish(throwing: AIError.emptyResponse)
                            } else {
                                continuation.finish()
                            }
                            return
                        } else if type == "error",
                                  let error = json["error"] as? [String: Any],
                                  let message = error["message"] as? String {
                            continuation.finish(throwing: AIError.serverError(httpResponse.statusCode, message))
                            return
                        }
                    }
                }
                currentEvent = ""
            } else {
                // Accumulate event lines
                if !currentEvent.isEmpty {
                    currentEvent += "\n"
                }
                currentEvent += line
            }
        }
        
        // Process any remaining event
        if !currentEvent.isEmpty {
            let trimmed = currentEvent.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data: ") {
                let jsonString = String(trimmed.dropFirst(6))
                if jsonString != "[DONE]" {
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let type = json["type"] as? String,
                       type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String,
                       !text.isEmpty {
                        hasReceivedChunks = true
                        continuation.yield(text)
                    }
                }
            }
        }
        
        // Stream ended
        if !hasReceivedChunks {
            continuation.finish(throwing: AIError.emptyResponse)
        } else {
            continuation.finish()
        }
    }
    
    private func streamOpenAIMessage(
        message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        maxTokens: Int,
        systemPrompt: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var fullMessage = message
        if let context = context {
            fullMessage = "Context:\n\(context)\n\nQuestion: \(message)"
        }
        
        var messageContent: [[String: Any]] = []
        messageContent.append(["type": "text", "text": fullMessage])
        
        for image in images {
            messageContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/png;base64,\(image.base64)",
                    "detail": "auto"
                ]
            ])
        }
        
        var messages: [[String: Any]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": messageContent])
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": maxTokens,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        lastHTTPStatusCode = httpResponse.statusCode
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIError.serverError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }
        
        // Parse OpenAI SSE stream - process line by line
        var hasReceivedChunks = false
        
        for try await line in bytes.lines {
            if Task.isCancelled {
                continuation.finish(throwing: AIError.cancelled)
                return
            }
            
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data: ") {
                let jsonString = String(trimmed.dropFirst(6))
                if jsonString == "[DONE]" {
                    if !hasReceivedChunks {
                        continuation.finish(throwing: AIError.emptyResponse)
                    } else {
                        continuation.finish()
                    }
                    return
                }
                
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String,
                   !content.isEmpty {
                    hasReceivedChunks = true
                    continuation.yield(content)
                }
            }
        }
        
        if !hasReceivedChunks {
            continuation.finish(throwing: AIError.emptyResponse)
        } else {
            continuation.finish()
        }
    }
    
    // MARK: - Configuration
    
    func setAPIKey(_ key: String, provider: AIProvider) {
        self.apiKey = key
        self.provider = provider
        saveAPIKey()
    }
    
    func getAPIKey() -> String? {
        return apiKey
    }
    
    func getProvider() -> AIProvider {
        return provider
    }
    
    func setAnthropicModel(_ model: AnthropicModel) {
        anthropicModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "anthropic_model")
    }
    
    func getAnthropicModel() -> AnthropicModel {
        return anthropicModel
    }
    
    // MARK: - Private Helpers
    
    private func saveAPIKey() {
        if let apiKey = apiKey {
            let keychain = KeychainHelper.shared
            keychain.save(apiKey, forKey: "ai_api_key")
            UserDefaults.standard.set(provider == .openAI ? "openai" : "anthropic", forKey: "ai_provider")
        }
    }
    
    private func loadAPIKey() {
        let keychain = KeychainHelper.shared
        if let apiKey = keychain.load(forKey: "ai_api_key") {
            self.apiKey = apiKey
        }
        
        if let providerString = UserDefaults.standard.string(forKey: "ai_provider") {
            self.provider = providerString == "openai" ? .openAI : .anthropic
        }
    }
    
    private func loadModel() {
        if let modelString = UserDefaults.standard.string(forKey: "anthropic_model"),
           let model = AnthropicModel(rawValue: modelString) {
            anthropicModel = model
        }
    }
}
