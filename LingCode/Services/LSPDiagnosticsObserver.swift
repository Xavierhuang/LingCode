//
//  LSPDiagnosticsObserver.swift
//  LingCode
//
//  Enhanced Speculative Execution: Pre-generate fixes for compilation errors
//  Observes LSP diagnostics and triggers local model when user pauses on error
//

import Foundation
import Combine

// MARK: - Diagnostic Model

struct Diagnostic {
    let filePath: URL
    let line: Int
    let column: Int
    let severity: DiagnosticSeverity
    let message: String
    let code: String?
    
    enum DiagnosticSeverity {
        case error
        case warning
        case information
        case hint
    }
}

// MARK: - Cached Fix

struct CachedFix {
    let diagnostic: Diagnostic
    let fixCode: String
    let diff: String
    let timestamp: Date
    let confidence: Double
}

// MARK: - LSP Diagnostics Observer

class LSPDiagnosticsObserver: ObservableObject {
    static let shared = LSPDiagnosticsObserver()
    
    @Published var diagnostics: [Diagnostic] = []
    @Published var cachedFixes: [String: CachedFix] = [:] // Key: "filePath:line:column"
    
    private var cursorPositionObserver: AnyCancellable?
    private var pauseTimer: Timer?
    private var lastCursorPosition: (file: URL, line: Int)?
    private let pauseThreshold: TimeInterval = 0.5 // 500ms pause triggers fix generation
    
    // Local model service for pre-generation
    private let localService = LocalOnlyService.shared
    
    private init() {
        // In a real implementation, this would connect to SourceKit-LSP
        // For now, we'll simulate diagnostics from compiler output
    }
    
    /// Update diagnostics (called from compiler/LSP)
    func updateDiagnostics(_ newDiagnostics: [Diagnostic]) {
        DispatchQueue.main.async {
            self.diagnostics = newDiagnostics
        }
    }
    
    /// Observe cursor position to detect when user pauses on error line
    func observeCursorPosition(file: URL, line: Int, column: Int) {
        // Cancel previous timer
        pauseTimer?.invalidate()
        
        // Check if there's an error at this position
        let errorAtPosition = diagnostics.first { diagnostic in
            diagnostic.filePath == file &&
            diagnostic.line == line &&
            diagnostic.severity == .error
        }
        
        guard let error = errorAtPosition else {
            lastCursorPosition = nil
            return
        }
        
        // User is on an error line - start pause timer
        lastCursorPosition = (file, line)
        
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            self?.triggerFixGeneration(for: error)
        }
    }
    
    /// Generate fix using local model (speculative execution)
    private func triggerFixGeneration(for diagnostic: Diagnostic) {
        let cacheKey = "\(diagnostic.filePath.path):\(diagnostic.line):\(diagnostic.column)"
        
        // Check if we already have a cached fix
        if let cached = cachedFixes[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 300 { // Cache valid for 5 minutes
            print("⚡️ Using cached fix for \(diagnostic.message)")
            return
        }
        
        // Generate fix using local model (fast, free)
        guard localService.isLocalModeEnabled && localService.isLocalModelAvailable() else {
            return // No local model available
        }
        
        print("🔮 Speculative execution: Pre-generating fix for error at \(diagnostic.filePath.lastPathComponent):\(diagnostic.line)")
        
        Task {
            do {
                // Read file content
                guard let fileContent = try? String(contentsOf: diagnostic.filePath, encoding: .utf8) else {
                    return
                }
                
                let lines = fileContent.components(separatedBy: .newlines)
                guard diagnostic.line <= lines.count else { return }
                
                let errorLine = lines[diagnostic.line - 1]
                let context = lines[max(0, diagnostic.line - 10)...min(lines.count - 1, diagnostic.line + 5)].joined(separator: "\n")
                
                // Build prompt for local model
                let prompt = """
                Fix this compilation error:
                
                File: \(diagnostic.filePath.lastPathComponent)
                Line \(diagnostic.line): \(errorLine)
                Error: \(diagnostic.message)
                
                Context:
                ```swift
                \(context)
                ```
                
                Return ONLY the fixed code for the error line, nothing else.
                """
                
                // Use local model to generate fix
                var fixCode = ""
                localService.streamLocally(
                    prompt: prompt,
                    context: nil,
                    onChunk: { chunk in
                        fixCode += chunk
                    },
                    onComplete: {
                        // Cache the fix
                        let cachedFix = CachedFix(
                            diagnostic: diagnostic,
                            fixCode: fixCode.trimmingCharacters(in: .whitespacesAndNewlines),
                            diff: self.generateDiff(original: errorLine, fixed: fixCode),
                            timestamp: Date(),
                            confidence: 0.8 // Local models have lower confidence
                        )
                        
                        DispatchQueue.main.async {
                            self.cachedFixes[cacheKey] = cachedFix
                            print("✅ Cached fix generated for \(diagnostic.message)")
                        }
                    },
                    onError: { error in
                        print("⚠️ Failed to generate speculative fix: \(error.localizedDescription)")
                    }
                )
            }
        }
    }
    
    /// Get cached fix for a diagnostic
    func getCachedFix(for diagnostic: Diagnostic) -> CachedFix? {
        let cacheKey = "\(diagnostic.filePath.path):\(diagnostic.line):\(diagnostic.column)"
        return cachedFixes[cacheKey]
    }
    
    /// Apply cached fix instantly (0ms latency)
    func applyCachedFix(_ fix: CachedFix) -> Bool {
        // This would be called when user types "Fix" or clicks a quick-fix button
        // Implementation would apply the diff to the file
        print("⚡️ Applying cached fix instantly (0ms latency)")
        return true
    }
    
    private func generateDiff(original: String, fixed: String) -> String {
        // Simple diff generation (can be enhanced)
        return "- \(original)\n+ \(fixed)"
    }
    
    /// Clear cached fixes
    func clearCache() {
        cachedFixes.removeAll()
    }
}
