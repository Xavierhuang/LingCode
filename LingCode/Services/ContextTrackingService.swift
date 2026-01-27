//
//  ContextTrackingService.swift
//  LingCode
//
//  Tracks and visualizes what context is being used in AI requests
//

import Foundation
import Combine

struct ContextSource: Identifiable, Hashable {
    let id = UUID()
    let type: ContextType
    let name: String
    let path: String?
    let relevanceScore: Double?
    let tokenCount: Int?
    let timestamp: Date
    
    enum ContextType: String, CaseIterable {
        case activeFile = "Active File"
        case selectedText = "Selection"
        case codebaseSearch = "Codebase Search"
        case fileMention = "File Mention"
        case folderMention = "Folder Mention"
        case terminalOutput = "Terminal Output"
        case webSearch = "Web Search"
        case diagnostics = "Diagnostics"
        case gitDiff = "Git Diff"
        case workspaceRules = "Workspace Rules"
        case codebaseOverview = "Codebase Overview"
    }
}

@MainActor
class ContextTrackingService: ObservableObject {
    static let shared = ContextTrackingService()
    
    @Published var currentContextSources: [ContextSource] = []
    @Published var contextHistory: [ContextSource] = []
    @Published var totalTokenUsage: Int = 0
    @Published var contextBuildTime: TimeInterval = 0
    
    private init() {}
    
    /// Track context sources for current request
    func trackContext(
        type: ContextSource.ContextType,
        name: String,
        path: String? = nil,
        relevanceScore: Double? = nil,
        tokenCount: Int? = nil
    ) {
        let source = ContextSource(
            type: type,
            name: name,
            path: path,
            relevanceScore: relevanceScore,
            tokenCount: tokenCount,
            timestamp: Date()
        )
        currentContextSources.append(source)
        contextHistory.append(source)
        
        if let tokens = tokenCount {
            totalTokenUsage += tokens
        }
    }
    
    /// Clear current context for new request
    func clearCurrentContext() {
        currentContextSources.removeAll()
    }
    
    /// Get context summary
    func getContextSummary() -> String {
        var summary = "Context Sources:\n"
        for source in currentContextSources {
            summary += "• \(source.type.rawValue): \(source.name)"
            if let path = source.path {
                summary += " (\(path))"
            }
            if let score = source.relevanceScore {
                summary += " [Relevance: \(String(format: "%.1f", score))]"
            }
            if let tokens = source.tokenCount {
                summary += " [Tokens: \(tokens)]"
            }
            summary += "\n"
        }
        return summary
    }
    
    /// Get token usage by type
    func getTokenUsageByType() -> [ContextSource.ContextType: Int] {
        var usage: [ContextSource.ContextType: Int] = [:]
        for source in currentContextSources {
            if let tokens = source.tokenCount {
                usage[source.type, default: 0] += tokens
            }
        }
        return usage
    }
}
