//
//  LocalOnlyService.swift
//  LingCode
//
//  Local-only mode for privacy and enterprise security
//  Addresses Cursor's privacy concerns
//

import Foundation
import Combine
import AppKit

/// Service for local-only AI processing
/// Addresses enterprise privacy and security concerns
class LocalOnlyService: ObservableObject {
    static let shared = LocalOnlyService()
    
    @Published var isLocalModeEnabled: Bool = false
    @Published var availableLocalModels: [LocalModelInfo] = []
    @Published var isOllamaRunning: Bool = false
    @Published var isInstallingOllama: Bool = false
    @Published var isPullingModels: Bool = false
    @Published var installationProgress: String = ""
    @Published var modelPullProgress: [String: String] = [:] // model name -> progress message
    
    private init() {
        loadSettings()
        // Check Ollama status on startup
        checkOllamaStatus()
        // Only detect models if local mode is enabled (to avoid connection errors)
        if isLocalModeEnabled {
            detectLocalModels()
        }
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
    
    /// Check if Ollama is running on localhost:11434
    func checkOllamaStatus() {
        let url = URL(string: "http://localhost:11434/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0 // Quick check
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    self.isOllamaRunning = true
                    // Auto-detect models if Ollama is running
                    if self.isLocalModeEnabled {
                        self.detectLocalModels()
                    }
                } else {
                    self.isOllamaRunning = false
                }
            }
        }
        task.resume()
    }
    
    /// Install Ollama programmatically
    func installOllama(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async {
            self.isInstallingOllama = true
            self.installationProgress = "Checking system..."
        }
        
        // Check if Ollama is already installed
        checkOllamaStatus()
        if isOllamaRunning {
            DispatchQueue.main.async {
                self.isInstallingOllama = false
                self.installationProgress = "Ollama is already installed and running"
            }
            completion(.success(()))
            return
        }
        
        // Check if Ollama binary exists
        let ollamaPath = "/usr/local/bin/ollama"
        if FileManager.default.fileExists(atPath: ollamaPath) {
            // Ollama is installed but not running - try to start it
            DispatchQueue.main.async {
                self.installationProgress = "Starting Ollama..."
            }
            startOllamaService { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isInstallingOllama = false
                    switch result {
                    case .success:
                        self.installationProgress = "Ollama started successfully"
                        self.isOllamaRunning = true
                    case .failure(let error):
                        self.installationProgress = "Failed to start: \(error.localizedDescription)"
                    }
                }
                completion(result)
            }
            return
        }
        
        // Install Ollama using official installer
        DispatchQueue.main.async {
            self.installationProgress = "Downloading Ollama installer..."
        }
        
        // For macOS, download and run the official installer
        // Use the official macOS installer URL
        DispatchQueue.main.async {
            self.installationProgress = "Opening Ollama installer..."
        }
        
        // Open the official Ollama download page
        if let url = URL(string: "https://ollama.com/download/Ollama-darwin.zip") {
            NSWorkspace.shared.open(url)
            DispatchQueue.main.async {
                self.installationProgress = "Please follow the installer instructions. After installation, Ollama will start automatically."
            }
            // Check status after a delay to see if installation completed
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.checkOllamaStatus()
                if self.isOllamaRunning {
                    self.isInstallingOllama = false
                    self.installationProgress = "Ollama installed and running!"
                    completion(.success(()))
                } else {
                    // Alternative: Try using Homebrew if available
                    self.tryHomebrewInstall(completion: completion)
                }
            }
            return
        }
        
        // Fallback: Try Homebrew installation
        tryHomebrewInstall(completion: completion)
    }
    
    /// Try installing via Homebrew (if available)
    private func tryHomebrewInstall(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async {
            self.installationProgress = "Trying Homebrew installation..."
        }
        
        // Check if Homebrew is available
        let checkBrewScript = "which brew"
        executeShellScript(checkBrewScript) { [weak self] brewResult in
            guard let self = self else {
                completion(.failure(NSError(domain: "LocalOnlyService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch brewResult {
            case .success:
                // Homebrew is available, use it to install Ollama
                DispatchQueue.main.async {
                    self.installationProgress = "Installing via Homebrew..."
                }
                let installScript = "brew install ollama"
                self.executeShellScript(installScript) { installResult in
                    DispatchQueue.main.async {
                        switch installResult {
                        case .success:
                            self.installationProgress = "Starting Ollama service..."
                            self.startOllamaService { startResult in
                                DispatchQueue.main.async {
                                    self.isInstallingOllama = false
                                    switch startResult {
                                    case .success:
                                        self.installationProgress = "Ollama installed and running!"
                                    case .failure(let error):
                                        self.installationProgress = "Installed but failed to start: \(error.localizedDescription)"
                                    }
                                }
                                completion(startResult)
                            }
                        case .failure(let error):
                            self.isInstallingOllama = false
                            self.installationProgress = "Homebrew installation failed. Please install Ollama manually from https://ollama.com"
                            completion(.failure(error))
                        }
                    }
                }
            case .failure:
                // Homebrew not available, provide manual instructions
                DispatchQueue.main.async {
                    self.isInstallingOllama = false
                    self.installationProgress = "Please install Ollama manually:\n1. Visit https://ollama.com/download\n2. Download and run the installer\n3. Restart LingCode"
                }
                completion(.failure(NSError(domain: "LocalOnlyService", code: 12, userInfo: [NSLocalizedDescriptionKey: "Homebrew not available. Please install Ollama manually."])))
            }
        }
    }
    
    
    /// Start Ollama service
    private func startOllamaService(completion: @escaping (Result<Void, Error>) -> Void) {
        let script = "ollama serve &"
        executeShellScript(script) { result in
            // Wait a moment for service to start
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.checkOllamaStatus()
                if self.isOllamaRunning {
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(domain: "LocalOnlyService", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to start Ollama service"])))
                }
            }
        }
    }
    
    /// Pull models programmatically
    func pullModels(models: [String] = ["deepseek-coder:6.7b", "qwen2.5-coder:7b", "phi3:mini"], completion: @escaping (Result<Void, Error>) -> Void) {
        guard isOllamaRunning else {
            completion(.failure(NSError(domain: "LocalOnlyService", code: 9, userInfo: [NSLocalizedDescriptionKey: "Ollama is not running. Please install and start Ollama first."])))
            return
        }
        
        DispatchQueue.main.async {
            self.isPullingModels = true
            self.modelPullProgress = [:]
        }
        
        // Pull models sequentially
        pullModelRecursive(models: models, index: 0) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isPullingModels = false
            }
            completion(result)
        }
    }
    
    /// Recursively pull models one by one
    private func pullModelRecursive(models: [String], index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < models.count else {
            completion(.success(()))
            return
        }
        
        let model = models[index]
        DispatchQueue.main.async {
            self.modelPullProgress[model] = "Pulling \(model)..."
        }
        
        pullSingleModel(model: model) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "LocalOnlyService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.modelPullProgress[model] = "✅ \(model) ready"
                }
                // Continue with next model
                self.pullModelRecursive(models: models, index: index + 1, completion: completion)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.modelPullProgress[model] = "❌ Failed: \(error.localizedDescription)"
                }
                // Continue anyway (some models might fail, but others might succeed)
                self.pullModelRecursive(models: models, index: index + 1, completion: completion)
            }
        }
    }
    
    /// Pull a single model using Ollama API
    private func pullSingleModel(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "http://localhost:11434/api/pull")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600.0 // 10 minutes for large models
        
        let body: [String: Any] = [
            "name": model
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Use streaming to track progress
        class PullDelegate: NSObject, URLSessionDataDelegate {
            var onProgress: (String) -> Void
            var onComplete: (Result<Void, Error>) -> Void
            var buffer = Data()
            
            init(onProgress: @escaping (String) -> Void, onComplete: @escaping (Result<Void, Error>) -> Void) {
                self.onProgress = onProgress
                self.onComplete = onComplete
            }
            
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                buffer.append(data)
                
                // Parse progress updates (Ollama sends JSON lines)
                let string = String(data: buffer, encoding: .utf8) ?? ""
                let lines = string.components(separatedBy: .newlines)
                buffer = Data((lines.last ?? "").utf8)
                
                for line in lines.dropLast() {
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        continue
                    }
                    
                    if let status = json["status"] as? String {
                        DispatchQueue.main.async {
                            self.onProgress(status)
                        }
                    }
                    
                    if let done = json["completed"] as? Int,
                       let total = json["total"] as? Int {
                        let percent = Int((Double(done) / Double(total)) * 100)
                        DispatchQueue.main.async {
                            self.onProgress("Downloading: \(percent)%")
                        }
                    }
                }
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error = error {
                    self.onComplete(.failure(error))
                } else {
                    self.onComplete(.success(()))
                }
            }
        }
        
        let delegate = PullDelegate(
            onProgress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.modelPullProgress[model] = progress
                }
            },
            onComplete: completion
        )
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        
        // Retain delegate
        objc_setAssociatedObject(task, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// Execute shell script
    private func executeShellScript(_ script: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                completion(.success(()))
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                completion(.failure(NSError(domain: "LocalOnlyService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    /// Detect Ollama models (silently fails if Ollama isn't running)
    private func detectOllamaModels() {
        let ollamaURL = URL(string: "http://localhost:11434/api/tags")!
        
        // Capture local mode state to avoid closure capture issues
        let shouldLogErrors = isLocalModeEnabled
        
        // Use a semaphore to make this synchronous
        let semaphore = DispatchSemaphore(value: 0)
        var detectedModels: [LocalModelInfo] = []
        
        let task = URLSession.shared.dataTask(with: ollamaURL) { data, response, error in
            defer { semaphore.signal() }
            
            // Silently handle connection errors (Ollama not running is expected)
            if let error = error {
                // Only log if local mode is enabled (user expects it to work)
                if shouldLogErrors {
                    let nsError = error as NSError
                    if nsError.code != NSURLErrorCannotConnectToHost && nsError.code != -1021 {
                        print("⚠️ Ollama detection error: \(error.localizedDescription)")
                    }
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                // Only log if local mode is enabled
                if shouldLogErrors {
                    print("⚠️ Ollama not detected or not running")
                }
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
        
        // Wait up to 1 second for response (shorter timeout to avoid delays)
        if semaphore.wait(timeout: .now() + 1) == .timedOut {
            // Silently timeout - Ollama probably not running
        } else {
            // Update on main thread to avoid publishing warnings
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.availableLocalModels = detectedModels
                if !detectedModels.isEmpty {
                    print("✅ Detected \(detectedModels.count) Ollama model(s): \(detectedModels.map { $0.name }.joined(separator: ", "))")
                }
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

