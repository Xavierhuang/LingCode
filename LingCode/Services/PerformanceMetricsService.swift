//
//  PerformanceMetricsService.swift
//  LingCode
//
//  Tracks performance metrics: token usage, costs, latency, etc.
//

import Foundation
import Combine

struct PerformanceMetrics: Identifiable {
    let id = UUID()
    let timestamp: Date
    let requestType: String
    let model: String?
    let tokenCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let latency: TimeInterval
    let contextBuildTime: TimeInterval
    let cost: Double?
    let success: Bool
}

@MainActor
class PerformanceMetricsService: ObservableObject {
    static let shared = PerformanceMetricsService()
    
    @Published var metrics: [PerformanceMetrics] = []
    @Published var totalTokenUsage: Int = 0
    @Published var totalCost: Double = 0.0
    @Published var averageLatency: TimeInterval = 0.0
    @Published var successRate: Double = 1.0
    
    // Token costs per 1K tokens (approximate)
    private let tokenCosts: [String: (input: Double, output: Double)] = [
        "gpt-4o": (0.0025, 0.010),
        "gpt-4o-mini": (0.00015, 0.0006),
        "gpt-4-turbo": (0.01, 0.03),
        "claude-3-5-sonnet": (0.003, 0.015),
        "claude-3-opus": (0.015, 0.075),
        "claude-3-haiku": (0.00025, 0.00125)
    ]
    
    private init() {}
    
    /// Record a performance metric
    func recordMetric(
        requestType: String,
        model: String?,
        inputTokens: Int,
        outputTokens: Int,
        latency: TimeInterval,
        contextBuildTime: TimeInterval,
        success: Bool
    ) {
        let tokenCount = inputTokens + outputTokens
        let cost = calculateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
        
        let metric = PerformanceMetrics(
            timestamp: Date(),
            requestType: requestType,
            model: model,
            tokenCount: tokenCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            latency: latency,
            contextBuildTime: contextBuildTime,
            cost: cost,
            success: success
        )
        
        metrics.append(metric)
        totalTokenUsage += tokenCount
        if let cost = cost {
            totalCost += cost
        }
        
        updateAverages()
    }
    
    /// Calculate cost based on model and tokens
    private func calculateCost(model: String?, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let model = model,
              let costs = tokenCosts[model] else {
            return nil
        }
        
        let inputCost = (Double(inputTokens) / 1000.0) * costs.input
        let outputCost = (Double(outputTokens) / 1000.0) * costs.output
        return inputCost + outputCost
    }
    
    /// Update average metrics
    private func updateAverages() {
        guard !metrics.isEmpty else { return }
        
        let totalLatency = metrics.reduce(0.0) { $0 + $1.latency }
        averageLatency = totalLatency / Double(metrics.count)
        
        let successful = metrics.filter { $0.success }.count
        successRate = Double(successful) / Double(metrics.count)
    }
    
    /// Get metrics for time period
    func getMetrics(since: Date) -> [PerformanceMetrics] {
        return metrics.filter { $0.timestamp >= since }
    }
    
    /// Clear old metrics (keep last 100)
    func clearOldMetrics() {
        if metrics.count > 100 {
            metrics.removeFirst(metrics.count - 100)
        }
    }
    
    /// Get cost estimate for model
    func getCostEstimate(model: String?, inputTokens: Int, outputTokens: Int) -> Double? {
        return calculateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}
