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
    
    private init() {
        aiService = AIService.shared
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
    var context: ContextOrchestrator { ContextOrchestrator.shared }
    var search: SemanticSearchService { SemanticSearchService.shared }
    var latency: PerformanceOptimizer { PerformanceOptimizer.shared }
    var performance: PerformanceOptimizer { PerformanceOptimizer.shared }
    var streaming: StreamingUpdateCoordinator { StreamingUpdateCoordinator.shared }
    var editSessionOrchestrator: EditSessionOrchestrator { EditSessionOrchestrator.shared }
    var agentCoordinator: AgentCoordinator { AgentCoordinator.shared }
}
