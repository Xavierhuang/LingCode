//
//  ServiceContainer.swift
//  LingCode
//
//  Dependency Injection Container
//  Replaces singleton pattern for better testability
//

import Foundation

/// Service container for dependency injection
/// Allows services to be injected rather than accessed as singletons
@MainActor
class ServiceContainer {
    static let shared = ServiceContainer()
    
    // AI Services
    private(set) var aiService: AIProviderProtocol
    private(set) var modernAIService: ModernAIService
    
    private init() {
        // Initialize services (can be replaced with mocks for testing)
        modernAIService = ModernAIService()
        aiService = modernAIService // Use modern implementation by default
    }
    
    /// Replace AI service (useful for testing or local models)
    func replaceAIService(_ service: AIProviderProtocol) {
        aiService = service
    }
}

/// Convenience accessors (backward compatibility during migration)
extension ServiceContainer {
    var ai: AIProviderProtocol { aiService }
    
    // Access to existing singleton services (for gradual migration)
    var context: ContextRankingService { ContextRankingService.shared }
    var search: SemanticSearchService { SemanticSearchService.shared }
    var latency: PerformanceOptimizer { PerformanceOptimizer.shared }
    var performance: PerformanceOptimizer { PerformanceOptimizer.shared }
    var streaming: StreamingUpdateCoordinator { StreamingUpdateCoordinator.shared }
    var editIntent: EditIntentCoordinator { EditIntentCoordinator.shared }
    var agentCoordinator: AgentCoordinator { AgentCoordinator.shared }
}
