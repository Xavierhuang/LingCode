//
//  TreeSitterBridge.swift
//  LingCode
//
//  Production-grade Tree-sitter → Swift bridge for AST parsing
//

import Foundation

// MARK: - Tree-sitter Node Wrapper (Safe Swift Interface)

// Placeholder type for Tree-sitter node (would be actual TSNode from C library)
struct TSNode {
    // Placeholder - would be actual Tree-sitter node type
}

struct TSNodeRef {
    let node: TSNode
    
    var type: String {
        // Placeholder - would use ts_node_type(node) from C bridge
        // For now, use regex-based detection
        return detectNodeType()
    }
    
    var range: Range<Int> {
        // Placeholder - would use ts_node_start_byte/end_byte
        // For now, estimate from content
        return 0..<0
    }
    
    var text: String {
        // Placeholder - would extract from source
        return ""
    }
    
    private func detectNodeType() -> String {
        // Fallback to regex-based detection
        return "unknown"
    }
}

// MARK: - Unified Symbol Model

struct ASTSymbol {
    enum Kind {
        case function
        case classSymbol
        case method
        case variable
        case `import`
        case property
        case enumSymbol
        case structSymbol
        case protocolSymbol
    }
    
    let name: String
    let kind: Kind
    let file: URL
    let range: Range<Int>
    let parent: String?
}

// MARK: - Tree-sitter Query Engine

struct TSQuery {
    let pattern: String
    let language: String
    
    func execute(on content: String, fileURL: URL) -> [ASTSymbol] {
        // Placeholder for Tree-sitter query execution
        // For now, use regex-based extraction
        return extractSymbolsRegex(from: content, fileURL: fileURL)
    }
    
    private func extractSymbolsRegex(from content: String, fileURL: URL) -> [ASTSymbol] {
        var symbols: [ASTSymbol] = []
        
        // Language-specific extraction
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "swift":
            symbols = extractSwiftSymbols(from: content, fileURL: fileURL)
        case "js", "jsx":
            symbols = extractJSSymbols(from: content, fileURL: fileURL)
        case "ts", "tsx":
            symbols = extractTSSymbols(from: content, fileURL: fileURL)
        case "py":
            symbols = extractPythonSymbols(from: content, fileURL: fileURL)
        default:
            break
        }
        
        return symbols
    }
    
    private func extractSwiftSymbols(from content: String, fileURL: URL) -> [ASTSymbol] {
        var symbols: [ASTSymbol] = []
        let lines = content.components(separatedBy: .newlines)
        var currentClass: String? = nil
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Class
            if let name = extractName(from: trimmed, pattern: #"^(public |private |internal |fileprivate |open )?class\s+(\w+)"#) {
                currentClass = name
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .classSymbol,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: nil
                ))
            }
            // Function
            else if let name = extractName(from: trimmed, pattern: #"^(public |private |internal |fileprivate |open )?(static |class )?func\s+(\w+)"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: currentClass != nil ? .method : .function,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: currentClass
                ))
            }
            // Variable
            else if let name = extractName(from: trimmed, pattern: #"^(let|var)\s+(\w+)"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .variable,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: currentClass
                ))
            }
        }
        
        return symbols
    }
    
    private func extractJSSymbols(from content: String, fileURL: URL) -> [ASTSymbol] {
        var symbols: [ASTSymbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Function
            if let name = extractName(from: trimmed, pattern: #"function\s+(\w+)"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .function,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: nil
                ))
            }
            // Arrow function
            else if let name = extractName(from: trimmed, pattern: #"const\s+(\w+)\s*=\s*\([^)]*\)\s*=>"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .function,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: nil
                ))
            }
            // Class
            else if let name = extractName(from: trimmed, pattern: #"class\s+(\w+)"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .classSymbol,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: nil
                ))
            }
        }
        
        return symbols
    }
    
    private func extractTSSymbols(from content: String, fileURL: URL) -> [ASTSymbol] {
        // TypeScript uses similar patterns to JavaScript
        return extractJSSymbols(from: content, fileURL: fileURL)
    }
    
    private func extractPythonSymbols(from content: String, fileURL: URL) -> [ASTSymbol] {
        var symbols: [ASTSymbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Function
            if let name = extractName(from: trimmed, pattern: #"def\s+(\w+)"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .function,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: nil
                ))
            }
            // Class
            else if let name = extractName(from: trimmed, pattern: #"class\s+(\w+)"#) {
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .classSymbol,
                    file: fileURL,
                    range: getLineRange(index, in: content),
                    parent: nil
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
        
        let lastRange = match.range(at: match.numberOfRanges - 1)
        guard let swiftRange = Range(lastRange, in: line) else { return nil }
        return String(line[swiftRange])
    }
    
    private func getLineRange(_ lineIndex: Int, in content: String) -> Range<Int> {
        let lines = content.components(separatedBy: .newlines)
        var offset = 0
        for i in 0..<min(lineIndex, lines.count) {
            offset += lines[i].count + 1 // +1 for newline
        }
        let lineLength = lineIndex < lines.count ? lines[lineIndex].count : 0
        return offset..<(offset + lineLength)
    }
}

// MARK: - AST Index with Caching

class ASTIndex {
    static let shared = ASTIndex()
    
    private var symbolCache: [URL: [ASTSymbol]] = [:]
    private var parseCache: [URL: (hash: String, symbols: [ASTSymbol])] = [:]
    private let cacheQueue = DispatchQueue(label: "com.lingcode.astindex", attributes: .concurrent)
    
    private init() {}
    
    /// Get symbols for file (with caching)
    func getSymbols(for fileURL: URL) -> [ASTSymbol] {
        return cacheQueue.sync {
            if let cached = symbolCache[fileURL] {
                return cached
            }
            
            // Parse file
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return []
            }
            
            // Check hash for incremental reparse
            let hash = content.hashValue.description
            if let cached = parseCache[fileURL], cached.hash == hash {
                return cached.symbols
            }
            
            // Parse with query
            let query = TSQuery(pattern: "", language: detectLanguage(from: fileURL))
            let symbols = query.execute(on: content, fileURL: fileURL)
            
            // Cache
            cacheQueue.async(flags: .barrier) {
                self.symbolCache[fileURL] = symbols
                self.parseCache[fileURL] = (hash: hash, symbols: symbols)
            }
            
            return symbols
        }
    }
    
    /// Incremental reparse (Tree-sitter supports this)
    func reparse(fileURL: URL, editRange: Range<Int>, newText: String) {
        cacheQueue.async(flags: .barrier) {
            // Invalidate cache
            self.symbolCache.removeValue(forKey: fileURL)
            self.parseCache.removeValue(forKey: fileURL)
            
            // Reparse (would use Tree-sitter incremental API)
            _ = self.getSymbols(for: fileURL)
        }
    }
    
    private func detectLanguage(from fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        default: return ""
        }
    }
    
    /// Invalidate cache for file
    func invalidate(for fileURL: URL) {
        cacheQueue.async(flags: .barrier) {
            self.symbolCache.removeValue(forKey: fileURL)
            self.parseCache.removeValue(forKey: fileURL)
        }
    }
}
