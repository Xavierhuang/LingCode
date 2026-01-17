//
//  PerformanceOptimizer.swift
//  LingCode
//
//  Battery + Memory Optimization (Mac-specific wins)
//

import Foundation
import IOKit.pwr_mgt

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
            
            // Move to head
            moveToHead(node)
            
            return node.value
        }
    }
    
    func set(_ key: Key, _ value: Value) {
        queue.async(flags: .barrier) {
            if let existingNode = self.cache[key] {
                // Update existing
                existingNode.value = value
                self.moveToHead(existingNode)
            } else {
                // Add new
                let newNode = Node(key: key, value: value)
                self.cache[key] = newNode
                self.addToHead(newNode)
                
                // Evict if over limit
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

// MARK: - Battery + Memory Optimizer

class PerformanceOptimizer {
    static let shared = PerformanceOptimizer()
    
    // LRU Caches
    private let astCache = LRUCache<URL, [ASTSymbol]>(maxSize: 50)
    private let tokenCountCache = LRUCache<URL, Int>(maxSize: 100)
    private let symbolTableCache = LRUCache<URL, [ASTSymbol]>(maxSize: 50)
    
    // Debouncing
    private var typingDebouncer: DispatchWorkItem?
    private var parseDebouncer: DispatchWorkItem?
    
    // Power state
    private var isOnBattery: Bool = false
    private var powerMonitoringTask: Task<Void, Never>?
    
    private init() {
        startPowerMonitoring()
    }
    
    // MARK: - CPU Optimizations
    
    /// Debounce typing events (150ms)
    func debounceTyping(delay: TimeInterval = 0.15, action: @escaping () -> Void) {
        typingDebouncer?.cancel()
        
        let workItem = DispatchWorkItem {
            action()
        }
        
        typingDebouncer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// Debounce AST parsing (no parse per keystroke)
    func debounceParse(delay: TimeInterval = 0.3, action: @escaping () -> Void) {
        parseDebouncer?.cancel()
        
        let workItem = DispatchWorkItem {
            action()
        }
        
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
    
    // MARK: - Memory Optimizations
    
    /// Get AST from cache
    func getAST(for fileURL: URL) -> [ASTSymbol]? {
        return astCache.get(fileURL)
    }
    
    /// Cache AST
    func cacheAST(_ symbols: [ASTSymbol], for fileURL: URL) {
        astCache.set(fileURL, symbols)
    }
    
    /// Get token count from cache
    func getTokenCount(for fileURL: URL) -> Int? {
        return tokenCountCache.get(fileURL)
    }
    
    /// Cache token count
    func cacheTokenCount(_ count: Int, for fileURL: URL) {
        tokenCountCache.set(fileURL, count)
    }
    
    /// Drop context aggressively on memory pressure
    func handleMemoryPressure() {
        // Drop non-active files from caches
        // Keep only active file and recent files
        // This would be called by system memory pressure notifications
        
        // Clear oldest 50% of cache
        // (LRU cache handles this automatically via maxSize)
    }
    
    // MARK: - Network Optimizations
    
    /// Compress prompt with gzip (placeholder - would use Compression framework)
    func compressPrompt(_ prompt: String) -> Data? {
        // Placeholder - would use Compression framework for actual compression
        return prompt.data(using: .utf8)
    }
    
    /// Reuse HTTP/2 connections (handled by URLSession automatically)
    /// Stream + early cancel (handled by streaming implementation)
    
    // MARK: - Power-Saving Mode
    
    /// Start monitoring power state
    private func startPowerMonitoring() {
        powerMonitoringTask = Task {
            while !Task.isCancelled {
                isOnBattery = checkBatteryPower()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            }
        }
    }
    
    /// Check if on battery power
    private func checkBatteryPower() -> Bool {
        // Use IOKit to check power source
        // For now, placeholder
        return false // Would use actual IOKit API
    }
    
    /// Check if power-saving mode is active
    var isPowerSavingMode: Bool {
        return isOnBattery
    }
    
    /// Get optimized settings for power-saving mode
    func getPowerSavingSettings() -> PowerSavingSettings {
        if isPowerSavingMode {
            return PowerSavingSettings(
                disableSpeculativeContext: true,
                useLocalModelsOnly: true,
                reduceAutocompleteFrequency: true,
                autocompleteDelay: 0.3 // Slower autocomplete
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
}

struct PowerSavingSettings {
    let disableSpeculativeContext: Bool
    let useLocalModelsOnly: Bool
    let reduceAutocompleteFrequency: Bool
    let autocompleteDelay: TimeInterval
}

// MARK: - Data Compression Extension

extension Data {
    func compressed(using algorithm: CompressionAlgorithm) -> Data? {
        // Placeholder - would use Compression framework
        return self
    }
}

enum CompressionAlgorithm {
    case zlib
    case lzfse
    case lzma
}
