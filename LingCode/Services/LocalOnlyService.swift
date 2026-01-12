//
//  LocalOnlyService.swift
//  LingCode
//
//  Local-only mode for privacy and enterprise security
//  Addresses Cursor's privacy concerns
//

import Foundation
import Combine

/// Service for local-only AI processing
/// Addresses enterprise privacy and security concerns
class LocalOnlyService: ObservableObject {
    static let shared = LocalOnlyService()
    
    @Published var isLocalModeEnabled: Bool = false
    @Published var availableLocalModels: [LocalModelInfo] = []
    
    private init() {
        loadSettings()
        detectLocalModels()
    }
    
    /// Check if local model is available
    func isLocalModelAvailable() -> Bool {
        return !availableLocalModels.isEmpty
    }
    
    /// Enable local-only mode
    func enableLocalMode() {
        isLocalModeEnabled = true
        saveSettings()
    }
    
    /// Disable local-only mode
    func disableLocalMode() {
        isLocalModeEnabled = false
        saveSettings()
    }
    
    /// Detect available local models
    private func detectLocalModels() {
        availableLocalModels = []
        
        // Check for Ollama
        detectOllamaModels()
    }
    
    /// Detect Ollama models
    private func detectOllamaModels() {
        let ollamaURL = URL(string: "http://localhost:11434/api/tags")!
        
        // Use a semaphore to make this synchronous
        let semaphore = DispatchSemaphore(value: 0)
        var detectedModels: [LocalModelInfo] = []
        
        let task = URLSession.shared.dataTask(with: ollamaURL) { data, response, error in
            defer { semaphore.signal() }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                print("⚠️ Ollama not detected or not running")
                return
            }
            
            for model in models {
                if let name = model["name"] as? String {
                    detectedModels.append(LocalModelInfo(
                        id: name,
                        name: name,
                        provider: "ollama",
                        isAvailable: true
                    ))
                }
            }
        }
        
        task.resume()
        
        // Wait up to 2 seconds for response
        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            print("⚠️ Ollama detection timed out")
        } else {
            availableLocalModels = detectedModels
            if !detectedModels.isEmpty {
                print("✅ Detected \(detectedModels.count) Ollama model(s): \(detectedModels.map { $0.name }.joined(separator: ", "))")
            }
        }
    }
    
    /// Process request locally
    func processLocally(
        prompt: String,
        context: String? = nil,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard isLocalModeEnabled else {
            onError(NSError(domain: "LocalOnlyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local mode not enabled"]))
            return
        }
        
        guard let model = availableLocalModels.first else {
            onError(NSError(domain: "LocalOnlyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No local models available"]))
            return
        }
        
        // Process with local model
        // This would integrate with actual local model API
        processWithLocalModel(model: model, prompt: prompt, context: context, onResponse: onResponse, onError: onError)
    }
    
    /// Stream request locally (for real-time responses)
    func streamLocally(
        prompt: String,
        context: String? = nil,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard isLocalModeEnabled else {
            onError(NSError(domain: "LocalOnlyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local mode not enabled"]))
            return
        }
        
        guard let model = availableLocalModels.first else {
            onError(NSError(domain: "LocalOnlyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No local models available"]))
            return
        }
        
        // Stream with local model
        streamWithLocalModel(model: model, prompt: prompt, context: context, onChunk: onChunk, onComplete: onComplete, onError: onError)
    }
    
    private func processWithLocalModel(
        model: LocalModelInfo,
        prompt: String,
        context: String?,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Build full prompt with context
        var fullPrompt = prompt
        if let context = context, !context.isEmpty {
            // Limit context length to avoid overwhelming the model (Ollama has token limits)
            let maxContextLength = 8000 // characters
            let truncatedContext = context.count > maxContextLength 
                ? String(context.prefix(maxContextLength)) + "\n\n[Context truncated...]"
                : context
            fullPrompt = "Context:\n\(truncatedContext)\n\nRequest:\n\(prompt)"
        }
        
        // Limit total prompt length
        let maxPromptLength = 16000 // characters
        if fullPrompt.count > maxPromptLength {
            fullPrompt = String(fullPrompt.prefix(maxPromptLength)) + "\n\n[Prompt truncated due to length]"
        }
        
        // Use Ollama API
        if model.provider == "ollama" {
            callOllamaAPI(model: model, prompt: fullPrompt, onResponse: onResponse, onError: onError)
        } else {
            onError(NSError(domain: "LocalOnlyService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported local model provider: \(model.provider)"]))
        }
    }
    
    /// Call Ollama API
    private func callOllamaAPI(
        model: LocalModelInfo,
        prompt: String,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": model.name,
            "prompt": prompt,
            "stream": false
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            onError(NSError(domain: "LocalOnlyService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request to JSON"]))
            return
        }
        
        request.httpBody = jsonData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                onError(error)
                return
            }
            
            // Check HTTP status code first
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                var errorMessage = "Ollama returned error \(httpResponse.statusCode)"
                
                // Try to extract error message from response body
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = json["error"] as? String {
                    errorMessage = "Ollama error: \(errorMsg)"
                } else if let data = data,
                          let errorString = String(data: data, encoding: .utf8) {
                    errorMessage = "Ollama error: \(errorString)"
                }
                
                onError(NSError(domain: "LocalOnlyService", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: errorMessage
                ]))
                return
            }
            
            guard let data = data else {
                onError(NSError(domain: "LocalOnlyService", code: 4, userInfo: [NSLocalizedDescriptionKey: "No data received from Ollama"]))
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                onError(NSError(domain: "LocalOnlyService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from Ollama. Raw response: \(String(data: data, encoding: .utf8) ?? "unknown")"]))
                return
            }
            
            // Check for error in response
            if let errorMsg = json["error"] as? String {
                onError(NSError(domain: "LocalOnlyService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Ollama error: \(errorMsg)"]))
                return
            }
            
            guard let responseText = json["response"] as? String else {
                onError(NSError(domain: "LocalOnlyService", code: 4, userInfo: [NSLocalizedDescriptionKey: "No 'response' field in Ollama response. Response: \(String(describing: json))"]))
                return
            }
            
            onResponse(responseText)
        }
        
        task.resume()
    }
    
    /// Stream with local model (Ollama streaming)
    private func streamWithLocalModel(
        model: LocalModelInfo,
        prompt: String,
        context: String?,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Build full prompt with context
        var fullPrompt = prompt
        if let context = context, !context.isEmpty {
            // Limit context length to avoid overwhelming the model (Ollama has token limits)
            let maxContextLength = 8000 // characters
            let truncatedContext = context.count > maxContextLength 
                ? String(context.prefix(maxContextLength)) + "\n\n[Context truncated...]"
                : context
            fullPrompt = "Context:\n\(truncatedContext)\n\nRequest:\n\(prompt)"
        }
        
        // Limit total prompt length
        let maxPromptLength = 16000 // characters
        if fullPrompt.count > maxPromptLength {
            fullPrompt = String(fullPrompt.prefix(maxPromptLength)) + "\n\n[Prompt truncated due to length]"
        }
        
        // Use Ollama streaming API
        if model.provider == "ollama" {
            streamOllamaAPI(model: model, prompt: fullPrompt, onChunk: onChunk, onComplete: onComplete, onError: onError)
        } else {
            onError(NSError(domain: "LocalOnlyService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported local model provider: \(model.provider)"]))
        }
    }
    
    /// Stream Ollama API
    private func streamOllamaAPI(
        model: LocalModelInfo,
        prompt: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300.0 // 5 minutes timeout for large prompts
        
        let requestBody: [String: Any] = [
            "model": model.name,
            "prompt": prompt,
            "stream": true
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            onError(NSError(domain: "LocalOnlyService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request to JSON"]))
            return
        }
        
        request.httpBody = jsonData
        
        // Use URLSessionDataDelegate for streaming
        class StreamingDelegate: NSObject, URLSessionDataDelegate {
            var onChunk: (String) -> Void
            var onComplete: () -> Void
            var onError: (Error) -> Void
            var buffer = Data()
            var isDone = false
            
            init(onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (Error) -> Void) {
                self.onChunk = onChunk
                self.onComplete = onComplete
                self.onError = onError
            }
            
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                buffer.append(data)
                
                // Parse complete lines (Ollama sends JSON objects separated by newlines)
                let string = String(data: buffer, encoding: .utf8) ?? ""
                let lines = string.components(separatedBy: .newlines)
                
                // Keep the last incomplete line in buffer
                buffer = Data((lines.last ?? "").utf8)
                
                for line in lines.dropLast() {
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        continue
                    }
                    
                    // Extract response text
                    if let responseText = json["response"] as? String {
                        DispatchQueue.main.async {
                            self.onChunk(responseText)
                        }
                    }
                    
                    // Check if done
                    if let done = json["done"] as? Bool, done {
                        self.isDone = true
                        DispatchQueue.main.async {
                            self.onComplete()
                        }
                        return
                    }
                }
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error = error {
                    // Provide a more helpful error message
                    let nsError = error as NSError
                    var userMessage = "Failed to connect to Ollama"
                    
                    if nsError.code == NSURLErrorTimedOut {
                        userMessage = "Ollama connection timed out. Make sure Ollama is running: 'ollama serve'"
                    } else if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == -1021 { // NSURLErrorConnectionRefused
                        userMessage = "Cannot connect to Ollama. Make sure Ollama is running: 'ollama serve'"
                    } else {
                        userMessage = "Ollama error: \(error.localizedDescription)"
                    }
                    
                    let helpfulError = NSError(
                        domain: "LocalOnlyService",
                        code: 5,
                        userInfo: [
                            NSLocalizedDescriptionKey: userMessage,
                            NSUnderlyingErrorKey: error
                        ]
                    )
                    
                    DispatchQueue.main.async {
                        self.onError(helpfulError)
                    }
                } else if !isDone {
                    DispatchQueue.main.async {
                        self.onComplete()
                    }
                }
            }
            
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                // Check HTTP status code for streaming responses
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    var errorMessage = "Ollama returned error \(httpResponse.statusCode)"
                    
                    // Try to read error from response if available
                    if let errorJson = try? JSONSerialization.jsonObject(with: buffer, options: []) as? [String: Any],
                       let errorMsg = errorJson["error"] as? String {
                        errorMessage = "Ollama error: \(errorMsg)"
                    }
                    
                    let error = NSError(domain: "LocalOnlyService", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: errorMessage
                    ])
                    
                    DispatchQueue.main.async {
                        self.onError(error)
                    }
                    completionHandler(.cancel)
                    return
                }
                
                completionHandler(.allow)
            }
        }
        
        let delegate = StreamingDelegate(onChunk: onChunk, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        
        // Retain delegate
        objc_setAssociatedObject(task, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// Refresh available models (call this when Ollama models change)
    func refreshAvailableModels() {
        detectLocalModels()
    }
    
    /// Test connection to Ollama and verify it's working
    func testOllamaConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard let model = availableLocalModels.first else {
            completion(.failure(NSError(domain: "LocalOnlyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No local models available. Please download a model first: 'ollama pull deepseek-coder:6.7b'"])))
            return
        }
        
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0 // 10 second timeout
        
        let requestBody: [String: Any] = [
            "model": model.name,
            "prompt": "Say 'Hello, I am working!' in one sentence.",
            "stream": false
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                let nsError = error as NSError
                var message = "Cannot connect to Ollama"
                
                if nsError.code == NSURLErrorTimedOut {
                    message = "Ollama connection timed out. Make sure 'ollama serve' is running."
                } else if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == -1021 { // NSURLErrorConnectionRefused
                    message = "Ollama is not running. Please start it with: 'ollama serve'"
                } else {
                    message = "Error: \(error.localizedDescription)"
                }
                
                completion(.failure(NSError(domain: "LocalOnlyService", code: 6, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                completion(.failure(NSError(domain: "LocalOnlyService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Ollama"])))
                return
            }
            
            completion(.success(responseText))
        }
        
        task.resume()
    }
    
    /// Encrypt code before sending to API (when local mode is off)
    func encryptCode(_ code: String) -> String {
        // Simple base64 encoding for now
        // In production, would use proper encryption
        if let data = code.data(using: .utf8) {
            return data.base64EncodedString()
        }
        return code
    }
    
    /// Decrypt code after receiving from API
    func decryptCode(_ encrypted: String) -> String {
        // Simple base64 decoding for now
        if let data = Data(base64Encoded: encrypted),
           let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return encrypted
    }
    
    /// Log security action for audit
    func logAction(_ action: SecurityAction) {
        // Log to audit trail
        let logEntry = AuditLogEntry(
            action: action,
            timestamp: Date(),
            user: NSUserName()
        )
        
        // Save to audit log
        saveAuditLog(logEntry)
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isLocalModeEnabled, forKey: "local_mode_enabled")
    }
    
    private func loadSettings() {
        isLocalModeEnabled = UserDefaults.standard.bool(forKey: "local_mode_enabled")
    }
    
    private func saveAuditLog(_ entry: AuditLogEntry) {
        // Save to audit log file
        // In production, would use proper logging system
    }
}

// MARK: - Models

struct LocalModelInfo {
    let id: String
    let name: String
    let provider: String // "ollama", "lmstudio", etc.
    let isAvailable: Bool
}

enum SecurityAction {
    case codeApplied
    case codeRejected
    case fileOpened(path: String)
    case apiRequest(provider: String)
    case localRequest
    case settingsChanged
}

struct AuditLogEntry {
    let action: SecurityAction
    let timestamp: Date
    let user: String
}

