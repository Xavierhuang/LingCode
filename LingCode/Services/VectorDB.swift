//
//  VectorDB.swift
//  LingCode
//
//  Lightweight vector database for code embeddings
//  Uses in-memory storage with SQLite persistence (optional)
//

import Foundation
import CoreML
import NaturalLanguage

// MARK: - Vector Embedding

struct CodeEmbedding: Codable {
    let id: String // CodeChunk.id
    let filePath: String
    let startLine: Int
    let endLine: Int
    let content: String
    let embedding: [Float] // Vector representation
    let keywords: [String]
    
    /// Calculate cosine similarity with another embedding
    func similarity(to other: CodeEmbedding) -> Double {
        guard embedding.count == other.embedding.count else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        
        for i in 0..<embedding.count {
            dotProduct += embedding[i] * other.embedding[i]
            normA += embedding[i] * embedding[i]
            normB += other.embedding[i] * other.embedding[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }
        
        return Double(dotProduct / denominator)
    }
}

// MARK: - Vector Database

class VectorDB {
    static let shared = VectorDB()
    
    private var embeddings: [String: CodeEmbedding] = [:]
    private let embeddingModel: NLEmbedding?
    private let embeddingDimension: Int
    
    private init() {
        // Use Apple's built-in sentence embedding (768 dimensions for English)
        embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
        embeddingDimension = 768 // Standard dimension for Apple's sentence embeddings
    }
    
    /// Generate embedding for text using CoreML/NaturalLanguage
    func generateEmbedding(for text: String) -> [Float]? {
        guard embeddingModel != nil else { return nil }
        
        // Use NLEmbedding to get vector representation
        // Note: NLEmbedding doesn't directly expose vectors, so we use distance-based approach
        // For true vector extraction, we'd need a CoreML model
        
        // Fallback: Use keyword-based pseudo-embedding
        // In production, load a CoreML embedding model (e.g., sentence-transformers)
        return generatePseudoEmbedding(for: text)
    }
    
    /// Generate pseudo-embedding from keywords (fallback until CoreML model is loaded)
    private func generatePseudoEmbedding(for text: String) -> [Float] {
        // Extract keywords and create a simple hash-based embedding
        let keywords = extractKeywords(from: text)
        var embedding = [Float](repeating: 0.0, count: embeddingDimension)
        
        // Hash each keyword to positions in the embedding vector
        for keyword in keywords {
            let hash = abs(keyword.hashValue)
            let index = hash % embeddingDimension
            embedding[index] += 1.0
        }
        
        // Normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / Float(magnitude) }
        }
        
        return embedding
    }
    
    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction (can be enhanced with NLP)
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        
        let uniqueWords = Array(Set(words))
        return Array(uniqueWords.prefix(50))
    }
    
    /// Store embedding for a code chunk
    func store(_ embedding: CodeEmbedding) {
        embeddings[embedding.id] = embedding
    }
    
    /// Store multiple embeddings
    func store(_ embeddings: [CodeEmbedding]) {
        for embedding in embeddings {
            self.embeddings[embedding.id] = embedding
        }
    }
    
    /// Search for similar code chunks using vector similarity
    func search(query: String, limit: Int = 10) -> [CodeEmbedding] {
        guard let queryEmbedding = generateEmbedding(for: query) else {
            return []
        }
        
        let queryCodeEmbedding = CodeEmbedding(
            id: "query",
            filePath: "",
            startLine: 0,
            endLine: 0,
            content: query,
            embedding: queryEmbedding,
            keywords: []
        )
        
        // Calculate similarity for all stored embeddings
        let scored = embeddings.values.map { embedding -> (CodeEmbedding, Double) in
            let similarity = queryCodeEmbedding.similarity(to: embedding)
            return (embedding, similarity)
        }
        
        // Sort by similarity and return top results
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Find similar code to a given code chunk
    func findSimilar(to codeEmbedding: CodeEmbedding, limit: Int = 5) -> [CodeEmbedding] {
        let scored = embeddings.values
            .filter { $0.id != codeEmbedding.id } // Exclude self
            .map { embedding -> (CodeEmbedding, Double) in
                let similarity = codeEmbedding.similarity(to: embedding)
                return (embedding, similarity)
            }
        
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Clear all embeddings
    func clear() {
        embeddings.removeAll()
    }
    
    /// Get embedding count
    var count: Int {
        return embeddings.count
    }
}
