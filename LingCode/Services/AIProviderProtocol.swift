//
//  AIProviderProtocol.swift
//  LingCode
//
//  Modern async/await protocol for AI providers
//  Replaces singleton pattern with dependency injection
//

import Foundation

/// Protocol for AI providers - enables dependency injection and testing
protocol AIProviderProtocol {
    /// Stream a message and return chunks asynchronously
    /// FIX: Added tools parameter for agent capabilities
    /// FIX: Added forceToolName to force a specific tool when agent is stuck
    func streamMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        maxTokens: Int?,
        systemPrompt: String?,
        tools: [AITool]?,
        forceToolName: String?
    ) -> AsyncThrowingStream<String, Error>
    
    /// Send a non-streaming message
    func sendMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        tools: [AITool]?
    ) async throws -> String
    
    /// Get the last HTTP status code from the most recent request
    var lastHTTPStatusCode: Int? { get }
    
    /// Cancel the current request
    func cancelCurrentRequest()
    
    /// API key (nil if not set)
    func getAPIKey() -> String?
    /// Set API key and provider
    func setAPIKey(_ key: String, provider: AIProvider)
    /// Current provider (e.g. anthropic, openAI)
    func getProvider() -> AIProvider
    /// Current Anthropic model (for display/settings)
    func getAnthropicModel() -> AnthropicModel
    /// Current model identifier for telemetry
    var currentModel: String { get }
}

/// Modern async/await error types
enum AIError: Error, LocalizedError {
    case apiKeyNotSet
    case networkError(Error)
    case serverError(Int, String?)
    case invalidResponse
    case cancelled
    case emptyResponse
    case rateLimitExceeded
    case timeout // FIX: Added for TTFT timeout
    case modelNotFound // FIX: Added for future date model crash
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotSet:
            return "API key not set"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return message ?? "Server error: HTTP \(code)"
        case .invalidResponse:
            return "Invalid response format"
        case .cancelled:
            return "Request cancelled"
        case .emptyResponse:
            return "Empty response received"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .timeout:
            return "Request timed out. The AI service is taking too long to respond. Try again or use a simpler request."
        case .modelNotFound:
            return "Model not found or not yet available"
        }
    }
}
