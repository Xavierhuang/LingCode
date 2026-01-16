//
//  ASTAnchorService.swift
//  LingCode
//
//  AST-anchored edits with symbol-based resolution and fallback to line ranges
//

import Foundation

struct SymbolLocation {
    let name: String
    let type: Anchor.AnchorType
    let startLine: Int
    let endLine: Int
    let parent: String?
    let childIndex: Int?
}

class ASTAnchorService {
    static let shared = ASTAnchorService()
    
    private var symbolCache: [URL: [SymbolLocation]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.lingcode.astcache", attributes: .concurrent)
    
    // Use ASTIndex for better performance
    private let astIndex = ASTIndex.shared
    
    private init() {}
    
    /// Resolve anchor to line range (best → worst priority)
    func resolveAnchor(_ anchor: Anchor, in fileURL: URL) -> EditRange? {
        // Priority 1: Symbol ID (function/class/method name)
        if let location = findSymbol(named: anchor.name, type: anchor.type, in: fileURL) {
            return EditRange(startLine: location.startLine, endLine: location.endLine)
        }
        
        // Priority 2: AST node type + name (already tried above)
        // Priority 3: Parent + child index
        if let parent = anchor.parent, let childIndex = anchor.childIndex {
            if let location = findSymbolInParent(parent, childIndex: childIndex, in: fileURL) {
                return EditRange(startLine: location.startLine, endLine: location.endLine)
            }
        }
        
        // Priority 4: Fallback to line range (handled by caller)
        return nil
    }
    
    /// Find symbol by name and type
    private func findSymbol(named name: String, type: Anchor.AnchorType, in fileURL: URL) -> SymbolLocation? {
        let symbols = getSymbols(for: fileURL)
        return symbols.first { $0.name == name && $0.type == type }
    }
    
    /// Find symbol by parent and child index
    private func findSymbolInParent(_ parentName: String, childIndex: Int, in fileURL: URL) -> SymbolLocation? {
        let symbols = getSymbols(for: fileURL)
        let parentSymbols = symbols.filter { $0.parent == parentName }
        guard childIndex < parentSymbols.count else { return nil }
        return parentSymbols[childIndex]
    }
    
    /// Get symbols for a file (with caching)
    func getSymbols(for fileURL: URL) -> [SymbolLocation] {
        // Use ASTIndex for better performance
        let astSymbols = astIndex.getSymbols(for: fileURL)
        
        // Convert ASTSymbol to SymbolLocation
        return astSymbols.map { astSymbol in
            SymbolLocation(
                name: astSymbol.name,
                type: convertKind(astSymbol.kind),
                startLine: astSymbol.range.lowerBound,
                endLine: astSymbol.range.upperBound,
                parent: astSymbol.parent,
                childIndex: nil
            )
        }
    }
    
    private func convertKind(_ kind: ASTSymbol.Kind) -> Anchor.AnchorType {
        switch kind {
        case .function: return .function
        case .classSymbol: return .classSymbol
        case .method: return .method
        case .structSymbol: return .structSymbol
        case .enumSymbol: return .enumSymbol
        case .protocolSymbol: return .protocolSymbol
        case .property: return .property
        case .variable: return .variable
        case .import: return .function // Fallback
        case .extension: return .function // Fallback
        }
    }
    
    /// Invalidate cache for a file
    func invalidateCache(for fileURL: URL) {
        cacheQueue.async(flags: .barrier) {
            self.symbolCache.removeValue(forKey: fileURL)
        }
    }
}
