//
//  AIResponseState.swift
//  LingCode
//
//  Tracks AI response state for strict completion validation
//  CORE INVARIANT: IDE must NEVER show "Response Complete" unless all conditions are met
//

import Foundation

/// State of an AI response
/// Used to enforce strict completion validation
public enum AIResponseState: Equatable {
    /// Request in progress
    case streaming
    
    /// Request succeeded with valid response
    case success
    
    /// Network failure (non-2xx HTTP response)
    case networkFailure(reason: String, statusCode: Int?)
    
    /// Empty response body
    case emptyResponse
    
    /// Parse failure (response received but couldn't parse)
    case parseFailure(reason: String)
    
    /// No-op result (response parsed but no edits/proposals generated)
    case noOpResult(reason: String)
    
    /// Request cancelled
    case cancelled
    
    /// Unknown error
    case error(String)
    
    /// Check if response is in a valid completion state
    /// CORE INVARIANT: Only true if ALL conditions are met:
    /// 1. HTTP 2xx response
    /// 2. Non-empty response body
    /// 3. At least one parsed edit/proposal
    /// 4. At least one change applied OR explicitly proposed
    public var isValidCompletion: Bool {
        switch self {
        case .success:
            return true
        case .streaming, .networkFailure, .emptyResponse, .parseFailure, .noOpResult, .cancelled, .error:
            return false
        }
    }
    
    /// Check if response is in a failure state
    public var isFailure: Bool {
        switch self {
        case .networkFailure, .emptyResponse, .parseFailure, .noOpResult, .error:
            return true
        case .streaming, .success, .cancelled:
            return false
        }
    }
    
    /// Get user-visible error message
    public var errorMessage: String? {
        switch self {
        case .networkFailure(let reason, _):
            return reason
        case .emptyResponse:
            return "AI service returned an empty response. Please retry."
        case .parseFailure(let reason):
            return "Failed to parse AI response: \(reason)"
        case .noOpResult(let reason):
            return reason
        case .error(let message):
            return message
        case .streaming, .success, .cancelled:
            return nil
        }
    }
    
    /// Get failure category for telemetry
    public var failureCategory: String? {
        switch self {
        case .networkFailure:
            return "network_failure"
        case .emptyResponse:
            return "empty_response"
        case .parseFailure:
            return "parse_failure"
        case .noOpResult:
            return "no_op_result"
        case .error:
            return "unknown_error"
        case .streaming, .success, .cancelled:
            return nil
        }
    }
}

/// Telemetry event for AI response handling
public struct AIResponseTelemetry: Equatable {
    public let timestamp: Date
    public let state: AIResponseState
    public let responseLength: Int
    public let parsedEditsCount: Int
    public let parsedProposalsCount: Int
    public let httpStatusCode: Int?
    public let failureCategory: String?
    
    public init(
        state: AIResponseState,
        responseLength: Int = 0,
        parsedEditsCount: Int = 0,
        parsedProposalsCount: Int = 0,
        httpStatusCode: Int? = nil
    ) {
        self.timestamp = Date()
        self.state = state
        self.responseLength = responseLength
        self.parsedEditsCount = parsedEditsCount
        self.parsedProposalsCount = parsedProposalsCount
        self.httpStatusCode = httpStatusCode
        self.failureCategory = state.failureCategory
    }
}
