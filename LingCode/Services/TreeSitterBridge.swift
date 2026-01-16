//
//  TreeSitterBridge.swift
//  LingCode
//
//  Production-grade SwiftSyntax-based AST parser
//  Replaces regex-based simulation with real AST parsing
//

import Foundation

#if canImport(SwiftSyntax)
import SwiftSyntax
import SwiftParser
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
        let sourceLocationConverter = SourceLocationConverter(file: fileURL.path, tree: sourceFile)
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
            return location.line ?? 1
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
    func parseWithRegex(content: String, fileURL: URL) -> [ASTSymbol] {
        // Use SwiftSyntaxParser's regex fallback for consistency
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
            let hash = String(content.hashValue)
            if let cached = parseCache[fileURL], cached.hash == hash {
                return cached.symbols
            }
            
            // Parse with SwiftSyntax (or regex fallback)
            let symbols: [ASTSymbol]
            if fileURL.pathExtension.lowercased() == "swift" {
                symbols = parser.parseSwiftFile(fileURL)
            } else {
                // For non-Swift files, use regex-based extraction
                symbols = parser.parseWithRegex(content: content, fileURL: fileURL)
            }
            
            // Cache
            cacheQueue.async(flags: .barrier) {
                self.symbolCache[fileURL] = symbols
                self.parseCache[fileURL] = (hash: hash, symbols: symbols)
            }
            
            return symbols
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
        
        // For other languages, use regex fallback
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
