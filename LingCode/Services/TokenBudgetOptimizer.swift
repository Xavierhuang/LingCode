//
//  TokenBudgetOptimizer.swift
//  LingCode
//
//  Token budget optimization with dynamic context trimming and intelligent file slicing
//

import Foundation

struct TokenBudget {
    let system: Int = 1000
    let activeFile: Int = 4000
    let selection: Int = 2000
    let diagnostics: Int = 1000
    let relatedFiles: Int = 6000
    let headroom: Int = 2000
    
    var total: Int {
        system + activeFile + selection + diagnostics + relatedFiles + headroom
    }
}

struct ContextItem {
    let file: URL
    let content: String
    let score: Int
    let isActive: Bool
    let referencedSymbols: Set<String>
}

class TokenBudgetOptimizer {
    // FIX: Mark shared as nonisolated to allow access from actor contexts
    static let shared = TokenBudgetOptimizer()
    
    private let budget = TokenBudget()
    
    private init() {}
    
    /// Optimize context within token budget
    /// FIX: Mark as nonisolated to allow calling from actor contexts
    nonisolated func optimizeContext(
        items: [ContextItem],
        maxTokens: Int = 16000
    ) -> [ContextItem] {
        var optimized: [ContextItem] = []
        var totalTokens = 0
        
        // Always include active file (never trim)
        for item in items where item.isActive {
            let tokens = estimateTokens(item.content)
            if totalTokens + tokens <= maxTokens {
                optimized.append(item)
                totalTokens += tokens
            }
        }
        
        // Sort remaining by score
        let remaining = items.filter { !$0.isActive }
            .sorted { $0.score > $1.score }
        
        // Include remaining items with intelligent trimming
        for item in remaining {
            let fullTokens = estimateTokens(item.content)
            let budgetRemaining = maxTokens - totalTokens
            
            if fullTokens <= budgetRemaining {
                // Full file fits
                optimized.append(item)
                totalTokens += fullTokens
            } else if budgetRemaining > 100 {
                // Trim file to fit
                let trimmed = sliceFile(
                    item.content,
                    referencedSymbols: item.referencedSymbols,
                    maxTokens: budgetRemaining
                )
                let trimmedTokens = estimateTokens(trimmed)
                
                if trimmedTokens > 0 && totalTokens + trimmedTokens <= maxTokens {
                    // Create new item with trimmed content
                    optimized.append(ContextItem(
                        file: item.file,
                        content: trimmed,
                        score: item.score,
                        isActive: item.isActive,
                        referencedSymbols: item.referencedSymbols
                    ))
                    totalTokens += trimmedTokens
                }
            }
        }
        
        return optimized
    }
    
    /// Slice file to include only relevant symbols (structural, not summarized)
    private func sliceFile(
        _ content: String,
        referencedSymbols: Set<String>,
        maxTokens: Int
    ) -> String {
        // If no referenced symbols, include imports and exports only
        if referencedSymbols.isEmpty {
            return sliceToImportsAndExports(content, maxTokens: maxTokens)
        }
        
        // Parse symbols and include only referenced ones
        let lines = content.components(separatedBy: .newlines)
        var includedLines: Set<Int> = []
        
        // Always include imports
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") ||
               trimmed.hasPrefix("from ") ||
               trimmed.hasPrefix("require(") ||
               trimmed.hasPrefix("#include") {
                includedLines.insert(index)
            }
        }
        
        // Include referenced symbols (would use ASTAnchorService in real implementation)
        
        // For now, use regex-based symbol detection
        for (index, line) in lines.enumerated() {
            for symbol in referencedSymbols {
                if line.contains(symbol) {
                    // Include this line and surrounding context
                    let start = max(0, index - 2)
                    let end = min(lines.count, index + 10)
                    for i in start..<end {
                        includedLines.insert(i)
                    }
                }
            }
        }
        
        // Build sliced content
        let sortedLines = includedLines.sorted()
        var sliced: [String] = []
        var lastIndex = -1
        
        for lineIndex in sortedLines {
            // Add gap marker if there's a jump
            if lastIndex >= 0 && lineIndex > lastIndex + 1 {
                sliced.append("// ...")
            }
            sliced.append(lines[lineIndex])
            lastIndex = lineIndex
        }
        
        let result = sliced.joined(separator: "\n")
        let tokens = estimateTokens(result)
        
        // If still too large, trim more aggressively
        if tokens > maxTokens {
            return sliceToImportsAndExports(content, maxTokens: maxTokens)
        }
        
        return result
    }
    
    /// Slice to imports and exports only
    private func sliceToImportsAndExports(_ content: String, maxTokens: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var included: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Include imports
            if trimmed.hasPrefix("import ") ||
               trimmed.hasPrefix("from ") ||
               trimmed.hasPrefix("require(") ||
               trimmed.hasPrefix("#include") ||
               trimmed.hasPrefix("export ") {
                included.append(line)
            }
            
            // Include exported symbols
            if trimmed.contains("export ") {
                included.append(line)
            }
        }
        
        let result = included.joined(separator: "\n")
        let tokens = estimateTokens(result)
        
        if tokens <= maxTokens {
            return result
        }
        
        // Last resort: just imports
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("import ") ||
                   trimmed.hasPrefix("from ") ||
                   trimmed.hasPrefix("require(") ||
                   trimmed.hasPrefix("#include")
        }.joined(separator: "\n")
    }
    
    /// Fast token estimation
    /// IMPROVEMENT: Uses BPE tokenizer for accurate token counting (replaces heuristic)
    func estimateTokens(_ text: String) -> Int {
        // Use BPETokenizer for accurate token counting
        // This replaces the heuristic-based approach with proper BPE tokenization
        return BPETokenizer.shared.estimateTokens(text)
    }
    
    /// Budget enforcement: drop lowest scored items
    func enforceBudget(
        items: [ContextItem],
        maxTokens: Int
    ) -> [ContextItem] {
        let sorted = items.sorted { $0.score > $1.score }
        var total = 0
        var result: [ContextItem] = []
        
        for item in sorted {
            let tokens = estimateTokens(item.content)
            if total + tokens <= maxTokens {
                result.append(item)
                total += tokens
            } else {
                break
            }
        }
        
        return result
    }
}
