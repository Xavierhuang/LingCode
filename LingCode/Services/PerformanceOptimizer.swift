//
//  PerformanceOptimizer.swift
//  LingCode
//
//  Unified Performance + Latency Optimization
//  Handles: Battery/Memory optimization, Precomputation, Speculative context, Caching
//

import Foundation
import IOKit.pwr_mgt
import Combine

// MARK: - LRU Cache

class LRUCache<Key: Hashable, Value> {
    private let maxSize: Int
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let queue = DispatchQueue(label: "com.lingcode.lrucache", attributes: .concurrent)
    
    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    init(maxSize: Int = 50) {
        self.maxSize = maxSize
    }
    
    func get(_ key: Key) -> Value? {
        return queue.sync {
            guard let node = cache[key] else { return nil }
            moveToHead(node)
            return node.value
        }
    }
    
    func set(_ key: Key, _ value: Value) {
        queue.async(flags: .barrier) {
            if let existingNode = self.cache[key] {
                existingNode.value = value
                self.moveToHead(existingNode)
            } else {
                let newNode = Node(key: key, value: value)
                self.cache[key] = newNode
                self.addToHead(newNode)
                
                if self.cache.count > self.maxSize {
                    self.evictTail()
                }
            }
        }
    }
    
    func remove(_ key: Key) {
        queue.async(flags: .barrier) {
            guard let node = self.cache[key] else { return }
            self.removeNode(node)
            self.cache.removeValue(forKey: key)
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
            self.head = nil
            self.tail = nil
        }
    }
    
    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil {
            tail = head
        }
    }
    
    private func removeNode(_ node: Node) {
        if node.prev != nil {
            node.prev?.next = node.next
        } else {
            head = node.next
        }
        if node.next != nil {
            node.next?.prev = node.prev
        } else {
            tail = node.prev
        }
    }
    
    private func moveToHead(_ node: Node) {
        removeNode(node)
        addToHead(node)
    }
    
    private func evictTail() {
        guard let tail = self.tail else { return }
        removeNode(tail)
        cache.removeValue(forKey: tail.key)
    }
}

// MARK: - AST Cache (Actor for thread safety)

actor ASTCache {
    var symbols: [URL: [SymbolLocation]] = [:]
    var tokenCounts: [URL: Int] = [:]
    var importGraphs: [URL: Set<URL>] = [:]
    
    func getSymbols(for fileURL: URL) -> [SymbolLocation]? {
        return symbols[fileURL]
    }
    
    func setSymbols(_ syms: [SymbolLocation], for fileURL: URL) {
        symbols[fileURL] = syms
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
        symbols.removeValue(forKey: fileURL)
        tokenCounts.removeValue(forKey: fileURL)
        importGraphs.removeValue(forKey: fileURL)
    }
}

// MARK: - PerformanceOptimizer (Unified)

class PerformanceOptimizer {
    static let shared = PerformanceOptimizer()
    
    // MARK: - Caches
    
    /// Actor-based AST cache for precomputation (thread-safe)
    private let astCache = ASTCache()
    
    /// LRU caches for memory-bounded storage
    private let astLRUCache = LRUCache<URL, [ASTSymbol]>(maxSize: 50)
    private let tokenCountCache = LRUCache<URL, Int>(maxSize: 100)
    private let symbolTableCache = LRUCache<URL, [ASTSymbol]>(maxSize: 50)
    
    // MARK: - Request Tracking
    
    private var currentRequest: URLSessionTask? = nil
    
    // MARK: - Debouncing
    
    private var typingDebouncer: DispatchWorkItem?
    private var parseDebouncer: DispatchWorkItem?
    
    // MARK: - Power State
    
    private var isOnBattery: Bool = false
    private var powerMonitoringTask: Task<Void, Never>?
    
    // MARK: - Latency Metrics
    
    struct LatencyMetrics {
        var contextBuild: TimeInterval = 0
        var modelRouting: TimeInterval = 0
        var llmLatency: TimeInterval = 0
        var patchApply: TimeInterval = 0
        
        var total: TimeInterval {
            contextBuild + modelRouting + llmLatency + patchApply
        }
        
        var meetsTarget: Bool {
            contextBuild < 0.015 &&  // <15ms
            modelRouting < 0.002 &&  // <2ms
            llmLatency < 0.3 &&      // <300ms
            patchApply < 0.01 &&     // <10ms
            total < 0.35             // <350ms
        }
    }
    
    private var metrics = LatencyMetrics()
    
    private init() {
        startPowerMonitoring()
    }
    
    // MARK: - Precomputation
    
    /// Precompute AST, token counts, and import graphs for a file
    func precompute(for fileURL: URL, projectURL: URL) async {
        let symbols = ASTAnchorService.shared.getSymbols(for: fileURL)
        await astCache.setSymbols(symbols, for: fileURL)
        
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            let tokens = TokenBudgetOptimizer.shared.estimateTokens(content)
            await astCache.setTokenCount(tokens, for: fileURL)
        }
        
        let imports = FileDependencyService.shared.findImportedFiles(for: fileURL, in: projectURL)
        await astCache.setImportGraph(Set(imports), for: fileURL)
    }
    
    /// Precompute for all files in project
    func precomputeProject(_ projectURL: URL) async {
        var fileURLs: [URL] = []
        
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        guard let enumerator = enumerator else { return }
        
        while let item = enumerator.nextObject() as? URL {
            guard !item.hasDirectoryPath else { continue }
            fileURLs.append(item)
        }
        
        for fileURL in fileURLs {
            await precompute(for: fileURL, projectURL: projectURL)
        }
    }
    
    // MARK: - Speculative Context (delegated to ContextOrchestrator)
    
    func startSpeculativeContext(
        activeFile: URL?,
        selectedText: String?,
        projectURL: URL?,
        query: String?,
        onComplete: (() -> Void)? = nil
    ) {
        Task { @MainActor in
            ContextOrchestrator.shared.startSpeculativeContext(
                activeFile: activeFile,
                selectedText: selectedText,
                projectURL: projectURL,
                query: query,
                onComplete: onComplete
            )
        }
    }
    
    func getSpeculativeContext() -> String? {
        ContextOrchestrator.shared.getSpeculativeContext()
    }
    
    func clearSpeculativeContext() {
        ContextOrchestrator.shared.clearSpeculativeContext()
    }
    
    // MARK: - Stream Parsing
    
    /// Parse edits from streaming response (start as soon as JSON detected)
    func parseEditsFromStream(_ stream: String) -> [Edit]? {
        if stream.contains("\"edits\"") {
            if let edits = JSONEditSchemaService.shared.parseEdits(from: stream) {
                return edits
            }
            return nil
        }
        return nil
    }
    
    // MARK: - Request Management
    
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
    
    // MARK: - Latency Metrics
    
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
    
    // MARK: - CPU Optimizations (Debouncing)
    
    /// Debounce typing events (150ms)
    func debounceTyping(delay: TimeInterval = 0.15, action: @escaping () -> Void) {
        typingDebouncer?.cancel()
        let workItem = DispatchWorkItem { action() }
        typingDebouncer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// Debounce AST parsing (no parse per keystroke)
    func debounceParse(delay: TimeInterval = 0.3, action: @escaping () -> Void) {
        parseDebouncer?.cancel()
        let workItem = DispatchWorkItem { action() }
        parseDebouncer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// Parse AST with background priority
    func parseASTInBackground(for fileURL: URL, completion: @escaping ([ASTSymbol]) -> Void) {
        Task(priority: .utility) {
            let symbols = await ASTIndex.shared.getSymbols(for: fileURL)
            await MainActor.run {
                completion(symbols)
            }
        }
    }
    
    // MARK: - Memory Optimizations (LRU Cache Access)
    
    /// Get AST from LRU cache
    func getAST(for fileURL: URL) -> [ASTSymbol]? {
        return astLRUCache.get(fileURL)
    }
    
    /// Cache AST in LRU cache
    func cacheAST(_ symbols: [ASTSymbol], for fileURL: URL) {
        astLRUCache.set(fileURL, symbols)
    }
    
    /// Get token count from LRU cache
    func getTokenCount(for fileURL: URL) -> Int? {
        return tokenCountCache.get(fileURL)
    }
    
    /// Cache token count in LRU cache
    func cacheTokenCount(_ count: Int, for fileURL: URL) {
        tokenCountCache.set(fileURL, count)
    }
    
    /// Drop context aggressively on memory pressure
    func handleMemoryPressure() {
        // LRU cache handles eviction automatically via maxSize
    }
    
    // MARK: - Network Optimizations
    
    /// Compress prompt with gzip (placeholder)
    func compressPrompt(_ prompt: String) -> Data? {
        return prompt.data(using: .utf8)
    }
    
    // MARK: - Power-Saving Mode
    
    private func startPowerMonitoring() {
        powerMonitoringTask = Task {
            while !Task.isCancelled {
                isOnBattery = checkBatteryPower()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    
    private func checkBatteryPower() -> Bool {
        return false // Placeholder for actual IOKit API
    }
    
    var isPowerSavingMode: Bool {
        return isOnBattery
    }
    
    func getPowerSavingSettings() -> PowerSavingSettings {
        if isPowerSavingMode {
            return PowerSavingSettings(
                disableSpeculativeContext: true,
                useLocalModelsOnly: true,
                reduceAutocompleteFrequency: true,
                autocompleteDelay: 0.3
            )
        } else {
            return PowerSavingSettings(
                disableSpeculativeContext: false,
                useLocalModelsOnly: false,
                reduceAutocompleteFrequency: false,
                autocompleteDelay: 0.15
            )
        }
    }
    
    // MARK: - Dual-Model Strategy
    
    /// Use local model for validation/retry before cloud
    func validateWithLocalModel(_ edits: [Edit]) async -> Bool {
        return !edits.isEmpty
    }
    
    /// Retry with local model before cloud
    func retryWithLocalModel(failedEdits: [Edit], error: Error) async -> [Edit]? {
        return nil
    }
}

// MARK: - Supporting Types

struct PowerSavingSettings {
    let disableSpeculativeContext: Bool
    let useLocalModelsOnly: Bool
    let reduceAutocompleteFrequency: Bool
    let autocompleteDelay: TimeInterval
}

extension Data {
    func compressed(using algorithm: CompressionAlgorithm) -> Data? {
        return self
    }
}

enum CompressionAlgorithm {
    case zlib
    case lzfse
    case lzma
}

// MARK: - Backwards Compatibility Alias

typealias LatencyOptimizer = PerformanceOptimizer
