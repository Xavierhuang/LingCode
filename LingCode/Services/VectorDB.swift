//
//  VectorDB.swift
//  LingCode
//
//  Lightweight vector database for code embeddings.
//  Similarity search is GPU-accelerated via MetalPerformanceShaders (MPS) matrix
//  multiply on Apple Silicon / Metal 3 GPUs, with Accelerate vDSP as the CPU
//  fast-path fallback for older devices or when Metal is unavailable.
//
//  Architecture
//  ────────────
//  • All stored embedding vectors are packed into a single contiguous Float32
//    matrix  E  of shape [N × D] (one row per chunk, D = embedding dimension).
//  • A query vector  q  of shape [1 × D] is broadcast-multiplied with  E^T,
//    producing a [1 × N] score vector — one dot product per stored chunk — in a
//    single MPS kernel call.
//  • Because every embedding is L2-normalised at write time, the dot product
//    equals the cosine similarity, so no per-element division is needed at
//    query time.
//  • The matrix is rebuilt lazily (dirty flag) rather than on every insert, so
//    bulk indexing only triggers one rebuild at search time.
//

import Foundation
import CoreML
import NaturalLanguage
import Accelerate
import Metal
import MetalPerformanceShaders

// MARK: - CodeEmbedding

struct CodeEmbedding: Codable {
    let id: String
    let filePath: String
    let startLine: Int
    let endLine: Int
    let content: String
    /// L2-normalised float vector (length == VectorDB.embeddingDimension)
    let embedding: [Float]
    let keywords: [String]

    /// Cosine similarity via Accelerate dot product.
    /// Both vectors must already be L2-normalised.
    func similarity(to other: CodeEmbedding) -> Double {
        let n = min(embedding.count, other.embedding.count)
        guard n > 0 else { return 0.0 }
        var dot: Float = 0.0
        vDSP_dotpr(embedding, 1, other.embedding, 1, &dot, vDSP_Length(n))
        return Double(dot)
    }
}

// MARK: - VectorDB

final class VectorDB {
    static let shared = VectorDB()

    // ── Storage ──────────────────────────────────────────────────────────────
    private var embeddings: [String: CodeEmbedding] = [:]

    // Ordered list of IDs matching the rows of the packed matrix.
    private var matrixIDs: [String] = []

    // Flat row-major Float32 buffer: rows = N chunks, cols = D dimensions.
    private var matrixBuffer: [Float] = []

    // Rebuild the matrix before the next search.
    private var matrixDirty = true

    // ── Embedding models ─────────────────────────────────────────────────────
    private let nlEmbeddingModel: NLEmbedding?
    private var coreMLModel: MLModel?
    let embeddingDimension: Int = 768

    // ── Metal / MPS ──────────────────────────────────────────────────────────
    private let metalDevice: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    /// true when MPS matrix multiply is available (Metal 3 / MPS on any Apple GPU)
    private let mpsAvailable: Bool

    // ── Init ─────────────────────────────────────────────────────────────────
    private init() {
        nlEmbeddingModel = NLEmbedding.sentenceEmbedding(for: .english)

        if let device = MTLCreateSystemDefaultDevice(),
           let queue = device.makeCommandQueue() {
            metalDevice = device
            commandQueue = queue
            mpsAvailable = true
        } else {
            metalDevice = nil
            commandQueue = nil
            mpsAvailable = false
        }

        loadCoreMLModel()
    }

    // MARK: - CoreML loading

    private func loadCoreMLModel() {
        guard let modelURL = Bundle.main.url(forResource: "EmbeddingModel",
                                             withExtension: "mlmodelc") else { return }
        do {
            coreMLModel = try MLModel(contentsOf: modelURL)
        } catch {
            print("VectorDB: CoreML model load failed – \(error.localizedDescription)")
        }
    }

    // MARK: - Embedding generation

    func generateEmbedding(for text: String) -> [Float]? {
        let raw: [Float]?
        if coreMLModel != nil {
            raw = generateEmbeddingWithCoreML(text: text)
        } else if let model = nlEmbeddingModel {
            raw = generateEmbeddingWithNLEmbedding(text: text, model: model)
        } else {
            return nil
        }
        return raw.map { l2Normalize($0) }
    }

    private func generateEmbeddingWithNLEmbedding(text: String, model: NLEmbedding) -> [Float] {
        let references: [String] = [
            "function definition implementation",
            "class struct enum protocol",
            "variable property method",
            "import module dependency",
            "error handling exception",
            "authentication login user",
            "database query storage",
            "network request response",
            "async await concurrency",
            "test unit integration"
        ]

        var vec = [Float](repeating: 0, count: embeddingDimension)
        for (i, ref) in references.enumerated() {
            let dist = model.distance(between: text.lowercased(), and: ref)
            vec[i] = Float(1.0 - dist)
        }

        let keywords = extractKeywords(from: text)
        for (i, kw) in keywords.enumerated() {
            let pos = (references.count + i) % embeddingDimension
            vec[pos] += Float(abs(kw.hashValue) % 100) / 1000.0
        }

        return vec // caller normalises
    }

    private func generateEmbeddingWithCoreML(text: String) -> [Float]? {
        guard let model = coreMLModel else { return nil }
        _ = model // silence unused-variable warning; real tokenisation needed per-model
        if let nlModel = nlEmbeddingModel {
            return generateEmbeddingWithNLEmbedding(text: text, model: nlModel)
        }
        return nil
    }

    // MARK: - L2 normalisation (Accelerate)

    private func l2Normalize(_ vec: [Float]) -> [Float] {
        var sumSq: Float = 0
        vDSP_svesq(vec, 1, &sumSq, vDSP_Length(vec.count))
        let mag = sqrtf(sumSq)
        guard mag > 0 else { return vec }
        var scale = 1.0 / mag
        var result = [Float](repeating: 0, count: vec.count)
        vDSP_vsmul(vec, 1, &scale, &result, 1, vDSP_Length(vec.count))
        return result
    }

    // MARK: - Storage

    func store(_ embedding: CodeEmbedding) {
        embeddings[embedding.id] = embedding
        matrixDirty = true
    }

    func store(_ newEmbeddings: [CodeEmbedding]) {
        for e in newEmbeddings { embeddings[e.id] = e }
        matrixDirty = true
    }

    func clear() {
        embeddings.removeAll()
        matrixIDs.removeAll()
        matrixBuffer.removeAll()
        matrixDirty = true
    }

    var count: Int { embeddings.count }

    // MARK: - Matrix rebuild

    /// Pack all stored embedding vectors into a contiguous row-major Float32
    /// buffer so that a single matrix multiply covers every chunk at once.
    private func rebuildMatrix() {
        let sorted = embeddings.values.sorted { $0.id < $1.id }
        matrixIDs = sorted.map { $0.id }
        matrixBuffer = sorted.flatMap { $0.embedding }
        matrixDirty = false
    }

    // MARK: - Search  (public)

    /// Returns the top `limit` most-similar chunks to `query`.
    /// Uses MPS GPU matrix multiply when available, Accelerate vDSP otherwise.
    nonisolated func search(query: String, limit: Int = 10) -> [CodeEmbedding] {
        guard let queryVec = generateEmbedding(for: query), !embeddings.isEmpty else {
            return []
        }

        if matrixDirty { rebuildMatrix() }

        let n = matrixIDs.count
        let d = embeddingDimension

        guard matrixBuffer.count == n * d else { return [] }

        let scores: [Float]
        if mpsAvailable, let device = metalDevice, let queue = commandQueue {
            scores = mpsCosineSimilarity(queryVec: queryVec, matrix: matrixBuffer,
                                         n: n, d: d, device: device, queue: queue)
                ?? accelerateCosineSimilarity(queryVec: queryVec, matrix: matrixBuffer, n: n, d: d)
        } else {
            scores = accelerateCosineSimilarity(queryVec: queryVec, matrix: matrixBuffer, n: n, d: d)
        }

        // Pair scores with IDs, sort, return top-limit chunks
        let topK = zip(matrixIDs, scores)
            .sorted { $0.1 > $1.1 }
            .prefix(limit)

        return topK.compactMap { embeddings[$0.0] }
    }

    /// Find chunks similar to a specific stored embedding.
    func findSimilar(to target: CodeEmbedding, limit: Int = 5) -> [CodeEmbedding] {
        if matrixDirty { rebuildMatrix() }

        let n = matrixIDs.count
        let d = embeddingDimension
        guard matrixBuffer.count == n * d else { return [] }

        let scores: [Float]
        if mpsAvailable, let device = metalDevice, let queue = commandQueue {
            scores = mpsCosineSimilarity(queryVec: target.embedding, matrix: matrixBuffer,
                                         n: n, d: d, device: device, queue: queue)
                ?? accelerateCosineSimilarity(queryVec: target.embedding, matrix: matrixBuffer, n: n, d: d)
        } else {
            scores = accelerateCosineSimilarity(queryVec: target.embedding, matrix: matrixBuffer, n: n, d: d)
        }

        return zip(matrixIDs, scores)
            .filter { $0.0 != target.id }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .compactMap { embeddings[$0.0] }
    }

    // MARK: - GPU path: MPS single-precision matrix multiply

    /// Computes  scores = E · q^T  on the GPU where E is [N × D] and q is [1 × D].
    /// Because every row of E and q are L2-normalised, the dot products equal cosine
    /// similarities.  Returns nil on any Metal error so the caller can fall back.
    private func mpsCosineSimilarity(queryVec: [Float],
                                      matrix: [Float],
                                      n: Int, d: Int,
                                      device: MTLDevice,
                                      queue: MTLCommandQueue) -> [Float]? {
        // ── Allocate GPU buffers ────────────────────────────────────────────
        let matrixBytes = n * d * MemoryLayout<Float>.stride
        let queryBytes  = d     * MemoryLayout<Float>.stride
        let resultBytes = n     * MemoryLayout<Float>.stride

        guard let matrixBuf = device.makeBuffer(bytes: matrix,
                                                length: matrixBytes,
                                                options: .storageModeShared),
              let queryBuf  = device.makeBuffer(bytes: queryVec,
                                                length: queryBytes,
                                                options: .storageModeShared),
              let resultBuf = device.makeBuffer(length: resultBytes,
                                                options: .storageModeShared)
        else { return nil }

        // ── MPS matrix descriptors ─────────────────────────────────────────
        //  E  : [N × D]  – rows are chunk embeddings
        //  q  : [D × 1]  – query column vector
        //  out: [N × 1]  – one dot product per chunk
        let descE = MPSMatrixDescriptor(rows: n, columns: d,
                                         rowBytes: d * MemoryLayout<Float>.stride,
                                         dataType: .float32)
        let descQ = MPSMatrixDescriptor(rows: d, columns: 1,
                                         rowBytes: 1 * MemoryLayout<Float>.stride,
                                         dataType: .float32)
        let descR = MPSMatrixDescriptor(rows: n, columns: 1,
                                         rowBytes: 1 * MemoryLayout<Float>.stride,
                                         dataType: .float32)

        let mpsE = MPSMatrix(buffer: matrixBuf, descriptor: descE)
        let mpsQ = MPSMatrix(buffer: queryBuf,  descriptor: descQ)
        let mpsR = MPSMatrix(buffer: resultBuf, descriptor: descR)

        // ── Encode multiply: out = E · q ───────────────────────────────────
        let matmul = MPSMatrixMultiplication(device: device,
                                              transposeLeft: false,
                                              transposeRight: false,
                                              resultRows: n,
                                              resultColumns: 1,
                                              interiorColumns: d,
                                              alpha: 1.0,
                                              beta: 0.0)

        guard let cmdBuf = queue.makeCommandBuffer() else { return nil }
        matmul.encode(commandBuffer: cmdBuf,
                      leftMatrix: mpsE,
                      rightMatrix: mpsQ,
                      resultMatrix: mpsR)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        guard cmdBuf.error == nil else { return nil }

        // ── Copy results back to CPU ───────────────────────────────────────
        let ptr = resultBuf.contents().bindMemory(to: Float.self, capacity: n)
        return Array(UnsafeBufferPointer(start: ptr, count: n))
    }

    // MARK: - CPU fast-path: Accelerate vDSP matrix-vector multiply

    /// Computes  scores = E · q  on the CPU via vDSP_mmul.
    /// Much faster than a scalar loop for large N (e.g. 2000 chunks × 768 dims).
    private func accelerateCosineSimilarity(queryVec: [Float],
                                             matrix: [Float],
                                             n: Int, d: Int) -> [Float] {
        var scores = [Float](repeating: 0, count: n)
        // vDSP_mmul: C[m×n] = A[m×k] · B[k×n]
        // Here: scores[N×1] = matrix[N×D] · query[D×1]
        vDSP_mmul(matrix, 1,
                  queryVec, 1,
                  &scores, 1,
                  vDSP_Length(n),   // rows of result
                  vDSP_Length(1),   // cols of result
                  vDSP_Length(d))   // inner dimension
        return scores
    }

    // MARK: - Keyword helper

    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "and", "or", "but", "for",
                                      "with", "from", "this", "that",
                                      "var", "let", "func", "class", "struct"]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Array(Set(words).prefix(50))
    }
}
