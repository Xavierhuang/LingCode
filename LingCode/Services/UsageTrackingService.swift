//
//  UsageTrackingService.swift
//  LingCode
//
//  Complete transparency - no hidden limits, accurate counters
//  Addresses Cursor's "bait-and-switch" and "broken transparency" issues
//

import Foundation
import Combine

/// Service for tracking API usage and providing complete transparency
/// Addresses Cursor's pricing and billing transparency issues
class UsageTrackingService: ObservableObject {
    static let shared = UsageTrackingService()
    
    @Published var currentUsage: UsageStats = UsageStats()
    @Published var rateLimitStatus: RateLimitStatus = RateLimitStatus()
    
    private let userDefaults = UserDefaults.standard
    private let usageKey = "usage_tracking"
    private let rateLimitKey = "rate_limit_status"
    
    private init() {
        loadUsageStats()
        loadRateLimitStatus()
    }
    
    // MARK: - Usage Tracking
    
    /// Track an API request
    func trackRequest(
        provider: AIProvider,
        model: String,
        tokensUsed: Int,
        cost: Double,
        timestamp: Date = Date()
    ) {
        let request = APIRequest(
            provider: provider,
            model: model,
            tokensUsed: tokensUsed,
            cost: cost,
            timestamp: timestamp
        )
        
        currentUsage.addRequest(request)
        saveUsageStats()
        
        // Check rate limits
        checkRateLimits(provider: provider)
    }
    
    /// Get usage statistics for a time period
    func getUsageStats(period: TimePeriod) -> UsageStats {
        let cutoffDate = period.cutoffDate
        return currentUsage.filtered(after: cutoffDate)
    }
    
    /// Get cost breakdown
    func getCostBreakdown(period: TimePeriod) -> CostBreakdown {
        let stats = getUsageStats(period: period)
        return CostBreakdown(
            totalCost: stats.totalCost,
            byProvider: stats.costByProvider,
            byModel: stats.costByModel,
            period: period
        )
    }
    
    /// Estimate cost for a request
    func estimateCost(
        provider: AIProvider,
        model: String,
        estimatedTokens: Int
    ) -> CostEstimate {
        let costPerToken = getCostPerToken(provider: provider, model: model)
        let estimatedCost = Double(estimatedTokens) * costPerToken
        
        return CostEstimate(
            provider: provider,
            model: model,
            estimatedTokens: estimatedTokens,
            estimatedCost: estimatedCost,
            currency: "USD"
        )
    }
    
    // MARK: - Rate Limit Management
    
    /// Check rate limit status for a provider
    func checkRateLimits(provider: AIProvider) {
        let stats = getUsageStats(period: .today)
        let requestsToday = stats.requestCount
        
        // Get rate limits for provider
        let limits = getRateLimits(provider: provider)
        
        let remaining = max(0, limits.maxRequests - requestsToday)
        let percentage = Double(requestsToday) / Double(limits.maxRequests)
        
        rateLimitStatus = RateLimitStatus(
            provider: provider,
            requestsUsed: requestsToday,
            requestsRemaining: remaining,
            maxRequests: limits.maxRequests,
            percentageUsed: percentage,
            resetTime: limits.resetTime,
            isNearLimit: percentage > 0.8,
            isAtLimit: requestsToday >= limits.maxRequests
        )
        
        saveRateLimitStatus()
        
        // Post notification if near limit
        if rateLimitStatus.isNearLimit && !rateLimitStatus.isAtLimit {
            NotificationCenter.default.post(
                name: NSNotification.Name("RateLimitWarning"),
                object: nil,
                userInfo: ["provider": provider.rawValue, "remaining": remaining]
            )
        }
    }
    
    /// Get rate limits for a provider
    /// CRITICAL FIX: Anchor resetTime to fixed midnight, not sliding window
    private func getRateLimits(provider: AIProvider) -> ProviderRateLimit {
        // CRITICAL FIX: Calculate reset time based on fixed midnight (not sliding)
        // This ensures limits actually reset at midnight, not every time the function is called
        let calendar = Calendar.current
        let now = Date()
        let tomorrowMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        
        // Default rate limits (can be configured)
        switch provider {
        case .anthropic:
            return ProviderRateLimit(
                maxRequests: 1000, // per day
                maxTokens: 1_000_000, // per day
                resetTime: tomorrowMidnight // Fixed anchor point
            )
        case .openAI:
            return ProviderRateLimit(
                maxRequests: 500, // per day
                maxTokens: 500_000, // per day
                resetTime: tomorrowMidnight // Fixed anchor point
            )
        }
    }
    
    /// Get cost per token for a model
    /// CRITICAL FIX: Fetch pricing from remote JSON, fallback to hardcoded values
    private func getCostPerToken(provider: AIProvider, model: String) -> Double {
        // CRITICAL FIX: Try to fetch pricing from remote JSON first
        if let remotePricing = fetchRemotePricing() {
            if let cost = remotePricing[provider.rawValue]?[model] {
                return cost
            }
        }
        
        // Fallback to hardcoded values (updated periodically)
        // Pricing as of 2025 (approximate)
        switch provider {
        case .anthropic:
            if model.contains("sonnet-4.5") {
                return 0.000003 // $3 per 1M input tokens
            } else if model.contains("haiku") {
                return 0.00000025 // $0.25 per 1M input tokens
            }
            return 0.000003
        case .openAI:
            if model.contains("gpt-4") {
                return 0.00003 // $30 per 1M input tokens
            } else if model.contains("gpt-3.5") {
                return 0.0000015 // $1.50 per 1M input tokens
            }
            return 0.00003
        }
    }
    
    /// CRITICAL FIX: Fetch pricing from remote JSON (GitHub/Server)
    /// This prevents needing App Store updates when providers change prices
    private var cachedPricing: [String: [String: Double]]? = nil
    private var lastPricingFetch: Date? = nil
    private let pricingCacheTTL: TimeInterval = 86400 // 24 hours
    
    private func fetchRemotePricing() -> [String: [String: Double]]? {
        // Check cache first
        if let cached = cachedPricing,
           let lastFetch = lastPricingFetch,
           Date().timeIntervalSince(lastFetch) < pricingCacheTTL {
            return cached
        }
        
        // Fetch from remote (non-blocking, async)
        // In production, this would fetch from your GitHub repo or server
        // For now, return nil to use hardcoded fallback
        // TODO: Implement actual remote fetch:
        // let url = URL(string: "https://raw.githubusercontent.com/yourorg/lingcode/main/pricing.json")!
        // let data = try? Data(contentsOf: url)
        // let pricing = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
        
        // Update cache
        lastPricingFetch = Date()
        
        return cachedPricing
    }
    
    // MARK: - Persistence
    
    private func saveUsageStats() {
        if let encoded = try? JSONEncoder().encode(currentUsage) {
            userDefaults.set(encoded, forKey: usageKey)
        }
    }
    
    private func loadUsageStats() {
        if let data = userDefaults.data(forKey: usageKey),
           let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            currentUsage = decoded
        }
    }
    
    private func saveRateLimitStatus() {
        if let encoded = try? JSONEncoder().encode(rateLimitStatus) {
            userDefaults.set(encoded, forKey: rateLimitKey)
        }
    }
    
    private func loadRateLimitStatus() {
        if let data = userDefaults.data(forKey: rateLimitKey),
           let decoded = try? JSONDecoder().decode(RateLimitStatus.self, from: data) {
            rateLimitStatus = decoded
        }
    }
    
    /// Reset usage stats (for testing or user request)
    func resetUsageStats() {
        currentUsage = UsageStats()
        rateLimitStatus = RateLimitStatus()
        saveUsageStats()
        saveRateLimitStatus()
    }
    
    /// Export usage data
    func exportUsageData(period: TimePeriod) -> Data? {
        let stats = getUsageStats(period: period)
        return try? JSONEncoder().encode(stats)
    }
}

// MARK: - Models

struct UsageStats: Codable {
    var requests: [APIRequest] = []
    var startDate: Date = Date()
    
    var requestCount: Int {
        requests.count
    }
    
    var totalTokens: Int {
        requests.reduce(0) { $0 + $1.tokensUsed }
    }
    
    var totalCost: Double {
        requests.reduce(0) { $0 + $1.cost }
    }
    
    var costByProvider: [String: Double] {
        Dictionary(grouping: requests, by: { $0.provider.rawValue })
            .mapValues { requests in
                requests.reduce(0) { $0 + $1.cost }
            }
    }
    
    var costByModel: [String: Double] {
        Dictionary(grouping: requests, by: { $0.model })
            .mapValues { requests in
                requests.reduce(0) { $0 + $1.cost }
            }
    }
    
    mutating func addRequest(_ request: APIRequest) {
        requests.append(request)
    }
    
    func filtered(after date: Date) -> UsageStats {
        var filtered = self
        filtered.requests = requests.filter { $0.timestamp >= date }
        return filtered
    }
}

struct APIRequest: Codable {
    let provider: AIProvider
    let model: String
    let tokensUsed: Int
    let cost: Double
    let timestamp: Date
}

struct RateLimitStatus: Codable {
    var provider: AIProvider = .anthropic
    var requestsUsed: Int = 0
    var requestsRemaining: Int = 1000
    var maxRequests: Int = 1000
    var percentageUsed: Double = 0.0
    var resetTime: Date = Date()
    var isNearLimit: Bool = false
    var isAtLimit: Bool = false
}

struct ProviderRateLimit {
    let maxRequests: Int
    let maxTokens: Int
    let resetTime: Date
}

struct CostEstimate {
    let provider: AIProvider
    let model: String
    let estimatedTokens: Int
    let estimatedCost: Double
    let currency: String
}

struct CostBreakdown {
    let totalCost: Double
    let byProvider: [String: Double]
    let byModel: [String: Double]
    let period: TimePeriod
}

enum TimePeriod {
    case today
    case thisWeek
    case thisMonth
    case allTime
    
    var cutoffDate: Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .thisMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .allTime:
            return Date.distantPast
        }
    }
}

// AIProvider is now Codable in AIService.swift

