//
//  AgentConfiguration.swift
//  LingCode
//
//  Centralized configuration for agent and context limits
//  Replaces hardcoded "magic numbers" throughout the codebase
//

import Foundation

/// Centralized configuration for agent behavior and limits
struct AgentConfiguration {
    /// Maximum iterations for agent loop
    static let maxIterations = 20
    
    /// Smart window context limit (lines)
    static let smartWindowLineLimit = 300
    
    /// Context window padding (lines before/after)
    static let contextWindowPadding = 20
    
    /// Speculative context debounce (seconds)
    static let speculativeDebounce = 0.3
    
    /// Chunk size limit for semantic search
    static let maxChunkLines = 50
    
    /// Minimum chunk size
    static let minChunkLines = 5
    
    /// Similarity guard threshold (percentage)
    static let similarityGuardThreshold = 0.2
    
    /// Minimum file size for similarity guard (lines)
    static let similarityGuardMinLines = 50
}
