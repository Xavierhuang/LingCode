//
//  LatencyOptimizer.swift
//  LingCode
//
//  Latency optimizations: precomputation, speculative context, dual-model, stream parsing, aggressive cancellation
//

import Foundation
import Combine

actor ASTCache {
    var cache: [URL: [SymbolLocation]] = [:]
    var tokenCounts: [URL: Int] = [:]
    var importGraphs: [URL: Set<URL>] = [:]
    
    func getSymbols(for fileURL: URL) -> [SymbolLocation]? {
        return cache[fileURL]
    }
    
    func setSymbols(_ symbols: [SymbolLocation], for fileURL: URL) {
        cache[fileURL] = symbols
    }
    
    func getTokenCount(for fileURL: URL) -> Int? {
        return tokenCounts[fileURL]
    }
    
    func setTokenCount(_ count: Int, for fileURL: URL) {
        tokenCounts[fileURL] = count
    }
    
    func getImportGraph(for fileURL: URL) -> Set<URL>? {
        return importGraphs[fileURL]
    }
    
    func setImportGraph(_ graph: Set<URL>, for fileURL: URL) {
        importGraphs[fileURL] = graph
    }
    
    func invalidate(for fileURL: URL) {
        cache.removeValue(forKey: fileURL)
        tokenCounts.removeValue(forKey: fileURL)
        importGraphs.removeValue(forKey: fileURL)
    }
}

class LatencyOptimizer {
    static let shared = LatencyOptimizer()
    
    private let astCache = ASTCache()
    private var speculativeContext: String? = nil
    private var speculativeContextTask: Task<Void, Never>? = nil
    private var speculativeContextStartTime: Date? = nil // Track when speculation started
    private var currentRequest: URLSessionTask? = nil
    
    private init() {}
    
    // MARK: - Precomputation
    
    /// Precompute AST, token counts, and import graphs for a file
    func precompute(for fileURL: URL, projectURL: URL) async {
        // Precompute AST
        let symbols = ASTAnchorService.shared.getSymbols(for: fileURL)
        await astCache.setSymbols(symbols, for: fileURL)
        
        // Precompute token count
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            let tokens = TokenBudgetOptimizer.shared.estimateTokens(content)
            await astCache.setTokenCount(tokens, for: fileURL)
        }
        
        // Precompute import graph
        let imports = FileDependencyService.shared.findImportedFiles(for: fileURL, in: projectURL)
        await astCache.setImportGraph(Set(imports), for: fileURL)
    }
    
    /// Precompute for all files in project
    func precomputeProject(_ projectURL: URL) async {
        // Use non-blocking file enumeration for Swift 6 async compatibility
        // Collect all file URLs first in a synchronous context, then process async
        var fileURLs: [URL] = []
        
        // Use a synchronous block to collect URLs (avoiding makeIterator in async context)
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        guard let enumerator = enumerator else { return }
        
        // Collect all file URLs synchronously before async processing
        // This avoids the makeIterator issue in Swift 6
        while let item = enumerator.nextObject() as? URL {
            guard !item.hasDirectoryPath else { continue }
            fileURLs.append(item)
        }
        
        // Process files asynchronously
        for fileURL in fileURLs {
            await precompute(for: fileURL, projectURL: projectURL)
        }
    }
    
    // MARK: - Speculative Context
    
    /// Start building context speculatively (on pause, cursor stop, selection change)
    func startSpeculativeContext(
        activeFile: URL?,
        selectedText: String?,
        projectURL: URL?,
        query: String?,
        onComplete: (() -> Void)? = nil
    ) {
        // Cancel previous speculative task
        speculativeContextTask?.cancel()
        
        // CRITICAL FIX: Track when speculation starts
        speculativeContextStartTime = Date()
        
        speculativeContextTask = Task {
            // Build context in background
            let context = await buildContextSpeculatively(
                activeFile: activeFile,
                selectedText: selectedText,
                projectURL: projectURL,
                query: query
            )
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.speculativeContext = context
                    self.speculativeContextStartTime = nil // Clear start time when done
                    onComplete?() // Notify completion (e.g., to clear isSpeculating flag)
                }
            }
        }
    }
    
    private func buildContextSpeculatively(
        activeFile: URL?,
        selectedText: String?,
        projectURL: URL?,
        query: String?
    ) async -> String {
        // This runs in the background while user is typing!
        // Use ContextRankingService for comprehensive context (includes semantic search, imports, etc.)
        // This is equivalent to what CursorContextBuilder does, but runs speculatively
        
        // Build context using ContextRankingService (thread-safe, can run in background)
        // ContextRankingService already includes:
        // - Active file content
        // - Selected text
        // - Semantic search results (if query provided)
        // - Imported files
        // - Related files
        // - Recent files
        // - Tests and interfaces
        let context = await ContextRankingService.shared.buildContext(
            activeFile: activeFile,
            selectedRange: selectedText,
            diagnostics: nil, // Diagnostics can be fetched if needed, but skip for speed
            projectURL: projectURL,
            query: query ?? "",
            tokenLimit: 8000
        )
        
        return context
    }
    
    /// Get speculative context if available
    /// CRITICAL FIX: Wait briefly for in-progress speculation if it's fresh enough to avoid race condition
    func getSpeculativeContext() -> String? {
        // If context is already ready, return it
        if let context = speculativeContext {
            return context
        }
        
        // CRITICAL FIX: If speculation is in progress and started recently, wait briefly for it
        // This prevents discarding 90% complete context for a cold start
        if let task = speculativeContextTask, 
           !task.isCancelled,
           let startTime = speculativeContextStartTime,
           Date().timeIntervalSince(startTime) < 1.5 { // Started within last 1.5 seconds
            
            // Wait synchronously for up to 300ms for the task to complete
            // This is a compromise - we don't want to block too long, but we want to use almost-ready context
            let startWait = Date()
            while Date().timeIntervalSince(startWait) < 0.3 { // Wait up to 300ms
                // Check if context is now available
                if let context = speculativeContext {
                    return context
                }
                
                // Check if task completed
                if task.isCancelled {
                    break
                }
                
                // Small delay to avoid busy-waiting
                Thread.sleep(forTimeInterval: 0.01) // 10ms
            }
            
            // Final check after wait
            if let context = speculativeContext {
                return context
            }
        }
        
        return speculativeContext
    }
    
    /// Clear speculative context
    func clearSpeculativeContext() {
        speculativeContext = nil
        speculativeContextTask?.cancel()
    }
    
    // MARK: - Stream Parsing
    
    /// Parse edits from streaming response (start as soon as JSON detected)
    func parseEditsFromStream(_ stream: String) -> [Edit]? {
        // Check if we have the start of JSON edits
        if stream.contains("\"edits\"") {
            // Try to parse what we have so far
            if let edits = JSONEditSchemaService.shared.parseEdits(from: stream) {
                return edits
            }
            
            // If not complete, wait for more
            return nil
        }
        
        return nil
    }
    
    // MARK: - Aggressive Cancellation
    
    /// Cancel current request if user types again
    func cancelIfUserTyped() {
        currentRequest?.cancel()
        currentRequest = nil
        clearSpeculativeContext()
    }
    
    /// Set current request for cancellation tracking
    func setCurrentRequest(_ request: URLSessionTask) {
        currentRequest = request
    }
    
    // MARK: - Latency Budget Tracking
    
    struct LatencyMetrics {
        var contextBuild: TimeInterval = 0
        var modelRouting: TimeInterval = 0
        var llmLatency: TimeInterval = 0
        var patchApply: TimeInterval = 0
        
        var total: TimeInterval {
            contextBuild + modelRouting + llmLatency + patchApply
        }
        
        var meetsTarget: Bool {
            contextBuild < 0.015 && // <15ms
            modelRouting < 0.002 && // <2ms
            llmLatency < 0.3 && // <300ms
            patchApply < 0.01 && // <10ms
            total < 0.35 // <350ms
        }
    }
    
    private var metrics = LatencyMetrics()
    
    func recordContextBuild(_ time: TimeInterval) {
        metrics.contextBuild = time
    }
    
    func recordModelRouting(_ time: TimeInterval) {
        metrics.modelRouting = time
    }
    
    func recordLLMLatency(_ time: TimeInterval) {
        metrics.llmLatency = time
    }
    
    func recordPatchApply(_ time: TimeInterval) {
        metrics.patchApply = time
    }
    
    func getMetrics() -> LatencyMetrics {
        return metrics
    }
}

// MARK: - Dual-Model Strategy

extension LatencyOptimizer {
    /// Use local model for validation/retry before cloud
    func validateWithLocalModel(_ edits: [Edit]) async -> Bool {
        // Placeholder: would use local model (DeepSeek, StarCoder2, etc.)
        // For now, just validate structure
        return !edits.isEmpty
    }
    
    /// Retry with local model before cloud
    func retryWithLocalModel(
        failedEdits: [Edit],
        error: Error
    ) async -> [Edit]? {
        // Placeholder: would use local model to fix edits
        // For now, return nil to fall back to cloud
        return nil
    }
}
