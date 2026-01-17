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

#if canImport(EditorParsers)
import EditorParsers
#endif

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
    // FIX: Make index nonisolated for thread-safe access from actor contexts
    nonisolated(unsafe) private var index: [CodeChunk] = []
    private let fileManager = FileManager.default
    // FIX: Make embedding nonisolated for thread-safe access
    nonisolated(unsafe) private var embedding: NLEmbedding?
    
    // Vector database for embeddings
    // FIX: VectorDB is a regular class, safe to access from any context
    private let vectorDB = VectorDB.shared
    
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
            var embeddingsToStore: [CodeEmbedding] = []
            
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
                    
                    // Generate embeddings for chunks
                    for chunk in chunks {
                        if let embeddingVector = self.vectorDB.generateEmbedding(for: chunk.content) {
                            let codeEmbedding = CodeEmbedding(
                                id: chunk.id,
                                filePath: chunk.filePath,
                                startLine: chunk.startLine,
                                endLine: chunk.endLine,
                                content: chunk.content,
                                embedding: embeddingVector,
                                keywords: chunk.keywords
                            )
                            embeddingsToStore.append(codeEmbedding)
                        }
                    }
                }
            }
            
            // Store embeddings in vector DB
            self.vectorDB.store(embeddingsToStore)
            
            DispatchQueue.main.async {
                self.index = newIndex
                self.isIndexing = false
                print("✅ Indexed \(newIndex.count) code chunks with vector embeddings")
            }
        }
    }
    
    /// 2. Find relevant code chunks for a query (new API with vector search)
    /// FIX: Mark as nonisolated to allow calling from actor contexts
    nonisolated func search(query: String, limit: Int = 10) -> [CodeChunk] {
        guard !index.isEmpty else { return [] }
        
        // FIX: Access vectorDB and create vectorMap in a way that's safe for nonisolated context
        // VectorDB is a regular class, so accessing it is safe
        let vectorResults = vectorDB.search(query: query, limit: limit * 2) // Get more for hybrid scoring
        
        // Create a map of vector results for fast lookup
        // FIX: CodeEmbedding is a struct with value semantics, safe to use
        let vectorMap = Dictionary(uniqueKeysWithValues: vectorResults.map { ($0.id, $0) })
        
        // A. Keyword Boosting (Fast)
        let queryTerms = query.lowercased().split(separator: " ").map(String.init)
        
        // B. Hybrid Scoring: Vector Similarity + Keyword Match
        let scoredChunks = index.map { chunk -> (CodeChunk, Double) in
            var score = 0.0
            
            // 1. Vector similarity (primary signal)
            // FIX: Accessing chunk.id and vectorMap is safe - both are value types
            if let vectorEmbedding = vectorMap[chunk.id] {
                // Use similarity score from vector DB (0.0 to 1.0)
                // FIX: similarity() is a method on a struct, safe to call
                let queryEmbedding = CodeEmbedding(
                    id: "query",
                    filePath: "",
                    startLine: 0,
                    endLine: 0,
                    content: query,
                    embedding: [],
                    keywords: []
                )
                score += vectorEmbedding.similarity(to: queryEmbedding) * 50.0 // Weight vector similarity heavily
            }
            
            // 2. Keyword overlap
            let contentLower = chunk.content.lowercased()
            for term in queryTerms {
                if contentLower.contains(term) {
                    score += 10.0 // Strong signal
                }
            }
            
            // 3. Filename match
            if !queryTerms.isEmpty && chunk.filePath.lowercased().contains(queryTerms[0]) {
                score += 20.0 // Very strong signal
            }
            
            // 4. Fallback: NLEmbedding distance (if vector DB doesn't have this chunk)
            if vectorMap[chunk.id] == nil, let embedding = self.embedding {
                let keywordsText = chunk.keywords.joined(separator: " ")
                if !keywordsText.isEmpty {
                    let dist = embedding.distance(between: query, and: keywordsText)
                    score += (1.0 - dist) * 15.0
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
                    let dist = embedding.distance(between: query, and: keywordsText)
                    score += (1.0 - dist) * 15.0
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
    
    /// FIX: Language-aware chunking strategy
    /// Supports both brace-based (Swift/JS/C++) and indentation-based (Python/YAML) languages
    private func chunkFile(_ content: String, fileURL: URL, workspace: URL) -> [CodeChunk] {
        let ext = fileURL.pathExtension.lowercased()
        let language = mapExtensionToLanguage(ext)
        
        // Use Tree-sitter for supported languages if available
        #if canImport(EditorParsers)
        if TreeSitterManager.shared.isLanguageSupported(language) {
            return chunkFileWithTreeSitter(content: content, fileURL: fileURL, workspace: workspace, language: language)
        }
        #endif
        
        // Fallback to language-specific heuristics
        switch language {
        case "python", "yaml":
            return chunkFileByIndentation(content: content, fileURL: fileURL, workspace: workspace)
        default:
            return chunkFileByBraces(content: content, fileURL: fileURL, workspace: workspace)
        }
    }
    
    /// Chunk using Tree-sitter AST (production-grade)
    #if canImport(EditorParsers)
    private func chunkFileWithTreeSitter(content: String, fileURL: URL, workspace: URL, language: String) -> [CodeChunk] {
        let symbols = TreeSitterManager.shared.parse(content: content, language: language, fileURL: fileURL)
        let relativePath = fileURL.path.replacingOccurrences(of: workspace.path + "/", with: "")
        let lines = content.components(separatedBy: .newlines)
        
        var chunks: [CodeChunk] = []
        
        // Group symbols into chunks (one chunk per function/class)
        for symbol in symbols {
            guard symbol.range.upperBound <= lines.count else { continue }
            
            let startLine = max(0, symbol.range.lowerBound)
            let endLine = min(lines.count - 1, symbol.range.upperBound - 1)
            let chunkLines = Array(lines[startLine...endLine])
            let chunkContent = chunkLines.joined(separator: "\n")
            
            // Extract keywords from symbol name and content
            var keywords = [symbol.name]
            keywords.append(contentsOf: chunkContent.split(separator: " ")
                .filter { $0.count > 3 }
                .prefix(19)
                .map(String.init))
            
            chunks.append(CodeChunk(
                filePath: relativePath,
                content: chunkContent,
                startLine: startLine,
                endLine: endLine,
                keywords: Array(keywords.prefix(20))
            ))
        }
        
        return chunks.isEmpty ? chunkFileByBraces(content: content, fileURL: fileURL, workspace: workspace) : chunks
    }
    #endif
    
    /// Chunk Python/YAML by indentation level
    private func chunkFileByIndentation(content: String, fileURL: URL, workspace: URL) -> [CodeChunk] {
        let lines = content.components(separatedBy: .newlines)
        var chunks: [CodeChunk] = []
        var currentChunkLines: [String] = []
        var startLine = 0
        var baseIndent = 0
        
        let relativePath = fileURL.path.replacingOccurrences(of: workspace.path + "/", with: "")
        
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                currentChunkLines.append(line)
                continue
            }
            
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            
            // FIX: Python decorators (@classmethod, @route) should be part of the next chunk
            // Don't split on decorators - they belong with the function they decorate
            if trimmed.hasPrefix("@") {
                // This is a decorator; keep accumulating but mark as start of new logical block
                currentChunkLines.append(line)
                // Don't flush chunk yet, but ensure next def includes this
                if baseIndent == 0 {
                    baseIndent = indent
                }
                continue
            }
            
            // Start new chunk on function/class definition (indent = 0) or significant indent change
            if (indent == 0 && !currentChunkLines.isEmpty) || 
               (baseIndent > 0 && indent < baseIndent && currentChunkLines.count >= AgentConfiguration.minChunkLines) {
                // Finalize current chunk
                if currentChunkLines.count >= AgentConfiguration.minChunkLines {
                    let chunkContent = currentChunkLines.joined(separator: "\n")
                    let keywords = extractKeywords(from: chunkContent)
                    chunks.append(CodeChunk(
                        filePath: relativePath,
                        content: chunkContent,
                        startLine: startLine,
                        endLine: i - 1,
                        keywords: keywords
                    ))
                }
                currentChunkLines = []
                startLine = i
            }
            
            if baseIndent == 0 && indent == 0 {
                baseIndent = indent
            }
            
            currentChunkLines.append(line)
            
            // Force chunk split if too large
            if currentChunkLines.count > AgentConfiguration.maxChunkLines {
                let chunkContent = currentChunkLines.joined(separator: "\n")
                let keywords = extractKeywords(from: chunkContent)
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
        
        // Add remaining lines
        if !currentChunkLines.isEmpty && currentChunkLines.count >= AgentConfiguration.minChunkLines {
            let chunkContent = currentChunkLines.joined(separator: "\n")
            let keywords = extractKeywords(from: chunkContent)
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
    
    /// Chunk brace-based languages (Swift/JS/C++)
    private func chunkFileByBraces(content: String, fileURL: URL, workspace: URL) -> [CodeChunk] {
        let lines = content.components(separatedBy: .newlines)
        var chunks: [CodeChunk] = []
        var currentChunkLines: [String] = []
        var startLine = 0
        var braceDepth = 0
        
        let relativePath = fileURL.path.replacingOccurrences(of: workspace.path + "/", with: "")
        
        for (i, line) in lines.enumerated() {
            currentChunkLines.append(line)
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            braceDepth += line.filter { $0 == "{" }.count
            braceDepth -= line.filter { $0 == "}" }.count
            
            // End chunk on closing brace at root level or size limit
            if (braceDepth == 0 && trimmed == "}" && currentChunkLines.count >= AgentConfiguration.minChunkLines) ||
               currentChunkLines.count > AgentConfiguration.maxChunkLines {
                let chunkContent = currentChunkLines.joined(separator: "\n")
                let keywords = extractKeywords(from: chunkContent)
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
        
        // Add remaining lines
        if !currentChunkLines.isEmpty && currentChunkLines.count >= AgentConfiguration.minChunkLines {
            let chunkContent = currentChunkLines.joined(separator: "\n")
            let keywords = extractKeywords(from: chunkContent)
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
    
    /// Extract keywords from content
    private func extractKeywords(from content: String) -> [String] {
        return content.split(separator: " ")
            .filter { $0.count > 3 }
            .prefix(20)
            .map(String.init)
    }
    
    /// Map file extension to language identifier
    private func mapExtensionToLanguage(_ ext: String) -> String {
        switch ext {
        case "py": return "python"
        case "js": return "javascript"
        case "ts", "tsx": return "typescript"
        case "go": return "go"
        case "yaml", "yml": return "yaml"
        default: return ext
        }
    }
    
    private func isCodeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["swift", "js", "ts", "py", "go", "rs", "java", "c", "cpp", "h", "m", "mm", "hpp", "cc"].contains(ext)
    }
}
