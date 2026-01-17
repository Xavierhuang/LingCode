//
//  TreeSitterBridge.swift
//  LingCode
//
//  Production-grade Polyglot AST parser
//  Supports: Swift (SwiftSyntax), Python/JS/TS/Go (Tree-sitter)
//

import Foundation

#if canImport(SwiftSyntax)
import SwiftSyntax
import SwiftParser
#endif

// Import EditorParsers to access TreeSitterSymbol and TreeSitterManager
#if canImport(EditorParsers)
import EditorParsers
#endif

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
        case `extension`
    }
    
    let name: String
    let kind: Kind
    let file: URL
    let range: Range<Int>
    let parent: String?
    let signature: String?
    let content: String?
}

// MARK: - SwiftSyntax-Based AST Parser

class SwiftSyntaxASTParser {
    static let shared = SwiftSyntaxASTParser()
    
    private var isSwiftSyntaxAvailable: Bool {
        #if canImport(SwiftSyntax)
        return true
        #else
        return false
        #endif
    }
    
    private init() {}
    
    /// Parse Swift file and extract AST symbols using SwiftSyntax
    func parseSwiftFile(_ fileURL: URL) -> [ASTSymbol] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        
        if isSwiftSyntaxAvailable {
            #if canImport(SwiftSyntax)
            return parseWithSwiftSyntax(content: content, fileURL: fileURL)
            #else
            return parseWithRegex(content: content, fileURL: fileURL)
            #endif
        } else {
            return parseWithRegex(content: content, fileURL: fileURL)
        }
    }
    
    #if canImport(SwiftSyntax)
    /// Real SwiftSyntax-based parsing (production-grade)
    private func parseWithSwiftSyntax(content: String, fileURL: URL) -> [ASTSymbol] {
        let sourceFile = Parser.parse(source: content)
        let sourceLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        let visitor = SymbolExtractorVisitor(fileURL: fileURL, sourceLocationConverter: sourceLocationConverter)
        visitor.walk(sourceFile)
        return visitor.symbols
    }
    
    /// SwiftSyntax visitor to extract symbols from AST
    private nonisolated class SymbolExtractorVisitor: SyntaxVisitor {
        var symbols: [ASTSymbol] = []
        let fileURL: URL
        let sourceLocationConverter: SourceLocationConverter
        var currentParent: String? = nil
        var parentStack: [String] = []
        
        init(fileURL: URL, sourceLocationConverter: SourceLocationConverter) {
            self.fileURL = fileURL
            self.sourceLocationConverter = sourceLocationConverter
            super.init(viewMode: .sourceAccurate)
        }
        
        private func getLine(_ position: AbsolutePosition) -> Int {
            let location = sourceLocationConverter.location(for: position)
            return location.line
        }
        
        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
            let endLine = getLine(node.endPositionBeforeTrailingTrivia)
            let signature = node.description
            
            parentStack.append(currentParent ?? "")
            currentParent = name
            
            symbols.append(ASTSymbol(
                name: name,
                kind: .classSymbol,
                file: fileURL,
                range: startLine..<endLine,
                parent: parentStack.last,
                signature: signature,
                content: node.description
            ))
            
            return .visitChildren
        }
        
        override func visitPost(_ node: ClassDeclSyntax) {
            if !parentStack.isEmpty {
                currentParent = parentStack.removeLast()
            }
        }
        
        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
            let endLine = getLine(node.endPositionBeforeTrailingTrivia)
            let signature = node.description
            
            parentStack.append(currentParent ?? "")
            currentParent = name
            
            symbols.append(ASTSymbol(
                name: name,
                kind: .structSymbol,
                file: fileURL,
                range: startLine..<endLine,
                parent: parentStack.last,
                signature: signature,
                content: node.description
            ))
            
            return .visitChildren
        }
        
        override func visitPost(_ node: StructDeclSyntax) {
            if !parentStack.isEmpty {
                currentParent = parentStack.removeLast()
            }
        }
        
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
            let endLine = getLine(node.endPositionBeforeTrailingTrivia)
            let signature = node.description
            
            parentStack.append(currentParent ?? "")
            currentParent = name
            
            symbols.append(ASTSymbol(
                name: name,
                kind: .enumSymbol,
                file: fileURL,
                range: startLine..<endLine,
                parent: parentStack.last,
                signature: signature,
                content: node.description
            ))
            
            return .visitChildren
        }
        
        override func visitPost(_ node: EnumDeclSyntax) {
            if !parentStack.isEmpty {
                currentParent = parentStack.removeLast()
            }
        }
        
        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
            let endLine = getLine(node.endPositionBeforeTrailingTrivia)
            let signature = node.description
            
            symbols.append(ASTSymbol(
                name: name,
                kind: .protocolSymbol,
                file: fileURL,
                range: startLine..<endLine,
                parent: currentParent,
                signature: signature,
                content: node.description
            ))
            
            return .visitChildren
        }
        
        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            if let extendedType = node.extendedType.as(IdentifierTypeSyntax.self) {
                let name = extendedType.name.text
                let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
                let endLine = getLine(node.endPositionBeforeTrailingTrivia)
                
                symbols.append(ASTSymbol(
                    name: name,
                    kind: .extension,
                    file: fileURL,
                    range: startLine..<endLine,
                    parent: currentParent,
                    signature: "extension \(name)",
                    content: node.description
                ))
            }
            
            return .visitChildren
        }
        
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
            let endLine = getLine(node.endPositionBeforeTrailingTrivia)
            let signature = node.signature.description
            let isStatic = node.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
            
            symbols.append(ASTSymbol(
                name: name,
                kind: (currentParent != nil || isStatic) ? .method : .function,
                file: fileURL,
                range: startLine..<endLine,
                parent: currentParent,
                signature: "func \(name)\(signature)",
                content: node.description
            ))
            
            return .visitChildren
        }
        
        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            for binding in node.bindings {
                if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                    let name = pattern.identifier.text
                    let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
                    let endLine = getLine(node.endPositionBeforeTrailingTrivia)
                    let isProperty = currentParent != nil
                    
                    symbols.append(ASTSymbol(
                        name: name,
                        kind: isProperty ? .property : .variable,
                        file: fileURL,
                        range: startLine..<endLine,
                        parent: currentParent,
                        signature: node.description,
                        content: node.description
                    ))
                }
            }
            
            return .visitChildren
        }
        
        override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
            let path = node.path.description
            let startLine = getLine(node.positionAfterSkippingLeadingTrivia)
            let endLine = getLine(node.endPositionBeforeTrailingTrivia)
            
            symbols.append(ASTSymbol(
                name: path,
                kind: .import,
                file: fileURL,
                range: startLine..<endLine,
                parent: nil,
                signature: "import \(path)",
                content: node.description
            ))
            
            return .visitChildren
        }
    }
    #endif
    
    /// Regex-based fallback (for non-Swift files or when SwiftSyntax unavailable)
    /// Parse non-Swift files using Tree-sitter (if available) or regex fallback
    func parseWithRegex(content: String, fileURL: URL) -> [ASTSymbol] {
        let ext = fileURL.pathExtension.lowercased()
        let language = mapExtensionToLanguage(ext)
        
        // Try Tree-sitter first (production-grade AST parsing)
        #if canImport(EditorParsers)
        if TreeSitterManager.shared.isLanguageSupported(language) {
            let treeSitterSymbols = TreeSitterManager.shared.parse(content: content, language: language, fileURL: fileURL)
            return treeSitterSymbols.map { tsSymbol in
                ASTSymbol(
                    name: tsSymbol.name,
                    kind: mapTreeSitterKindToASTKind(tsSymbol.kind),
                    file: tsSymbol.file,
                    range: tsSymbol.range,
                    parent: tsSymbol.parent, // Now includes parent hierarchy from resolveHierarchy
                    signature: tsSymbol.signature,
                    content: nil
                )
            }
        }
        #endif
        
        // Fallback to regex-based extraction
        return SwiftSyntaxParser.shared.extractSymbols(from: content, filePath: fileURL.path)
            .map { symbol in
                ASTSymbol(
                    name: symbol.name,
                    kind: mapCodeSymbolKind(symbol.kind),
                    file: fileURL,
                    range: 0..<0, // Regex can't provide accurate byte ranges
                    parent: nil,
                    signature: symbol.signature,
                    content: symbol.content
                )
            }
    }
    
    /// Map file extension to language identifier
    private func mapExtensionToLanguage(_ ext: String) -> String {
        switch ext {
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "typescript"
        case "go": return "go"
        default: return ext
        }
    }
    
    #if canImport(EditorParsers)
    /// Map Tree-sitter symbol kind to AST symbol kind
    private func mapTreeSitterKindToASTKind(_ kind: TreeSitterSymbol.Kind) -> ASTSymbol.Kind {
        switch kind {
        case .function: return .function
        case .classSymbol: return .classSymbol
        case .method: return .method
        case .variable: return .variable
        case .property: return .property
        }
    }
    #endif
    
    private func mapCodeSymbolKind(_ kind: CodeSymbol.Kind) -> ASTSymbol.Kind {
        switch kind {
        case .function: return .function
        case .class: return .classSymbol
        case .struct: return .structSymbol
        case .enum: return .enumSymbol
        case .protocol: return .protocolSymbol
        case .extension: return .extension
        case .variable: return .variable
        case .property: return .property
        case .method: return .method
        case .import: return .import
        }
    }
}

// MARK: - AST Index with Caching (Updated to use SwiftSyntax)

class ASTIndex {
    static let shared = ASTIndex()
    
    private var symbolCache: [URL: [ASTSymbol]] = [:]
    private var parseCache: [URL: (hash: String, symbols: [ASTSymbol])] = [:]
    private let cacheQueue = DispatchQueue(label: "com.lingcode.astindex", attributes: .concurrent)
    private let parser = SwiftSyntaxASTParser.shared
    
    private init() {}
    
    /// Get symbols for file (with caching)
    /// PERFORMANCE: Uses background queue to prevent main thread blocking
    /// 
    /// ⚠️ WARNING: This is synchronous and will block the calling thread during parsing.
    /// - Safe when called from background queues (e.g., CodebaseIndexService)
    /// - Will freeze UI if called directly from main thread on cache miss
    /// 
    /// For UI calls, use `getSymbolsAsync(for:completion:)` instead.
    func getSymbols(for fileURL: URL) -> [ASTSymbol] {
        // Fast path: Check cache (thread-safe read)
        return cacheQueue.sync {
            if let cached = symbolCache[fileURL] {
                return cached
            }
            
            // Parse file
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return []
            }
            
            // Check hash for incremental reparse
            let hash = String(content.hashValue)
            if let cached = parseCache[fileURL], cached.hash == hash {
                symbolCache[fileURL] = cached.symbols
                return cached.symbols
            }
            
            // PERFORMANCE: Parsing happens on background queue (cacheQueue)
            // SwiftSyntax parsing can take 10-100ms for large files
            // This prevents UI freezing when indexing thousands of files
            let symbols: [ASTSymbol]
            if fileURL.pathExtension.lowercased() == "swift" {
                // Swift: Use SwiftSyntax (production-grade)
                symbols = parser.parseSwiftFile(fileURL)
            } else {
                // Non-Swift: Try Tree-sitter first, fallback to regex
                // Tree-sitter provides AST-based parsing for Python/JS/TS/Go
                symbols = parser.parseWithRegex(content: content, fileURL: fileURL)
            }
            
            // Cache results
            symbolCache[fileURL] = symbols
            parseCache[fileURL] = (hash: hash, symbols: symbols)
            
            return symbols
        }
    }
    
    /// Async version for UI calls - prevents main thread blocking
    /// Use this when calling from SwiftUI views or main thread contexts
    func getSymbolsAsync(for fileURL: URL, completion: @escaping ([ASTSymbol]) -> Void) {
        // Fast path: Check cache synchronously (read-only, safe)
        if let cached = symbolCache[fileURL] {
            completion(cached)
            return
        }
        
        // Heavy work on background queue
        cacheQueue.async {
            let symbols = self.getSymbols(for: fileURL)
            DispatchQueue.main.async {
                completion(symbols)
            }
        }
    }
    
    /// Modern async/await version for UI calls
    /// Use this in SwiftUI views with Task { } blocks
    @available(macOS 12.0, *)
    func getSymbolsAsync(for fileURL: URL) async -> [ASTSymbol] {
        // Fast path: Check cache
        if let cached = symbolCache[fileURL] {
            return cached
        }
        
        // Heavy work on background
        return await withCheckedContinuation { continuation in
            cacheQueue.async {
                let symbols = self.getSymbols(for: fileURL)
                continuation.resume(returning: symbols)
            }
        }
    }
    
    
    /// Incremental reparse (invalidate and reparse)
    func reparse(fileURL: URL, editRange: Range<Int>, newText: String) {
        cacheQueue.async(flags: .barrier) {
            // Invalidate cache
            self.symbolCache.removeValue(forKey: fileURL)
            self.parseCache.removeValue(forKey: fileURL)
            
            // Reparse
            _ = self.getSymbols(for: fileURL)
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

// MARK: - Legacy TSQuery Interface (for backward compatibility)

struct TSQuery {
    let pattern: String
    let language: String
    
    func execute(on content: String, fileURL: URL) -> [ASTSymbol] {
        // Use SwiftSyntax parser for Swift files
        if fileURL.pathExtension.lowercased() == "swift" {
            return SwiftSyntaxASTParser.shared.parseSwiftFile(fileURL)
        }
        
        // For other languages, use Tree-sitter parsers
        return SwiftSyntaxParser.shared.extractSymbols(from: content, filePath: fileURL.path)
            .map { symbol in
                ASTSymbol(
                    name: symbol.name,
                    kind: mapCodeSymbolKind(symbol.kind),
                    file: fileURL,
                    range: 0..<0,
                    parent: nil,
                    signature: symbol.signature,
                    content: symbol.content
                )
            }
    }
    
    private func mapCodeSymbolKind(_ kind: CodeSymbol.Kind) -> ASTSymbol.Kind {
        switch kind {
        case .function: return .function
        case .class: return .classSymbol
        case .struct: return .structSymbol
        case .enum: return .enumSymbol
        case .protocol: return .protocolSymbol
        case .extension: return .extension
        case .variable: return .variable
        case .property: return .property
        case .method: return .method
        case .import: return .import
        }
    }
}
