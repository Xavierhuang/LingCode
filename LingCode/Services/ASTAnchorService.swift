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
        }
    }
    
    /// Parse symbols from file (language-agnostic regex-based parser)
    private func parseSymbols(from fileURL: URL) -> [SymbolLocation] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        
        let ext = fileURL.pathExtension.lowercased()
        let language = detectLanguage(from: ext)
        
        switch language {
        case "swift":
            return parseSwiftSymbols(from: content)
        case "javascript", "typescript":
            return parseJSSymbols(from: content)
        case "python":
            return parsePythonSymbols(from: content)
        default:
            return []
        }
    }
    
    private func detectLanguage(from extension: String) -> String {
        switch `extension` {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        default: return ""
        }
    }
    
    private func parseSwiftSymbols(from content: String) -> [SymbolLocation] {
        var symbols: [SymbolLocation] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentClass: String? = nil
        var classMethodIndex = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Class
            if let name = extractName(from: trimmed, pattern: #"^(public |private |internal |fileprivate |open )?class\s+(\w+)"#) {
                currentClass = name
                classMethodIndex = 0
                symbols.append(SymbolLocation(
                    name: name,
                    type: .classSymbol,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
            // Struct
            else if let name = extractName(from: trimmed, pattern: #"^(public |private |internal |fileprivate )?struct\s+(\w+)"#) {
                symbols.append(SymbolLocation(
                    name: name,
                    type: .structSymbol,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
            // Function
            else if let name = extractName(from: trimmed, pattern: #"^(public |private |internal |fileprivate |open )?(static |class )?func\s+(\w+)"#) {
                let endLine = findEndOfBlock(startingAt: index, in: lines)
                symbols.append(SymbolLocation(
                    name: name,
                    type: currentClass != nil ? .method : .function,
                    startLine: index + 1,
                    endLine: endLine,
                    parent: currentClass,
                    childIndex: currentClass != nil ? classMethodIndex : nil
                ))
                if currentClass != nil {
                    classMethodIndex += 1
                }
            }
        }
        
        return symbols
    }
    
    private func parseJSSymbols(from content: String) -> [SymbolLocation] {
        var symbols: [SymbolLocation] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Function
            if let name = extractName(from: trimmed, pattern: #"function\s+(\w+)"#) {
                symbols.append(SymbolLocation(
                    name: name,
                    type: .function,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
            // Arrow function
            else if let name = extractName(from: trimmed, pattern: #"const\s+(\w+)\s*=\s*\([^)]*\)\s*=>"#) {
                symbols.append(SymbolLocation(
                    name: name,
                    type: .function,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
            // Class
            else if let name = extractName(from: trimmed, pattern: #"class\s+(\w+)"#) {
                symbols.append(SymbolLocation(
                    name: name,
                    type: .classSymbol,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
        }
        
        return symbols
    }
    
    private func parsePythonSymbols(from content: String) -> [SymbolLocation] {
        var symbols: [SymbolLocation] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Function
            if let name = extractName(from: trimmed, pattern: #"def\s+(\w+)"#) {
                symbols.append(SymbolLocation(
                    name: name,
                    type: .function,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
            // Class
            else if let name = extractName(from: trimmed, pattern: #"class\s+(\w+)"#) {
                symbols.append(SymbolLocation(
                    name: name,
                    type: .classSymbol,
                    startLine: index + 1,
                    endLine: findEndOfBlock(startingAt: index, in: lines),
                    parent: nil,
                    childIndex: nil
                ))
            }
        }
        
        return symbols
    }
    
    private func extractName(from line: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) else {
            return nil
        }
        
        // Get the last capture group (the name)
        let lastRange = match.range(at: match.numberOfRanges - 1)
        guard let swiftRange = Range(lastRange, in: line) else { return nil }
        return String(line[swiftRange])
    }
    
    private func findEndOfBlock(startingAt startIndex: Int, in lines: [String]) -> Int {
        var braceCount = 0
        var inBlock = false
        
        for i in startIndex..<lines.count {
            let line = lines[i]
            
            for char in line {
                if char == "{" {
                    braceCount += 1
                    inBlock = true
                } else if char == "}" {
                    braceCount -= 1
                    if inBlock && braceCount == 0 {
                        return i + 1
                    }
                }
            }
            
            // Python: check for dedent
            if !inBlock && i > startIndex {
                let currentIndent = lines[i].prefix(while: { $0 == " " || $0 == "\t" }).count
                let startIndent = lines[startIndex].prefix(while: { $0 == " " || $0 == "\t" }).count
                if currentIndent <= startIndent && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    return i
                }
            }
        }
        
        return lines.count
    }
    
    /// Invalidate cache for a file
    func invalidateCache(for fileURL: URL) {
        cacheQueue.async(flags: .barrier) {
            self.symbolCache.removeValue(forKey: fileURL)
        }
    }
}
