//
//  AIService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Security

enum AIProvider: String, Codable {
    case openAI = "openai"
    case anthropic = "anthropic"
    
    var rawValue: String {
        switch self {
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        }
    }
}

enum AnthropicModel: String, CaseIterable {
    case sonnet45 = "claude-sonnet-4-5-20250929"
    case haiku45 = "claude-haiku-4-5-20251001"
    case opus41 = "claude-opus-4-1-20250805"
    
    var displayName: String {
        switch self {
        case .sonnet45: return "Claude Sonnet 4.5"
        case .haiku45: return "Claude Haiku 4.5"
        case .opus41: return "Claude Opus 4.1"
        }
    }
    
    var description: String {
        switch self {
        case .sonnet45: return "Smartest model for complex agents and coding"
        case .haiku45: return "Fastest model with near-frontier intelligence"
        case .opus41: return "Exceptional model for specialized reasoning"
        }
    }
}

class AIService {
    static let shared = AIService()
    
    private var apiKey: String?
    private var provider: AIProvider = .anthropic
    private var anthropicModel: AnthropicModel = .sonnet45
    
    // Track current task for cancellation
    private var currentTask: URLSessionTask?
    private var currentSession: URLSession?
    private var currentDelegate: AnyObject? // Retain delegate
    private var isCancelled: Bool = false
    
    private init() {
        loadAPIKey()
        loadModel()
    }
    
    /// Estimate token count (simplified)
    private func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    /// Cancel the current AI request
    func cancelCurrentRequest() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        currentSession?.invalidateAndCancel()
        currentSession = nil
        currentDelegate = nil // Release delegate
    }
    
    /// Clean up streaming resources (called by delegate)
    func cleanupStreaming() {
        currentTask = nil
        currentSession = nil
        currentDelegate = nil
    }
    
    /// Check if a request is currently in progress
    var isRequestInProgress: Bool {
        return currentTask != nil
    }
    
    func setAnthropicModel(_ model: AnthropicModel) {
        anthropicModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "anthropic_model")
    }
    
    func getAnthropicModel() -> AnthropicModel {
        return anthropicModel
    }
    
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
    
    func sendMessage(
        _ message: String,
        context: String? = nil,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Check if local mode is enabled and available
        let localService = LocalOnlyService.shared
        if localService.isLocalModeEnabled && localService.isLocalModelAvailable() {
            // Use local model
            localService.processLocally(
                prompt: message,
                context: context,
                onResponse: onResponse,
                onError: onError
            )
            return
        }
        
        // Check cache first
        let performanceService = PerformanceService.shared
        if let cached = performanceService.getCachedResponse(prompt: message, context: context) {
            onResponse(cached)
            return
        }
        
        // Check rate limits
        let usageService = UsageTrackingService.shared
        usageService.checkRateLimits(provider: provider)
        if usageService.rateLimitStatus.isAtLimit {
            onError(NSError(domain: "AIService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded"]))
            return
        }
        
        guard let apiKey = apiKey else {
            onError(NSError(domain: "AIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"]))
            return
        }
        
        // Reset cancellation flag
        isCancelled = false
        
        switch provider {
        case .openAI:
            sendOpenAIMessage(message, context: context, images: [], apiKey: apiKey, onResponse: onResponse, onError: onError)
        case .anthropic:
            sendAnthropicMessage(message, context: context, images: [], apiKey: apiKey, onResponse: onResponse, onError: onError)
        }
    }
    
    func sendMessage(
        _ message: String,
        context: String? = nil,
        images: [AttachedImage] = [],
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let apiKey = apiKey else {
            onError(NSError(domain: "AIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"]))
            return
        }
        
        switch provider {
        case .openAI:
            sendOpenAIMessage(message, context: context, images: images, apiKey: apiKey, onResponse: onResponse, onError: onError)
        case .anthropic:
            sendAnthropicMessage(message, context: context, images: images, apiKey: apiKey, onResponse: onResponse, onError: onError)
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
        // Check if local mode is enabled and available
        let localService = LocalOnlyService.shared
        if localService.isLocalModeEnabled && localService.isLocalModelAvailable() {
            // Use local model with streaming
            localService.streamLocally(
                prompt: message,
                context: context,
                onChunk: onChunk,
                onComplete: onComplete,
                onError: onError
            )
            return
        }
        
        guard let apiKey = apiKey else {
            onError(NSError(domain: "AIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"]))
            return
        }
        
        let tokens = maxTokens ?? 4096 // Default to 4096, but allow override for project generation
        
        switch provider {
        case .openAI:
            streamOpenAIMessage(message, context: context, images: images, apiKey: apiKey, maxTokens: tokens, systemPrompt: systemPrompt, onChunk: onChunk, onComplete: onComplete, onError: onError)
        case .anthropic:
            streamAnthropicMessage(message, context: context, images: images, apiKey: apiKey, maxTokens: tokens, systemPrompt: systemPrompt, onChunk: onChunk, onComplete: onComplete, onError: onError)
        }
    }
    
    private func sendOpenAIMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        var fullMessage = message
        if let context = context {
            fullMessage = "Context:\n\(context)\n\nQuestion: \(message)"
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build message content with images
        var messageContent: [[String: Any]] = []
        
        // Add text
        messageContent.append([
            "type": "text",
            "text": fullMessage
        ])
        
        // Add images
        for image in images {
            messageContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/png;base64,\(image.base64)",
                    "detail": "auto"
                ]
            ])
        }
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": messageContent]
            ],
            "temperature": 0.7,
            "max_tokens": 4096
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                DispatchQueue.main.async {
                    self?.currentTask = nil
                }
            }
            
            // Check if cancelled
            if self?.isCancelled == true {
                DispatchQueue.main.async {
                    onError(NSError(domain: "AIService", code: -999, userInfo: [NSLocalizedDescriptionKey: "Request cancelled"]))
                }
                return
            }
            
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled {
                    DispatchQueue.main.async {
                        onError(NSError(domain: "AIService", code: -999, userInfo: [NSLocalizedDescriptionKey: "Request cancelled"]))
                    }
                    return
                }
                DispatchQueue.main.async {
                    onError(error)
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DispatchQueue.main.async {
                    onError(NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                }
                return
            }
            
            DispatchQueue.main.async {
                onResponse(content)
            }
        }
        
        currentTask = task
        task.resume()
    }
    
    private func streamOpenAIMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        maxTokens: Int,
        systemPrompt: String? = nil,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        var fullMessage = message
        if let context = context {
            fullMessage = "Context:\n\(context)\n\nQuestion: \(message)"
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build message content with images
        var messageContent: [[String: Any]] = []
        
        // Add text
        messageContent.append([
            "type": "text",
            "text": fullMessage
        ])
        
        // Add images
        for image in images {
            messageContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/png;base64,\(image.base64)",
                    "detail": "auto"
                ]
            ])
        }
        
        // Build messages array (system prompt first if provided, then user message)
        var messages: [[String: Any]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": messageContent])
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": maxTokens,
            "stream": true
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    onError(error)
                }
                return
            }
            
            // For streaming, we'd need to use URLSessionDataDelegate
            // For now, fall back to non-streaming
            self.sendOpenAIMessage(message, context: context, images: images, apiKey: apiKey, onResponse: { response in
                onChunk(response)
                onComplete()
            }, onError: onError)
        }.resume()
    }
    
    private func sendAnthropicMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        var fullMessage = message
        if let context = context {
            fullMessage = "Context:\n\(context)\n\nQuestion: \(message)"
        }
        
        // Build content array with images and text
        var content: [[String: Any]] = []
        
        // Add images first (Anthropic format)
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
        
        // Add text
        content.append([
            "type": "text",
            "text": fullMessage
        ])
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Add user agent
        request.setValue("LingCode/1.0", forHTTPHeaderField: "User-Agent")
        
        print("🔗 Anthropic API Request:")
        print("   URL: \(url)")
        print("   Model: \(anthropicModel.rawValue)")
        print("   API Key: \(apiKey.prefix(20))...")
        
        let body: [String: Any] = [
            "model": anthropicModel.rawValue,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                print("📤 Request body: \(bodyString)")
            }
        } catch {
            print("❌ Failed to serialize request body: \(error)")
            DispatchQueue.main.async {
                onError(error)
            }
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                DispatchQueue.main.async {
                    self?.currentTask = nil
                }
            }
            
            // Check if cancelled
            if self?.isCancelled == true {
                DispatchQueue.main.async {
                    onError(NSError(domain: "AIService", code: -999, userInfo: [NSLocalizedDescriptionKey: "Request cancelled"]))
                }
                return
            }
            
            if let error = error {
                // Check if it's a cancellation error
                if (error as NSError).code == NSURLErrorCancelled {
                    DispatchQueue.main.async {
                        onError(NSError(domain: "AIService", code: -999, userInfo: [NSLocalizedDescriptionKey: "Request cancelled"]))
                    }
                    return
                }
                print("Network error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    onError(error)
                }
                return
            }
            
            guard let data = data else {
                print("No data received from API")
                DispatchQueue.main.async {
                    onError(NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                }
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("Error response: \(errorData)")
                        if let errorMessage = errorData["error"] as? [String: Any],
                           let message = errorMessage["message"] as? String {
                            DispatchQueue.main.async {
                                onError(NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))
                            }
                        } else if let errorMessage = errorData["error"] as? String {
                            DispatchQueue.main.async {
                                onError(NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                            }
                        } else {
                            let responseString = String(data: data, encoding: .utf8) ?? "Unknown"
                            print("Error response string: \(responseString)")
                            DispatchQueue.main.async {
                                onError(NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(responseString)"]))
                            }
                        }
                    } else {
                        let responseString = String(data: data, encoding: .utf8) ?? "Unknown"
                        print("Error response (not JSON): \(responseString)")
                        DispatchQueue.main.async {
                            onError(NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                        }
                    }
                    return
                }
            }
            
            // Parse successful response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Response received. Keys: \(json.keys)")
                
                if let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first {
                    print("Content array found with \(content.count) items")
                    
                    if let text = firstContent["text"] as? String {
                        print("Text extracted: \(text.prefix(100))...")
                        DispatchQueue.main.async {
                            onResponse(text)
                        }
                        return
                    } else {
                        print("No 'text' field in content. Content keys: \(firstContent.keys)")
                    }
                } else {
                    print("No 'content' array found. Response structure: \(json)")
                }
                
                // Try to get error message from response
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("API error in response: \(message)")
                    DispatchQueue.main.async {
                        onError(NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: message]))
                    }
                } else {
                    let responseString = String(data: data, encoding: .utf8) ?? "Unknown"
                    print("Invalid response format. Full response: \(responseString)")
                    DispatchQueue.main.async {
                        onError(NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response format. Check console for details."]))
                    }
                }
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "Unknown"
                print("Failed to parse JSON. Response: \(responseString)")
                DispatchQueue.main.async {
                    onError(NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response. Check console for details."]))
                }
            }
        }
        
        currentTask = task
        task.resume()
    }
    
    private func streamAnthropicMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        maxTokens: Int,
        systemPrompt: String? = nil,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        var fullMessage = message
        if let context = context {
            fullMessage = "Context:\n\(context)\n\nQuestion: \(message)"
        }
        
        // Build content array with images and text
        var content: [[String: Any]] = []
        
        // Add images first (Anthropic format)
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
        
        // Add text
        content.append([
            "type": "text",
            "text": fullMessage
        ])
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("LingCode/1.0", forHTTPHeaderField: "User-Agent")
        
        var body: [String: Any] = [
            "model": anthropicModel.rawValue,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        
        // Add system prompt if provided (Anthropic API supports system field)
        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async {
                onError(error)
            }
            return
        }
        
        // Create a custom URLSession with a delegate for streaming
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        
        class StreamingDelegate: NSObject, URLSessionDataDelegate {
            let onChunk: (String) -> Void
            let onComplete: () -> Void
            let onError: (Error) -> Void
            weak var service: AIService?
            var buffer = Data()
            var receivedData = Data()
            var httpStatusCode: Int?
            var hasReceivedChunks = false
            var firstChunkTime: Date?
            var lastChunkTime: Date?
            var timeoutTimer: Timer?
            
            // Timeout detection: If no chunks arrive within 30 seconds of HTTP 200, treat as failure
            let chunkTimeout: TimeInterval = 30.0
            
            init(service: AIService, onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (Error) -> Void) {
                self.service = service
                self.onChunk = onChunk
                self.onComplete = onComplete
                self.onError = onError
            }
            
            // MARK: - HTTP Response Handling (Network Failure Detection)
            
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                // NETWORK FAILURE HANDLING: Treat non-2xx responses as HARD FAILURES
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatusCode = httpResponse.statusCode
                    print("🔗 HTTP Status Code: \(httpResponse.statusCode)")
                    
                    // Check if status code is NOT 2xx (200-299)
                    if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                        // HARD FAILURE: Do not proceed to parsing or apply phases
                        let errorMessage: String
                        if httpResponse.statusCode == 429 {
                            errorMessage = "AI service temporarily unavailable. Rate limit exceeded. Please retry."
                        } else if httpResponse.statusCode == 529 || httpResponse.statusCode == 503 {
                            errorMessage = "AI service temporarily unavailable. Service overloaded. Please retry."
                        } else {
                            errorMessage = "AI service temporarily unavailable. HTTP \(httpResponse.statusCode). Please retry."
                        }
                        
                        // Log telemetry
                        print("❌ NETWORK FAILURE: HTTP \(httpResponse.statusCode) - \(errorMessage)")
                        
                        DispatchQueue.main.async {
                            self.onError(NSError(
                                domain: "AIService",
                                code: httpResponse.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: errorMessage]
                            ))
                        }
                        
                        // Cancel the task - do not proceed
                        completionHandler(.cancel)
                        return
                    }
                    
                    // For 2xx responses, start timeout timer to detect "silent failures"
                    // If no chunks arrive within timeout period, treat as empty response
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        DispatchQueue.main.async {
                            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: self.chunkTimeout, repeats: false) { [weak self] _ in
                                guard let self = self else { return }
                                if !self.hasReceivedChunks {
                                    // TIMEOUT: HTTP 200 but no chunks received
                                    print("❌ SILENT FAILURE DETECTED: HTTP 200 but no content chunks received within \(self.chunkTimeout)s")
                                    print("   HTTP Status: \(self.httpStatusCode ?? 0)")
                                    print("   Response data length: \(self.receivedData.count)")
                                    print("   Possible causes: Server sent success but failed to generate text, or parsing failed")
                                    
                                    self.onError(NSError(
                                        domain: "AIService",
                                        code: 204, // No Content
                                        userInfo: [
                                            NSLocalizedDescriptionKey: "Connection successful (HTTP 200) but no content was received. This may be a transient server issue. Please retry.",
                                            "failure_type": "silent_failure",
                                            "http_status": self.httpStatusCode ?? 0,
                                            "received_bytes": self.receivedData.count
                                        ]
                                    ))
                                }
                            }
                        }
                    }
                }
                
                // Continue with normal processing for 2xx responses
                completionHandler(.allow)
            }
            
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                if service?.isCancelled == true {
                    dataTask.cancel()
                    return
                }
                
                // Track received data for empty response detection
                receivedData.append(data)
                buffer.append(data)
                
                // Parse Server-Sent Events (SSE) format
                // Process complete lines, keep incomplete ones in buffer
                guard let string = String(data: buffer, encoding: .utf8) else {
                    return
                }
                
                let lines = string.components(separatedBy: "\n")
                
                // Process all complete lines (everything except the last one)
                for line in lines.dropLast() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        continue
                    }
                    
                    if trimmed.hasPrefix("data: ") {
                        let jsonString = String(trimmed.dropFirst(6))
                        if jsonString == "[DONE]" {
                            DispatchQueue.main.async {
                                self.onComplete()
                            }
                            return
                        }
                        
                        guard let jsonData = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                            continue
                        }
                        
                        // Handle different event types
                        if let type = json["type"] as? String {
                            if type == "content_block_delta" {
                                if let delta = json["delta"] as? [String: Any],
                                   let text = delta["text"] as? String,
                                   !text.isEmpty {
                                    // Track chunk timing for timeout detection
                                    let now = Date()
                                    if firstChunkTime == nil {
                                        firstChunkTime = now
                                        // Cancel timeout timer once we receive first chunk
                                        DispatchQueue.main.async {
                                            self.timeoutTimer?.invalidate()
                                            self.timeoutTimer = nil
                                        }
                                    }
                                    lastChunkTime = now
                                    
                                    hasReceivedChunks = true
                                    DispatchQueue.main.async {
                                        self.onChunk(text)
                                    }
                                }
                            } else if type == "message_stop" {
                                DispatchQueue.main.async {
                                    self.onComplete()
                                }
                                return
                            } else if type == "error" {
                                if let error = json["error"] as? [String: Any],
                                   let message = error["message"] as? String {
                                    DispatchQueue.main.async {
                                        self.onError(NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: message]))
                                    }
                                }
                                return
                            }
                        }
                    }
                }
                
                // Keep the last (potentially incomplete) line in buffer
                if let lastLine = lines.last, !lastLine.isEmpty {
                    buffer = Data(lastLine.utf8)
                } else {
                    buffer = Data()
                }
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                // Process any remaining data in buffer
                if !buffer.isEmpty, let string = String(data: buffer, encoding: .utf8) {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed.hasPrefix("data: ") {
                        let jsonString = String(trimmed.dropFirst(6))
                        if jsonString != "[DONE]" {
                            if let jsonData = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let type = json["type"] as? String,
                               type == "content_block_delta",
                               let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                hasReceivedChunks = true
                                DispatchQueue.main.async {
                                    self.onChunk(text)
                                }
                            }
                        }
                    }
                }
                
                if let error = error {
                    if (error as NSError).code != NSURLErrorCancelled {
                        DispatchQueue.main.async {
                            self.onError(error)
                        }
                    }
                } else {
                    // Cancel timeout timer if still running
                    DispatchQueue.main.async {
                        self.timeoutTimer?.invalidate()
                        self.timeoutTimer = nil
                    }
                    
                    // EMPTY RESPONSE GUARD: Enhanced detection for "silent failures"
                    // Case 1: HTTP 200 but no chunks received (server sent success but no content)
                    // Case 2: HTTP 200 with data but no parseable text chunks (malformed SSE)
                    // Case 3: HTTP 200 with empty response body
                    if !hasReceivedChunks {
                        let responseString = String(data: receivedData, encoding: .utf8) ?? ""
                        let trimmedResponse = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Determine failure type for better error messages
                        var failureType = "empty_response"
                        var errorMessage = "AI service returned an empty response. Please retry."
                        
                        if receivedData.count > 0 && trimmedResponse.isEmpty {
                            // Non-empty data but can't be decoded as UTF-8
                            failureType = "encoding_error"
                            errorMessage = "Received response data but couldn't decode it. This may indicate a server encoding issue. Please retry."
                        } else if receivedData.count > 0 && !trimmedResponse.isEmpty {
                            // Data received but no parseable chunks (malformed SSE)
                            failureType = "parse_error"
                            errorMessage = "Received response but couldn't parse content chunks. The server may have sent malformed data. Please retry."
                            
                            // Log raw response for debugging (first 500 chars)
                            let preview = String(trimmedResponse.prefix(500))
                            print("   Raw response preview: \(preview)")
                        } else if receivedData.count == 0 {
                            // Truly empty response
                            failureType = "empty_response"
                            errorMessage = "Connection successful (HTTP 200) but no data was received. This may be a transient server issue. Please retry."
                        }
                        
                        // EMPTY RESPONSE: Abort pipeline immediately
                        print("❌ EMPTY RESPONSE DETECTED:")
                        print("   Failure type: \(failureType)")
                        print("   HTTP Status: \(httpStatusCode ?? 0)")
                        print("   Response data length: \(receivedData.count)")
                        print("   Has received chunks: \(hasReceivedChunks)")
                        if let firstChunk = firstChunkTime {
                            print("   First chunk time: \(firstChunk)")
                        }
                        if let lastChunk = lastChunkTime {
                            print("   Last chunk time: \(lastChunk)")
                        }
                        print("   Possible causes:")
                        print("   1. Server sent success signal but failed to generate text")
                        print("   2. IDE's parser failed to read incoming stream")
                        print("   3. ViewBridge/UI crash interrupted response rendering")
                        print("   4. Context length/timeout - request too large or took too long")
                        
                        DispatchQueue.main.async {
                            self.onError(NSError(
                                domain: "AIService",
                                code: 204, // No Content
                                userInfo: [
                                    NSLocalizedDescriptionKey: errorMessage,
                                    "failure_type": failureType,
                                    "http_status": self.httpStatusCode ?? 0,
                                    "received_bytes": self.receivedData.count
                                ]
                            ))
                        }
                        return
                    }
                    
                    // Ensure onComplete is called even if we didn't see [DONE]
                    DispatchQueue.main.async {
                        self.onComplete()
                        // Clean up after completion
                        self.service?.cleanupStreaming()
                    }
                }
            }
        }
        
        let delegate = StreamingDelegate(service: self, onChunk: onChunk, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: OperationQueue())
        
        let task = session.dataTask(with: request)
        currentTask = task
        currentSession = session
        currentDelegate = delegate // Retain delegate to prevent deallocation
        task.resume()
    }
    
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

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private init() {}
    
    func save(_ value: String, forKey key: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
}

