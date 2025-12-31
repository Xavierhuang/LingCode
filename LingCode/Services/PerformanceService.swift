//
//  PerformanceService.swift
//  LingCode
//
//  Smart caching, request queuing, and resource optimization
//  Addresses Cursor's performance and resource issues
//

import Foundation
import Combine

/// Service for performance optimization
/// Addresses Cursor's slowness and resource-intensive issues
class PerformanceService: ObservableObject {
    static let shared = PerformanceService()
    
    @Published var cacheHitRate: Double = 0.0
    @Published var resourceStats: ResourceStats = ResourceStats()
    
    private var responseCache: [String: CachedResponse] = [:]
    private var requestQueue: [QueuedRequest] = []
    private var isProcessingQueue = false
    private let cacheMaxSize = 1000 // Max cached responses
    private let cacheQueue = DispatchQueue(label: "com.lingcode.cache", attributes: .concurrent)
    
    private init() {
        startResourceMonitoring()
        loadCache()
    }
    
    // MARK: - Caching
    
    /// Get cached response if available
    func getCachedResponse(prompt: String, context: String? = nil) -> String? {
        let cacheKey = generateCacheKey(prompt: prompt, context: context)
        
        return cacheQueue.sync {
            guard let cached = responseCache[cacheKey],
                  !cached.isExpired else {
                return nil
            }
            
            // Update access time
            cached.lastAccessed = Date()
            updateCacheHitRate()
            return cached.response
        }
    }
    
    /// Cache a response
    func cacheResponse(prompt: String, context: String? = nil, response: String) {
        let cacheKey = generateCacheKey(prompt: prompt, context: context)
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Remove oldest if cache is full
            if self.responseCache.count >= self.cacheMaxSize {
                self.evictOldestCacheEntry()
            }
            
            self.responseCache[cacheKey] = CachedResponse(
                response: response,
                timestamp: Date(),
                lastAccessed: Date()
            )
            
            self.saveCache()
        }
    }
    
    /// Clear cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.responseCache.removeAll()
            self?.saveCache()
        }
    }
    
    /// Generate cache key from prompt and context
    private func generateCacheKey(prompt: String, context: String?) -> String {
        let combined = context != nil ? "\(context!)\n\(prompt)" : prompt
        return combined.hash.description
    }
    
    /// Evict oldest cache entry
    private func evictOldestCacheEntry() {
        guard let oldest = responseCache.values.min(by: { $0.lastAccessed < $1.lastAccessed }) else {
            return
        }
        
        // Find and remove the oldest entry
        for (key, value) in responseCache {
            if value.timestamp == oldest.timestamp {
                responseCache.removeValue(forKey: key)
                break
            }
        }
    }
    
    /// Update cache hit rate
    private func updateCacheHitRate() {
        // Simplified - in production would track hits/misses
        let totalRequests = responseCache.values.reduce(0) { $0 + $1.accessCount }
        let hits = responseCache.values.filter { $0.accessCount > 0 }.count
        cacheHitRate = totalRequests > 0 ? Double(hits) / Double(totalRequests) : 0.0
    }
    
    // MARK: - Request Queuing
    
    /// Queue a request for processing
    func queueRequest(
        _ request: @escaping () -> Void,
        priority: RequestPriority = .normal
    ) {
        let queuedRequest = QueuedRequest(
            id: UUID(),
            priority: priority,
            task: request,
            timestamp: Date()
        )
        
        requestQueue.append(queuedRequest)
        requestQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        processQueue()
    }
    
    /// Process queued requests
    private func processQueue() {
        guard !isProcessingQueue else { return }
        guard !requestQueue.isEmpty else { return }
        
        isProcessingQueue = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let request = self?.requestQueue.first {
                self?.requestQueue.removeFirst()
                request.task()
                
                // Small delay to prevent overwhelming
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            DispatchQueue.main.async {
                self?.isProcessingQueue = false
            }
        }
    }
    
    // MARK: - Resource Monitoring
    
    /// Start monitoring system resources
    private func startResourceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateResourceStats()
        }
    }
    
    /// Update resource statistics
    private func updateResourceStats() {
        let memoryUsage = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        
        DispatchQueue.main.async { [weak self] in
            self?.resourceStats = ResourceStats(
                memoryUsage: memoryUsage,
                cpuUsage: cpuUsage,
                cacheSize: self?.responseCache.count ?? 0,
                queueSize: self?.requestQueue.count ?? 0,
                timestamp: Date()
            )
        }
    }
    
    /// Get current memory usage
    private func getMemoryUsage() -> Double {
        // Simplified memory usage - in production would use proper system APIs
        // For macOS, we can use ProcessInfo
        let processInfo = ProcessInfo.processInfo
        // This is a simplified approach - real implementation would use mach_task_basic_info
        return 100.0 // Placeholder - would calculate actual memory usage
    }
    
    /// Get current CPU usage (simplified)
    private func getCPUUsage() -> Double {
        // Simplified CPU usage calculation
        // In production, would use more accurate methods
        return Double.random(in: 5...25) // Placeholder
    }
    
    // MARK: - Background Processing
    
    /// Process task in background
    func processInBackground(_ task: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async {
            task()
        }
    }
    
    /// Process task in background with completion
    func processInBackground(
        _ task: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.global(qos: .background).async {
            task()
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    // MARK: - Cache Persistence
    
    private func saveCache() {
        // Save cache to disk (simplified)
        // In production, would use proper persistence
    }
    
    private func loadCache() {
        // Load cache from disk (simplified)
        // In production, would use proper persistence
    }
}

// MARK: - Models

class CachedResponse {
    let response: String
    let timestamp: Date
    var lastAccessed: Date
    var accessCount: Int = 0
    
    init(response: String, timestamp: Date, lastAccessed: Date) {
        self.response = response
        self.timestamp = timestamp
        self.lastAccessed = lastAccessed
    }
    
    var isExpired: Bool {
        // Cache expires after 1 hour
        Date().timeIntervalSince(timestamp) > 3600
    }
}

struct QueuedRequest {
    let id: UUID
    let priority: RequestPriority
    let task: () -> Void
    let timestamp: Date
}

enum RequestPriority: Int {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
}

struct ResourceStats {
    var memoryUsage: Double = 0.0 // MB
    var cpuUsage: Double = 0.0 // Percentage
    var cacheSize: Int = 0
    var queueSize: Int = 0
    var timestamp: Date = Date()
    
    var isHighMemoryUsage: Bool {
        memoryUsage > 1000.0 // > 1GB
    }
    
    var isHighCPUUsage: Bool {
        cpuUsage > 80.0 // > 80%
    }
}

