//
//  SemanticDiffService.swift
//  LingCode
//
//  Inline semantic diffs (not line diffs) - shows what changed semantically
//

import Foundation

enum SemanticChange {
    case renamedSymbol(old: String, new: String, symbolID: UUID)
    case conditionChanged(before: String, after: String)
    case returnTypeChanged(before: String, after: String)
    case functionAdded(name: String, signature: String)
    case functionRemoved(name: String, signature: String)
    case parameterAdded(function: String, parameter: String)
    case parameterRemoved(function: String, parameter: String)
    case expressionChanged(before: String, after: String)
    case typeChanged(before: String, after: String)
    
    var displayText: String {
        switch self {
        case .renamedSymbol(let old, let new, _):
            return "↺ Renamed: \(old) → \(new)"
        case .conditionChanged(let before, let after):
            return "↺ Condition changed: \(before) → \(after)"
        case .returnTypeChanged(let before, let after):
            return "↺ Return type changed: \(before) → \(after)"
        case .functionAdded(let name, _):
            return "+ Function added: \(name)"
        case .functionRemoved(let name, _):
            return "- Function removed: \(name)"
        case .parameterAdded(let function, let parameter):
            return "+ Parameter added to \(function): \(parameter)"
        case .parameterRemoved(let function, let parameter):
            return "- Parameter removed from \(function): \(parameter)"
        case .expressionChanged(let before, let after):
            return "↺ Expression changed: \(before) → \(after)"
        case .typeChanged(let before, let after):
            return "↺ Type changed: \(before) → \(after)"
        }
    }
    
    var icon: String {
        switch self {
        case .renamedSymbol, .conditionChanged, .returnTypeChanged, .expressionChanged, .typeChanged:
            return "↺"
        case .functionAdded, .parameterAdded:
            return "+"
        case .functionRemoved, .parameterRemoved:
            return "-"
        }
    }
}

struct SemanticDiff {
    let file: URL
    let changes: [SemanticChange]
    let lineRanges: [Range<Int>] // Line ranges where changes occurred
}

struct ASTSnapshot {
    let fileID: URL
    let ast: [ASTSymbol]
    let timestamp: Date
    let contentHash: String
}

class SemanticDiffService {
    static let shared = SemanticDiffService()
    
    private var astCache: [URL: ASTSnapshot] = [:]
    private let cacheQueue = DispatchQueue(label: "com.lingcode.semanticdiff", attributes: .concurrent)
    
    private init() {}
    
    /// Create AST snapshot for file
    func createSnapshot(for fileURL: URL) -> ASTSnapshot {
        let ast = ASTIndex.shared.getSymbolsSync(for: fileURL)
        let contentHash = computeContentHash(for: fileURL)
        
        let snapshot = ASTSnapshot(
            fileID: fileURL,
            ast: ast,
            timestamp: Date(),
            contentHash: contentHash
        )
        
        cacheQueue.async(flags: .barrier) {
            self.astCache[fileURL] = snapshot
        }
        
        return snapshot
    }
    
    /// Compute semantic diff between two states
    func computeSemanticDiff(
        before: ASTSnapshot,
        after: ASTSnapshot,
        fileURL: URL
    ) -> SemanticDiff {
        var changes: [SemanticChange] = []
        var lineRanges: [Range<Int>] = []
        
        // Match nodes by symbol ID, type, and range overlap
        let beforeMap = Dictionary(grouping: before.ast) { $0.name }
        let afterMap = Dictionary(grouping: after.ast) { $0.name }
        
        // Find renamed symbols
        for (name, beforeSymbols) in beforeMap {
            if let afterSymbols = afterMap[name] {
                // Symbol exists in both - check for changes
                for beforeSymbol in beforeSymbols {
                    if let afterSymbol = findMatchingSymbol(beforeSymbol, in: afterSymbols) {
                        // Check for type changes
                        if beforeSymbol.kind != afterSymbol.kind {
                            changes.append(.typeChanged(
                                before: kindToString(beforeSymbol.kind),
                                after: kindToString(afterSymbol.kind)
                            ))
                            lineRanges.append(afterSymbol.range)
                        }
                    } else {
                        // Symbol removed
                        changes.append(.functionRemoved(
                            name: name,
                            signature: name
                        ))
                        lineRanges.append(beforeSymbol.range)
                    }
                }
            } else {
                // Symbol removed
                for beforeSymbol in beforeSymbols {
                    changes.append(.functionRemoved(
                        name: name,
                        signature: name
                    ))
                    lineRanges.append(beforeSymbol.range)
                }
            }
        }
        
        // Find new symbols
        for (name, afterSymbols) in afterMap {
            if beforeMap[name] == nil {
                // New symbol
                for afterSymbol in afterSymbols {
                    changes.append(.functionAdded(
                        name: name,
                        signature: name
                    ))
                    lineRanges.append(afterSymbol.range)
                }
            }
        }
        
        // Detect renamed symbols (same location, different name)
        for beforeSymbol in before.ast {
            if let afterSymbol = findSymbolAtRange(beforeSymbol.range, in: after.ast),
               beforeSymbol.name != afterSymbol.name {
                changes.append(.renamedSymbol(
                    old: beforeSymbol.name,
                    new: afterSymbol.name,
                    symbolID: UUID() // Would use actual symbol ID
                ))
                lineRanges.append(afterSymbol.range)
            }
        }
        
        return SemanticDiff(
            file: fileURL,
            changes: changes,
            lineRanges: lineRanges
        )
    }
    
    /// Get semantic diff for file (before/after content)
    func getSemanticDiff(
        fileURL: URL,
        beforeContent: String?,
        afterContent: String
    ) -> SemanticDiff? {
        // Create before snapshot
        let beforeSnapshot: ASTSnapshot
        if let before = beforeContent {
            // Parse before AST
            let beforeAST = parseAST(from: before, fileURL: fileURL)
            beforeSnapshot = ASTSnapshot(
                fileID: fileURL,
                ast: beforeAST,
                timestamp: Date(),
                contentHash: before.hashValue.description
            )
        } else {
            // Get cached snapshot
            beforeSnapshot = cacheQueue.sync {
                return astCache[fileURL] ?? createSnapshot(for: fileURL)
            }
        }
        
        // Create after snapshot
        let afterAST = parseAST(from: afterContent, fileURL: fileURL)
        let afterSnapshot = ASTSnapshot(
            fileID: fileURL,
            ast: afterAST,
            timestamp: Date(),
            contentHash: afterContent.hashValue.description
        )
        
        // Compute diff
        return computeSemanticDiff(
            before: beforeSnapshot,
            after: afterSnapshot,
            fileURL: fileURL
        )
    }
    
    // MARK: - Helper Methods
    
    private func findMatchingSymbol(_ symbol: ASTSymbol, in candidates: [ASTSymbol]) -> ASTSymbol? {
        // Match by range overlap
        return candidates.first { candidate in
            rangesOverlap(symbol.range, candidate.range)
        }
    }
    
    private func findSymbolAtRange(_ range: Range<Int>, in symbols: [ASTSymbol]) -> ASTSymbol? {
        return symbols.first { symbol in
            rangesOverlap(range, symbol.range)
        }
    }
    
    private func rangesOverlap(_ range1: Range<Int>, _ range2: Range<Int>) -> Bool {
        return range1.overlaps(range2)
    }
    
    private func parseAST(from content: String, fileURL: URL) -> [ASTSymbol] {
        // Use ASTIndex to parse
        // For now, create temporary file and parse
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        let ast = ASTIndex.shared.getSymbolsSync(for: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return ast
    }
    
    private func computeContentHash(for fileURL: URL) -> String {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ""
        }
        return content.hashValue.description
    }
    
    private func kindToString(_ kind: ASTSymbol.Kind) -> String {
        switch kind {
        case .function: return "function"
        case .classSymbol: return "class"
        case .method: return "method"
        case .variable: return "variable"
        case .property: return "property"
        case .import: return "import"
        case .enumSymbol: return "enum"
        case .structSymbol: return "struct"
        case .protocolSymbol: return "protocol"
        case .extension: return "extension"
        }
    }
}

// Note: Range already has overlaps() method, no extension needed
