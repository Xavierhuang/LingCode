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
        systemPrompt: String? = nil,
        tools: [AITool]? = nil
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
                        // 🟢 FIX: Check if Ollama is running before attempting to stream
                        if !localService.isOllamaRunning {
                            let error = NSError(
                                domain: "LocalOnlyService",
                                code: 5,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Cannot connect to Ollama. Make sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve\n3. Try again"
                                ]
                            )
                            continuation.finish(throwing: error)
                            return
                        }
                        
                        // Use local streaming (convert callback to async stream)
                        // Use a thread-safe cancellation flag with actor
                        actor LocalStreamCancellation {
                            var isCancelled = false
                            func setCancelled(_ value: Bool) { self.isCancelled = value }
                            func getCancelled() -> Bool { return self.isCancelled }
                        }
                        let cancellation = LocalStreamCancellation()
                        
                        localService.streamLocally(
                            prompt: message,
                            context: context,
                            onChunk: { chunk in
                                Task {
                                    let cancelled = await cancellation.getCancelled()
                                    if !cancelled {
                                        continuation.yield(chunk)
                                    }
                                }
                            },
                            onComplete: {
                                Task {
                                    let cancelled = await cancellation.getCancelled()
                                    if !cancelled {
                                        continuation.finish()
                                    }
                                }
                            },
                            onError: { error in
                                Task {
                                    let cancelled = await cancellation.getCancelled()
                                    if !cancelled {
                                        continuation.finish(throwing: error)
                                    }
                                }
                            }
                        )
                        
                        continuation.onTermination = { @Sendable _ in
                            Task {
                                await cancellation.setCancelled(true)
                            }
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
                        // FIX: Smart failover - try primary model, fallback to lighter model on timeout
                        do {
                            try await streamAnthropicMessageWithFailover(
                                message: message,
                                context: context,
                                images: images,
                                apiKey: apiKey,
                                maxTokens: maxTokens ?? 4096,
                                systemPrompt: systemPrompt,
                                tools: tools,
                                continuation: continuation
                            )
                        } catch {
                            // If timeout or model not found, try failover
                            if case AIError.timeout = error, anthropicModel != .haiku45 {
                                continuation.yield("[Falling back to Haiku...]\n")
                                let originalModel = anthropicModel
                                anthropicModel = .haiku45
                                do {
                                    try await streamAnthropicMessageWithFailover(
                                        message: message,
                                        context: context,
                                        images: images,
                                        apiKey: apiKey,
                                        maxTokens: maxTokens ?? 4096,
                                        systemPrompt: systemPrompt,
                                        tools: tools,
                                        continuation: continuation
                                    )
                                } catch {
                                    anthropicModel = originalModel
                                    throw error
                                }
                                anthropicModel = originalModel
                            } else {
                                throw error
                            }
                        }
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
        images: [AttachedImage] = [],
        tools: [AITool]? = nil
    ) async throws -> String {
        var accumulatedText = ""
        
        for try await chunk in streamMessage(message, context: context, images: images, tools: tools) {
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
    
    /// FIX: Smart failover wrapper - handles timeout and model fallback
    private func streamAnthropicMessageWithFailover(
        message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        maxTokens: Int,
        systemPrompt: String?,
        tools: [AITool]?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // FIX: Get model with fallback for future dates
        var modelToUse = getAvailableModel()
        
        print("🔍 Selected model from enum: '\(anthropicModel.rawValue)'")
        print("🔍 Converted to API model: '\(modelToUse)'")
        
        // FIX: Try primary model first, fallback to available model on 400/404 errors
        do {
            try await streamAnthropicMessage(
                message: message,
                context: context,
                images: images,
                apiKey: apiKey,
                maxTokens: maxTokens,
                systemPrompt: systemPrompt,
                tools: tools,
                model: modelToUse,
                continuation: continuation
            )
        } catch {
            // If model not found (400/404), try fallback model
            if let aiError = error as? AIError,
               case .serverError(let code, _) = aiError,
               (code == 400 || code == 404),
               modelToUse != AnthropicModel.haiku45.rawValue {
                print("⚠️ Primary model '\(modelToUse)' not available, trying fallback...")
                modelToUse = AnthropicModel.haiku45.rawValue
                try await streamAnthropicMessage(
                    message: message,
                    context: context,
                    images: images,
                    apiKey: apiKey,
                    maxTokens: maxTokens,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    model: modelToUse,
                    continuation: continuation
                )
            } else {
                // Re-throw other errors
                throw error
            }
        }
    }
    
    // MARK: - SSE Event Processing Helper
    
    /// Process a single SSE event (extracted from accumulated lines)
    /// Returns true if continuation was finished (should stop processing)
    private func processSSEEvent(
        _ eventString: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        hasReceivedChunks: inout Bool,
        firstChunkTime: inout Date?,
        startTime: Date,
        rawLines: [String],
        httpResponse: HTTPURLResponse,
        currentToolUse: inout (id: String, name: String, partialJson: String)?
    ) -> Bool {
        // FIX: SSE format has "event:" and "data:" on separate lines
        // Extract the "data:" line from the accumulated event
        let eventLines = eventString.components(separatedBy: .newlines)
        var dataLine: String?
        
        for eventLine in eventLines {
            let trimmed = eventLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data: ") {
                dataLine = trimmed
                break
            }
        }
        
        guard let dataLine = dataLine else {
            return false
        }
        
        // FIX: Safe string indexing - use dropFirst which is safe
        guard dataLine.count > 6 else {
            return false
        }
        let jsonString = String(dataLine.dropFirst(6)) // Remove "data: " prefix
        
        if jsonString == "[DONE]" {
            print("✅ Received [DONE] marker")
            if !hasReceivedChunks {
                print("❌ [DONE] received but no chunks were processed")
                print("📋 All lines received: \(rawLines.joined(separator: "\n"))")
                continuation.finish(throwing: AIError.emptyResponse)
            } else {
                continuation.finish()
            }
            return true
        }
        
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = json["type"] as? String else {
            return false
        }
        
        print("🔍 Parsed SSE event type: '\(type)'")
        
        // FIX: Handle tool use blocks (agent capabilities)
        // Anthropic sends tool_use in content_block_start events, but input is streamed as deltas
        if type == "content_block_start",
           let contentBlock = json["content_block"] as? [String: Any],
           let blockType = contentBlock["type"] as? String,
           blockType == "tool_use" {
            // Extract tool use information - input may be empty here, will come in deltas
            if let toolUseId = contentBlock["id"] as? String,
               let toolName = contentBlock["name"] as? String {
                print("🔍 [ModernAIService] Tool use started: \(toolName) (ID: \(toolUseId))")
                // FIX: If there's a previous tool use, emit it first (shouldn't happen, but be safe)
                if let previousToolUse = currentToolUse, !previousToolUse.partialJson.isEmpty {
                    print("🟡 [ModernAIService] New tool use started but previous tool use not emitted, emitting now")
                    if let jsonData = previousToolUse.partialJson.data(using: .utf8),
                       let toolInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        continuation.yield("🔧 TOOL_CALL:\(previousToolUse.id):\(previousToolUse.name):\(encodeToolInput(toolInput))\n")
                        hasReceivedChunks = true
                    }
                }
                // Start tracking this tool use - input will come in deltas
                currentToolUse = (id: toolUseId, name: toolName, partialJson: "")
                // Check if input is already complete (non-streaming case)
                if let toolInput = contentBlock["input"] as? [String: Any], !toolInput.isEmpty {
                    print("🔍 [ModernAIService] Tool input provided in start event")
                    continuation.yield("🔧 TOOL_CALL:\(toolUseId):\(toolName):\(encodeToolInput(toolInput))\n")
                    hasReceivedChunks = true
                    currentToolUse = nil // Clear tracking
                }
            }
        } else if type == "content_block_delta",
           let delta = json["delta"] as? [String: Any] {
            
            // Check if this is an input_json_delta (tool input streaming)
            if let deltaType = delta["type"] as? String, deltaType == "input_json_delta",
               let partialJson = delta["partial_json"] as? String {
                // Accumulate partial JSON for tool input
                if var toolUse = currentToolUse {
                    toolUse.partialJson += partialJson
                    currentToolUse = toolUse
                    print("🔍 [ModernAIService] Accumulating tool input JSON: \(partialJson.prefix(50))... (total: \(toolUse.partialJson.count) chars)")
                } else {
                    print("🟡 [ModernAIService] Received input_json_delta but currentToolUse is nil")
                }
            } else {
                // Regular text delta
                let text: String?
                if let textDelta = delta["text"] as? String {
                    text = textDelta
                } else {
                    text = nil
                }
                
                if let text = text, !text.isEmpty {
                    let previewLength = min(50, text.count)
                    let preview = String(text.prefix(previewLength))
                    print("📝 content_block_delta: text='\(preview)'")
                    if firstChunkTime == nil {
                        firstChunkTime = Date()
                        print("🎉 First chunk received at \(Date().timeIntervalSince(startTime))s")
                    }
                    hasReceivedChunks = true
                    continuation.yield(text)
                } else {
                    print("⚠️ content_block_delta has no text or empty text")
                    print("   Delta structure: \(delta)")
                }
            }
        } else if type == "content_block_stop" {
            // Tool input is complete - emit tool call marker
            print("🔍 [ModernAIService] content_block_stop received")
            if let toolUse = currentToolUse {
                print("🔍 [ModernAIService] currentToolUse exists: \(toolUse.name), partialJson length: \(toolUse.partialJson.count)")
                if !toolUse.partialJson.isEmpty {
                    print("🔍 [ModernAIService] Tool input complete, parsing JSON")
                    // Parse the accumulated JSON
                    if let jsonData = toolUse.partialJson.data(using: .utf8),
                       let toolInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        print("🟢 [ModernAIService] Emitting tool call: \(toolUse.name)")
                        continuation.yield("🔧 TOOL_CALL:\(toolUse.id):\(toolUse.name):\(encodeToolInput(toolInput))\n")
                        hasReceivedChunks = true
                        currentToolUse = nil
                    } else {
                        print("🔴 [ModernAIService] Failed to parse accumulated tool input JSON")
                        print("🔴 [ModernAIService] JSON string (first 500 chars): \(toolUse.partialJson.prefix(500))")
                        print("🔴 [ModernAIService] JSON string (last 500 chars): \(toolUse.partialJson.suffix(500))")
                        currentToolUse = nil
                    }
                } else {
                    print("🟡 [ModernAIService] content_block_stop but partialJson is empty")
                    currentToolUse = nil
                }
            } else {
                print("🟡 [ModernAIService] content_block_stop but currentToolUse is nil")
            }
        } else if type == "message_stop" {
            print("🛑 message_stop received")
            
            // FIX: Before finishing, check if there's a pending tool use and emit it
            if let toolUse = currentToolUse, !toolUse.partialJson.isEmpty {
                print("🔍 [ModernAIService] message_stop received, checking for pending tool call")
                print("🔍 [ModernAIService] Tool: \(toolUse.name), partialJson length: \(toolUse.partialJson.count)")
                print("🔍 [ModernAIService] Partial JSON preview: \(toolUse.partialJson.prefix(100))")
                
                // Try to parse and emit the tool call
                if let jsonData = toolUse.partialJson.data(using: .utf8),
                   let toolInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    print("🟢 [ModernAIService] Emitting pending tool call before message_stop: \(toolUse.name)")
                    continuation.yield("🔧 TOOL_CALL:\(toolUse.id):\(toolUse.name):\(encodeToolInput(toolInput))\n")
                    hasReceivedChunks = true
                } else {
                    // JSON is incomplete - analyze what's missing
                    let trimmedJson = toolUse.partialJson.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isAlmostComplete = trimmedJson.hasSuffix("\"") || trimmedJson.hasSuffix("}") || trimmedJson.hasSuffix("]")
                    
                    // Check for specific tool requirements
                    var missingFields: [String] = []
                    if toolUse.name == "write_file" {
                        if !trimmedJson.contains("\"content\"") {
                            missingFields.append("content")
                        }
                        if !trimmedJson.contains("\"file_path\"") {
                            missingFields.append("file_path")
                        }
                    }
                    
                    print("🔴 [ModernAIService] Failed to parse tool input JSON before message_stop")
                    print("🔴 [ModernAIService] Tool: \(toolUse.name), JSON length: \(toolUse.partialJson.count) chars")
                    print("🔴 [ModernAIService] JSON preview (first 200 chars): \(toolUse.partialJson.prefix(200))")
                    print("🔴 [ModernAIService] JSON preview (last 200 chars): \(toolUse.partialJson.suffix(200))")
                    if !missingFields.isEmpty {
                        print("🔴 [ModernAIService] Missing required fields: \(missingFields.joined(separator: ", "))")
                    }
                    print("🔴 [ModernAIService] JSON appears incomplete - stream ended prematurely")
                    print("🔴 [ModernAIService] Almost complete: \(isAlmostComplete)")
                    print("🔴 [ModernAIService] This may indicate a network timeout, API response size limit, or stream truncation")
                    print("🔴 [ModernAIService] For write_file with large content, the API may be hitting response size limits")
                    
                    // Try to fix common incomplete JSON patterns (missing closing brace) only if we have all required fields
                    if !isAlmostComplete && trimmedJson.count > 10 && missingFields.isEmpty {
                        // Try adding closing quote and brace if it looks like we're missing just the closing
                        var fixedJson = trimmedJson
                        if !fixedJson.hasSuffix("\"") && fixedJson.contains("\"file_path\"") {
                            // Might be missing closing quote
                            if let lastQuoteRange = fixedJson.range(of: "\"", options: .backwards) {
                                let afterLastQuote = String(fixedJson[lastQuoteRange.upperBound...])
                                if !afterLastQuote.contains("\"") && !afterLastQuote.contains(",") {
                                    fixedJson += "\""
                                }
                            }
                        }
                        if !fixedJson.hasSuffix("}") {
                            fixedJson += "}"
                        }
                        
                        if let jsonData = fixedJson.data(using: .utf8),
                           let toolInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            print("🟡 [ModernAIService] Attempting to fix incomplete JSON by adding closing quote/brace")
                            continuation.yield("🔧 TOOL_CALL:\(toolUse.id):\(toolUse.name):\(encodeToolInput(toolInput))\n")
                            hasReceivedChunks = true
                        } else {
                            print("🔴 [ModernAIService] Could not fix incomplete JSON - missing required fields or malformed")
                        }
                    } else if !missingFields.isEmpty {
                        print("🔴 [ModernAIService] Cannot fix incomplete JSON - missing required fields: \(missingFields.joined(separator: ", "))")
                        
                        // Emit a special error message in the stream so the agent knows what happened
                        // This will appear in the accumulated response and help the agent understand the issue
                        let errorHint = "\n\n⚠️ API Response Truncated: The tool call for '\(toolUse.name)' was incomplete because the response was too large. For large file writes, consider breaking the content into smaller chunks or using a different approach."
                        continuation.yield(errorHint)
                        hasReceivedChunks = true
                    }
                }
                currentToolUse = nil
            }
            
            if !hasReceivedChunks {
                print("❌ message_stop but no chunks received")
                print("📋 All events received: \(rawLines.joined(separator: "\n"))")
                continuation.finish(throwing: AIError.emptyResponse)
            } else {
                continuation.finish()
            }
            return true
        } else if type == "error",
                  let error = json["error"] as? [String: Any],
                  let message = error["message"] as? String {
            continuation.finish(throwing: AIError.serverError(httpResponse.statusCode, message))
            return true
        }
        
        return false
    }
    
    private func streamAnthropicMessage(
        message: String,
        context: String?,
        images: [AttachedImage],
        apiKey: String,
        maxTokens: Int,
        systemPrompt: String?,
        tools: [AITool]?,
        model: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // Track tool use blocks and accumulate their input JSON
        var currentToolUse: (id: String, name: String, partialJson: String)? = nil
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
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        
        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }
        
        // FIX: Add tools support for agent capabilities
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { tool in
                var toolDict: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description
                ]
                
                // CRITICAL FIX: Recursively unwrap the schema
                // This prevents the "Invalid type in JSON write" crash
                if let inputSchema = recursiveUnwrap(tool.inputSchema) as? [String: Any] {
                    toolDict["input_schema"] = inputSchema
                } else {
                    // Fallback to empty object if unwrap fails
                    toolDict["input_schema"] = [:]
                }
                
                return toolDict
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // DEBUG: Log the actual model being used
        print("🔍 Making API request with model: '\(model)'")
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("📤 Request body: \(bodyString)")
        }
        
        // Use URLSession.bytes(for:) for modern async streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        lastHTTPStatusCode = httpResponse.statusCode
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // FIX: Read error response body for better error messages
            var errorBody = ""
            do {
                // Try to read error response
                var errorData = Data()
                for try await chunk in bytes {
                    errorData.append(chunk)
                    if errorData.count > 10000 { break } // Limit read size
                }
                if let errorString = String(data: errorData, encoding: .utf8),
                   let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorBody = message
                } else if let errorString = String(data: errorData, encoding: .utf8) {
                    errorBody = errorString
                }
            } catch {
                // Ignore error reading body
            }
            
            let errorMessage: String
            if !errorBody.isEmpty {
                errorMessage = errorBody
            } else if httpResponse.statusCode == 429 {
                errorMessage = "Rate limit exceeded. Please wait a moment and try again."
            } else if httpResponse.statusCode == 529 || httpResponse.statusCode == 503 {
                errorMessage = "Service overloaded. Please try again later."
            } else if httpResponse.statusCode == 400 {
                errorMessage = "Invalid request. The model may not be available. Try using Claude Sonnet 3.5 or Claude Haiku instead."
            } else if httpResponse.statusCode == 404 {
                errorMessage = "Model not found. The model '\(model)' may not be available yet. Try using Claude Sonnet 3.5 or Claude Haiku instead."
            } else {
                errorMessage = "HTTP \(httpResponse.statusCode). Please check your API key and model selection."
            }
            
            print("❌ Anthropic API Error:")
            print("   Status Code: \(httpResponse.statusCode)")
            print("   Model: \(model)")
            print("   Error: \(errorMessage)")
            
            throw AIError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // FIX: Adaptive TTFT timeout - longer for complex operations
        // Detect if this is a complex operation that may take longer
        let isComplexOperation = (context?.count ?? 0) > 50000 || // Large context
                               message.lowercased().contains("codebase_search") ||
                               message.lowercased().contains("analyze") ||
                               message.lowercased().contains("upgrade") ||
                               message.lowercased().contains("refactor")
        
        // Use longer timeout for complex operations (15s) vs simple ones (6s)
        let ttftTimeout: TimeInterval = isComplexOperation ? 15.0 : 6.0
        
        let startTime = Date()
        var firstChunkTime: Date?
        var hasReceivedChunks = false
        var continuationFinished = false // FIX: Track if continuation is already finished
        var rawLines: [String] = [] // DEBUG: Collect raw lines for debugging
        
        // Parse SSE stream - process line by line, detect complete events
        var currentEvent = ""
        var lineCount = 0
        
        for try await line in bytes.lines {
            lineCount += 1
            // DEBUG: Log first few lines to see what we're getting
            if lineCount <= 10 {
                print("📥 SSE Line \(lineCount): '\(line)'")
            }
            rawLines.append(line)
            
            // FIX: Check adaptive TTFT timeout
            let elapsed = Date().timeIntervalSince(startTime)
            if !hasReceivedChunks && elapsed > ttftTimeout {
                print("⏱️ TTFT timeout after \(elapsed)s (limit: \(ttftTimeout)s), no chunks received")
                print("📋 First 20 lines received: \(rawLines.prefix(20).joined(separator: "\n"))")
                if isComplexOperation {
                    print("⚠️ [ModernAIService] Complex operation timed out - this may be normal for large codebase searches")
                }
                if !continuationFinished {
                    continuation.finish(throwing: AIError.timeout)
                    continuationFinished = true
                }
                return
            }
            if Task.isCancelled {
                if !continuationFinished {
                    continuation.finish(throwing: AIError.cancelled)
                    continuationFinished = true
                }
                return
            }
            
            // FIX: Process event when we see a new "event:" line or empty line
            // This handles SSE format where events may not have empty lines between them
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isNewEvent = trimmedLine.hasPrefix("event: ")
            let isEmpty = line.isEmpty
            
            if (isNewEvent || isEmpty) && !currentEvent.isEmpty {
                // Process the accumulated event before starting a new one
                let shouldStop = processSSEEvent(currentEvent, continuation: continuation, hasReceivedChunks: &hasReceivedChunks, firstChunkTime: &firstChunkTime, startTime: startTime, rawLines: rawLines, httpResponse: httpResponse, currentToolUse: &currentToolUse)
                if shouldStop {
                    continuationFinished = true
                    return
                }
                currentEvent = ""
            }
            
            if !isEmpty {
                // Accumulate event lines
                if !currentEvent.isEmpty {
                    currentEvent += "\n"
                }
                currentEvent += line
            }
        }
        
        // Process any remaining event
        if !currentEvent.isEmpty && !continuationFinished {
            let shouldStop = processSSEEvent(currentEvent, continuation: continuation, hasReceivedChunks: &hasReceivedChunks, firstChunkTime: &firstChunkTime, startTime: startTime, rawLines: rawLines, httpResponse: httpResponse, currentToolUse: &currentToolUse)
            if shouldStop {
                continuationFinished = true
                return
            }
        }
        
        // FIX: If we have a pending tool use with accumulated JSON, emit it now
        if let toolUse = currentToolUse {
            print("🔍 [ModernAIService] Stream ended, checking for pending tool call")
            print("🔍 [ModernAIService] Tool: \(toolUse.name), partialJson length: \(toolUse.partialJson.count)")
            if !toolUse.partialJson.isEmpty {
                print("🔍 [ModernAIService] Stream ended, emitting final tool call with accumulated JSON")
                if let jsonData = toolUse.partialJson.data(using: .utf8),
                   let toolInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    print("🟢 [ModernAIService] Emitting tool call at stream end: \(toolUse.name)")
                    continuation.yield("🔧 TOOL_CALL:\(toolUse.id):\(toolUse.name):\(encodeToolInput(toolInput))\n")
                    hasReceivedChunks = true
                } else {
                    print("🔴 [ModernAIService] Failed to parse tool input JSON at stream end")
                    print("🔴 [ModernAIService] JSON string (first 500 chars): \(toolUse.partialJson.prefix(500))")
                }
            } else {
                print("🟡 [ModernAIService] Stream ended but partialJson is empty for tool: \(toolUse.name)")
            }
            currentToolUse = nil
        }
        
        // Stream ended - only finish if not already finished
        if !continuationFinished {
            if !hasReceivedChunks {
                print("❌ Stream ended with no chunks received")
                print("   Model used: '\(model)'")
                print("   HTTP Status: \(httpResponse.statusCode)")
                print("   Total lines received: \(lineCount)")
                print("   Raw lines (first 50):")
                for (index, line) in rawLines.prefix(50).enumerated() {
                    print("     [\(index)]: \(line)")
                }
                if rawLines.count > 50 {
                    print("     ... and \(rawLines.count - 50) more lines")
                }
                continuation.finish(throwing: AIError.emptyResponse)
            } else {
                print("✅ Stream completed successfully with chunks")
                continuation.finish()
            }
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
    
    /// Get current model name as string
    var currentModel: String {
        switch provider {
        case .anthropic:
            return anthropicModel.rawValue
        case .openAI:
            return "gpt-4o"
        }
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
        if let modelString = UserDefaults.standard.string(forKey: "anthropic_model") {
            print("📦 Loading model from UserDefaults: '\(modelString)'")
            // FIX: Migrate old dated model names to new alias names
            let migratedString = migrateModelName(modelString)
            print("🔄 Migrated to: '\(migratedString)'")
            
            if let model = AnthropicModel(rawValue: migratedString) {
                anthropicModel = model
                print("✅ Model loaded: '\(model.rawValue)' (display: '\(model.displayName)')")
                // Save migrated model back to UserDefaults
                if migratedString != modelString {
                    UserDefaults.standard.set(migratedString, forKey: "anthropic_model")
                    print("💾 Saved migrated model to UserDefaults")
                }
            } else {
                print("⚠️ Could not find enum case for '\(migratedString)', using default")
                // Fallback to default if migration result doesn't match enum
                anthropicModel = .sonnet45
            }
        } else {
            print("📦 No model in UserDefaults, using default: '\(anthropicModel.rawValue)'")
        }
    }
    
    /// FIX: Migrate old dated model names to new alias names
    private func migrateModelName(_ modelString: String) -> String {
        // Map old dated models to new aliases
        switch modelString {
        case "claude-sonnet-4-5-20250929":
            return "claude-sonnet-4-5"
        case "claude-haiku-4-5-20251001":
            return "claude-haiku-4-5"
        case "claude-opus-4-5-20251101":
            return "claude-opus-4-5"
        case "claude-opus-4-1-20250805":
            return "claude-opus-4-5" // Migrate 4.1 to 4.5
        default:
            // If it's already an alias or unknown, return as-is
            return modelString
        }
    }
    
    // MARK: - FIX: Model Fallback & Token Estimation
    
    /// FIX: Get available model with fallback for future dates
    /// Always returns alias model name (without date) for compatibility
    private func getAvailableModel() -> String {
        let modelID = anthropicModel.rawValue
        print("🔍 getAvailableModel() called with enum value: '\(modelID)'")
        
        // FIX: If model has a date, convert to alias
        // This ensures we always use the alias which works even if dated version doesn't exist
        if modelID.contains("-202") {
            // Extract base model name (everything before the date)
            if let dateIndex = modelID.range(of: "-202")?.lowerBound {
                let baseModel = String(modelID[..<dateIndex])
                print("⚠️ Model '\(modelID)' has date, using alias '\(baseModel)'")
                return baseModel
            }
        }
        
        // If already an alias or no date, return as-is
        print("✅ Using model as-is: '\(modelID)'")
        return modelID
    }
    
    /// FIX: Improved token estimation (ported from AIService)
    /// IMPROVEMENT: Uses BPE tokenizer for accurate token counting
    private func estimateTokens(_ text: String) -> Int {
        return BPETokenizer.shared.estimateTokens(text)
    }
    
    /// FIX: Encode tool input to string for streaming
    private func encodeToolInput(_ input: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        // Base64 encode to avoid newline issues in stream
        return Data(string.utf8).base64EncodedString()
    }
    
    // MARK: - Helper: Recursive Unwrap for AnyCodable
    
    /// FIX: Recursively unwraps AnyCodable and arrays/dictionaries containing AnyCodable
    /// into pure JSON primitives (String, Number, Bool, Array, Dictionary).
    /// This prevents the "Invalid type in JSON write (__SwiftValue)" crash.
    private func recursiveUnwrap(_ value: Any) -> Any {
        // Handle AnyCodable wrapper
        if let anyCodable = value as? AnyCodable {
            return recursiveUnwrap(anyCodable.value)
        }
        
        // Handle dictionaries - recursively unwrap all values
        if let dict = value as? [String: Any] {
            return dict.mapValues { recursiveUnwrap($0) }
        }
        
        // Handle arrays - recursively unwrap all elements
        if let array = value as? [Any] {
            return array.map { recursiveUnwrap($0) }
        }
        
        // Handle dictionaries with AnyCodable values directly
        if let dict = value as? [String: AnyCodable] {
            return dict.mapValues { recursiveUnwrap($0) }
        }
        
        // Handle arrays with AnyCodable elements directly
        if let array = value as? [AnyCodable] {
            return array.map { recursiveUnwrap($0) }
        }
        
        // Return primitive types as-is (String, Int, Double, Bool, etc.)
        return value
    }
}
