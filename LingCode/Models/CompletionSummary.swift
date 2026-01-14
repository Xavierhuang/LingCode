//
//  CompletionSummary.swift
//  LingCode
//
//  Deterministic completion summary model
//  Derived from parsed execution results, not AI-generated
//

import Foundation

/// Completion summary derived from structured execution results
/// 
/// WHY DERIVED, NOT GENERATED:
/// - Summary is built deterministically from observable diffs/actions
/// - No additional AI call needed - we already have structured data
/// - Ensures accuracy and avoids hallucination
public struct CompletionSummary: Equatable {
    /// Main title/summary line
    public let title: String
    
    /// Bullet points with details
    public let bulletPoints: [String]
    
    /// File statistics
    public struct FileStats: Equatable {
        public let filesModified: Int
        public let totalAddedLines: Int
        public let totalRemovedLines: Int
        public let netChange: Int
        
        public init(filesModified: Int, totalAddedLines: Int, totalRemovedLines: Int) {
            self.filesModified = filesModified
            self.totalAddedLines = totalAddedLines
            self.totalRemovedLines = totalRemovedLines
            self.netChange = totalAddedLines - totalRemovedLines
        }
    }
    public let fileStats: FileStats?
    
    public init(title: String, bulletPoints: [String] = [], fileStats: FileStats? = nil) {
        self.title = title
        self.bulletPoints = bulletPoints
        self.fileStats = fileStats
    }
}
