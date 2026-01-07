//
//  SemanticSearchService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct SemanticSearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let line: Int
    let column: Int
    let text: String
    let relevanceScore: Double
    let explanation: String?
}

class SemanticSearchService {
    static let shared = SemanticSearchService()
    
    private init() {}
    
    func search(
        query: String,
        in projectURL: URL,
        maxResults: Int = 50
    ) async -> [SemanticSearchResult] {
        // First, do a text-based search to get candidates
        let textResults = await performTextSearch(query: query, in: projectURL)
        
        // Then use AI to rank and understand relevance
        let semanticResults = await rankResultsWithAI(query: query, candidates: textResults, maxResults: maxResults)
        
        return semanticResults
    }
    
    func findSimilarCode(to code: String, in projectURL: URL) async -> [SemanticSearchResult] {
        // Find code that is semantically similar to the provided code
        let query = "Find code similar to this:\n\(code.prefix(500))"
        return await search(query: query, in: projectURL)
    }
    
    private func performTextSearch(query: String, in projectURL: URL) async -> [GlobalSearchResult] {
        var results: [GlobalSearchResult] = []
        
        // Extract keywords from query
        let keywords = extractKeywords(from: query)
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }
        
        // Collect all URLs first (synchronous)
        var fileURLs: [URL] = []
        while let element = enumerator.nextObject() as? URL {
            if !element.hasDirectoryPath {
                fileURLs.append(element)
            }
        }
        
        // Process files
        for fileURL in fileURLs {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  content.count < 500_000 else {
                continue
            }
            
            // Check if file contains any keywords
            let lowerContent = content.lowercased()
            var matches = 0
            for keyword in keywords {
                if lowerContent.contains(keyword.lowercased()) {
                    matches += 1
                }
            }
            
            if matches > 0 {
                // Find lines with matches
                let lines = content.components(separatedBy: .newlines)
                for (lineIndex, line) in lines.enumerated() {
                    let lowerLine = line.lowercased()
                    for keyword in keywords {
                        if lowerLine.contains(keyword.lowercased()) {
                            results.append(GlobalSearchResult(
                                filePath: fileURL.path,
                                line: lineIndex + 1,
                                column: 1,
                                text: line.trimmingCharacters(in: .whitespaces),
                                matchText: keyword
                            ))
                            break
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    private func extractKeywords(from query: String) -> [String] {
        // Simple keyword extraction - remove common words
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "should", "could", "may", "might", "can", "this", "that", "these", "those", "what", "which", "who", "where", "when", "why", "how"])
        
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }
        
        return Array(Set(words)) // Remove duplicates
    }
    
    private func rankResultsWithAI(
        query: String,
        candidates: [GlobalSearchResult],
        maxResults: Int
    ) async -> [SemanticSearchResult] {
        guard !candidates.isEmpty else { return [] }
        
        // Group candidates by file to reduce API calls
        let grouped = Dictionary(grouping: candidates) { $0.filePath }
        var rankedResults: [SemanticSearchResult] = []
        
        // Process in batches
        for (filePath, results) in grouped.prefix(10) {
            let fileResults = Array(results.prefix(20))
            let context = fileResults.map { "Line \($0.line): \($0.text)" }.joined(separator: "\n")
            
            let prompt = """
            Search query: "\(query)"
            
            Code snippets from file \(URL(fileURLWithPath: filePath).lastPathComponent):
            \(context)
            
            Rank these code snippets by relevance to the search query. Return only the most relevant ones (top 5-10).
            For each relevant snippet, provide:
            1. Line number
            2. Brief explanation of why it's relevant
            
            Format: Line X: [explanation]
            """
            
            // Use AI to rank results
            let ranked = await rankWithAI(prompt: prompt, results: fileResults, query: query)
            rankedResults.append(contentsOf: ranked)
        }
        
        // Sort by relevance score
        rankedResults.sort { $0.relevanceScore > $1.relevanceScore }
        
        return Array(rankedResults.prefix(maxResults))
    }
    
    private func rankWithAI(
        prompt: String,
        results: [GlobalSearchResult],
        query: String
    ) async -> [SemanticSearchResult] {
        // For now, use a simple heuristic-based ranking
        // In a full implementation, this would call the AI service
        
        var ranked: [SemanticSearchResult] = []
        
        for result in results {
            var score = 0.0
            
            // Exact match bonus
            if result.text.lowercased().contains(query.lowercased()) {
                score += 10.0
            }
            
            // Keyword matches
            let keywords = extractKeywords(from: query)
            let lowerText = result.text.lowercased()
            for keyword in keywords {
                if lowerText.contains(keyword.lowercased()) {
                    score += 2.0
                }
            }
            
            // Length penalty (shorter matches might be more relevant)
            if result.text.count < 100 {
                score += 1.0
            }
            
            ranked.append(SemanticSearchResult(
                filePath: result.filePath,
                line: result.line,
                column: result.column,
                text: result.text,
                relevanceScore: score,
                explanation: score > 5 ? "Relevant match" : nil
            ))
        }
        
        return ranked
    }
}

