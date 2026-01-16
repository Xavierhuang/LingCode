//
//  SemanticSearchService.swift
//  LingCode
//
//  Created for Hybrid Context Retrieval (RAG)
//  Beats Cursor by finding relevant code that isn't currently open.
//

import Foundation
import NaturalLanguage
import Combine

struct CodeChunk: Codable, Identifiable {
    var id: String { filePath + "::" + String(startLine) }
    let filePath: String
    let content: String
    let startLine: Int
    let endLine: Int
    // In a real production app, we would store vector embeddings here.
    // For this implementation, we use keyword + NL similarity.
    var keywords: [String]
}

// Backward compatibility: Convert CodeChunk to SemanticSearchResult
struct SemanticSearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let line: Int
    let column: Int
    let text: String
    let relevanceScore: Double
    let explanation: String?
    
    init(from chunk: CodeChunk, score: Double) {
        self.filePath = chunk.filePath
        self.line = chunk.startLine
        self.column = 1
        self.text = chunk.content.components(separatedBy: .newlines).first ?? chunk.content
        self.relevanceScore = score
        self.explanation = "Semantic match"
    }
}

class SemanticSearchService: ObservableObject {
    static let shared = SemanticSearchService()
    
    @Published var isIndexing = false
    private var index: [CodeChunk] = []
    private let fileManager = FileManager.default
    private var embedding: NLEmbedding?
    
    // Background queue for indexing
    private let indexQueue = DispatchQueue(label: "com.lingcode.semantic.index", qos: .utility)
    
    private init() {
        // Initialize embedding (may be nil if not available)
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }
    
    /// 1. Index the workspace (Run this when opening a project)
    func indexWorkspace(_ workspaceURL: URL) {
        self.isIndexing = true
        
        indexQueue.async {
            var newIndex: [CodeChunk] = []
            
            let enumerator = self.fileManager.enumerator(
                at: workspaceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            
            while let fileURL = enumerator?.nextObject() as? URL {
                // Skip non-code files
                guard self.isCodeFile(fileURL) else { continue }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let chunks = self.chunkFile(content, fileURL: fileURL, workspace: workspaceURL)
                    newIndex.append(contentsOf: chunks)
                }
            }
            
            DispatchQueue.main.async {
                self.index = newIndex
                self.isIndexing = false
                print("✅ Indexed \(newIndex.count) code chunks for semantic search")
            }
        }
    }
    
    /// 2. Find relevant code chunks for a query (new API)
    func search(query: String, limit: Int = 10) -> [CodeChunk] {
        guard !index.isEmpty else { return [] }
        
        // A. Keyword Boosting (Fast)
        let queryTerms = query.lowercased().split(separator: " ").map(String.init)
        
        // B. Semantic Scoring
        // In a full RAG system, we would do Dot Product of Vectors.
        // Here we use a hybrid score of Keyword Match + Apple NLEmbedding distance.
        
        let scoredChunks = index.map { chunk -> (CodeChunk, Double) in
            var score = 0.0
            
            // 1. Keyword overlap
            let contentLower = chunk.content.lowercased()
            for term in queryTerms {
                if contentLower.contains(term) {
                    score += 10.0 // Strong signal
                }
            }
            
            // 2. Filename match
            if !queryTerms.isEmpty && chunk.filePath.lowercased().contains(queryTerms[0]) {
                score += 20.0 // Very strong signal
            }
            
            // 3. Simple Semantic (Conceptual) Match
            // We use the embedding distance between query and chunk keywords
            if let embedding = self.embedding {
                let keywordsText = chunk.keywords.joined(separator: " ")
                if !keywordsText.isEmpty {
                    if let dist = try? embedding.distance(between: query, and: keywordsText) {
                        score += (1.0 - dist) * 15.0
                    }
                }
            }
            
            return (chunk, score)
        }
        
        // Return top N
        return scoredChunks
            .filter { $0.1 > 5.0 } // Minimum relevance threshold
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Backward compatibility: Search that returns SemanticSearchResult
    func search(
        query: String,
        in projectURL: URL,
        maxResults: Int = 50
    ) async -> [SemanticSearchResult] {
        // If index is empty, index the workspace first
        if index.isEmpty {
            indexWorkspace(projectURL)
            // Wait a bit for indexing to start (in production, you'd use proper async/await)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Use the new search API and convert results
        let chunks = search(query: query, limit: maxResults)
        return chunks.map { chunk in
            // Calculate score for this chunk
            let queryTerms = query.lowercased().split(separator: " ").map(String.init)
            var score = 0.0
            
            let contentLower = chunk.content.lowercased()
            for term in queryTerms {
                if contentLower.contains(term) {
                    score += 10.0
                }
            }
            
            if !queryTerms.isEmpty && chunk.filePath.lowercased().contains(queryTerms[0]) {
                score += 20.0
            }
            
            if let embedding = self.embedding {
                let keywordsText = chunk.keywords.joined(separator: " ")
                if !keywordsText.isEmpty {
                    if let dist = try? embedding.distance(between: query, and: keywordsText) {
                        score += (1.0 - dist) * 15.0
                    }
                }
            }
            
            return SemanticSearchResult(from: chunk, score: score)
        }
    }
    
    func findSimilarCode(to code: String, in projectURL: URL) async -> [SemanticSearchResult] {
        // Find code that is semantically similar to the provided code
        let query = "Find code similar to this:\n\(code.prefix(500))"
        return await search(query: query, in: projectURL)
    }
    
    // MARK: - Helper Methods
    
    private func chunkFile(_ content: String, fileURL: URL, workspace: URL) -> [CodeChunk] {
        // Simple chunking strategy: Split by functions/classes (heuristic)
        // A robust version would use TreeSitter
        
        let lines = content.components(separatedBy: .newlines)
        var chunks: [CodeChunk] = []
        var currentChunkLines: [String] = []
        var startLine = 0
        
        let relativePath = fileURL.path.replacingOccurrences(of: workspace.path + "/", with: "")
        
        for (i, line) in lines.enumerated() {
            currentChunkLines.append(line)
            
            // Heuristic: End chunk on closing brace at root level or empty line after 20+ lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Basic chunk boundary detection
            if (trimmed == "}" || currentChunkLines.count > 50) && currentChunkLines.count > 5 {
                let chunkContent = currentChunkLines.joined(separator: "\n")
                
                // Extract keywords (simplistic)
                let keywords = chunkContent.split(separator: " ")
                    .filter { $0.count > 3 }
                    .prefix(20)
                    .map(String.init)
                
                chunks.append(CodeChunk(
                    filePath: relativePath,
                    content: chunkContent,
                    startLine: startLine,
                    endLine: i,
                    keywords: keywords
                ))
                
                currentChunkLines = []
                startLine = i + 1
            }
        }
        
        // Add remaining lines as final chunk if any
        if !currentChunkLines.isEmpty && currentChunkLines.count > 5 {
            let chunkContent = currentChunkLines.joined(separator: "\n")
            let keywords = chunkContent.split(separator: " ")
                .filter { $0.count > 3 }
                .prefix(20)
                .map(String.init)
            
            chunks.append(CodeChunk(
                filePath: relativePath,
                content: chunkContent,
                startLine: startLine,
                endLine: lines.count - 1,
                keywords: keywords
            ))
        }
        
        return chunks
    }
    
    private func isCodeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["swift", "js", "ts", "py", "go", "rs", "java", "c", "cpp", "h", "m", "mm", "hpp", "cc"].contains(ext)
    }
}
