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
    func streamMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage],
        maxTokens: Int?,
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error>
    
    /// Send a non-streaming message
    func sendMessage(
        _ message: String,
        context: String?,
        images: [AttachedImage]
    ) async throws -> String
    
    /// Get the last HTTP status code from the most recent request
    var lastHTTPStatusCode: Int? { get }
    
    /// Cancel the current request
    func cancelCurrentRequest()
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
        }
    }
}
