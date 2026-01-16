//
//  SwiftSyntaxParser.swift
//  LingCode
//
//  Modern code parser using SwiftSyntax (REQUIRED)
//  SwiftSyntax is a required dependency - no regex fallback
//

import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Code Symbol Model

struct CodeSymbol {
    enum Kind {
        case function
        case `class`
        case `struct`
        case `enum`
        case `protocol`
        case `extension`
        case variable
        case property
        case method
        case `import`
    }
    
    let name: String
    let kind: Kind
    let filePath: String
    let startLine: Int
    let endLine: Int
    let signature: String // Full signature for context
    let content: String // Full content of the symbol
}

// MARK: - SwiftSyntax Parser (Required)

class SwiftSyntaxParser {
    static let shared = SwiftSyntaxParser()
    
    private init() {}
    
    /// Extract symbols from Swift code using SwiftSyntax
    /// Throws if parsing fails - SwiftSyntax is required
    func extractSymbols(from content: String, filePath: String) -> [CodeSymbol] {
        do {
            return try extractSymbolsWithSwiftSyntax(from: content, filePath: filePath)
        } catch {
            // Log error but return empty array rather than crashing
            print("⚠️ SwiftSyntax parsing failed for \(filePath): \(error.localizedDescription)")
            print("   This file may contain syntax errors or unsupported Swift features.")
            return []
        }
    }
    
    /// Extract symbols using SwiftSyntax (robust AST parsing)
    private func extractSymbolsWithSwiftSyntax(from content: String, filePath: String) throws -> [CodeSymbol] {
        let sourceFile = Parser.parse(source: content)
        let sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        let visitor = SymbolExtractorVisitor(filePath: filePath, sourceLocationConverter: sourceLocationConverter)
        visitor.walk(sourceFile)
        return visitor.symbols
    }
    
    /// SwiftSyntax visitor to extract symbols
    private nonisolated class SymbolExtractorVisitor: SyntaxVisitor {
        var symbols: [CodeSymbol] = []
        let filePath: String
        let sourceLocationConverter: SourceLocationConverter
        var currentParent: String? = nil
        var parentStack: [String] = []
        
        init(filePath: String, sourceLocationConverter: SourceLocationConverter) {
            self.filePath = filePath
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
            
            symbols.append(CodeSymbol(
                name: name,
                kind: .class,
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
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
            
            symbols.append(CodeSymbol(
                name: name,
                kind: .struct,
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
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
            
            symbols.append(CodeSymbol(
                name: name,
                kind: .enum,
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
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
            
            symbols.append(CodeSymbol(
                name: name,
                kind: .protocol,
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
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
                
                symbols.append(CodeSymbol(
                    name: name,
                    kind: .extension,
                    filePath: filePath,
                    startLine: startLine,
                    endLine: endLine,
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
            
            symbols.append(CodeSymbol(
                name: name,
                kind: (currentParent != nil || isStatic) ? .method : .function,
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
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
                    
                    symbols.append(CodeSymbol(
                        name: name,
                        kind: isProperty ? .property : .variable,
                        filePath: filePath,
                        startLine: startLine,
                        endLine: endLine,
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
            
            symbols.append(CodeSymbol(
                name: path,
                kind: .import,
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
                signature: "import \(path)",
                content: node.description
            ))
            
            return .visitChildren
        }
    }
    
    /// Extract a specific symbol by name and kind
    func extractSymbol(named name: String, kind: CodeSymbol.Kind, from content: String, filePath: String) -> CodeSymbol? {
        let symbols = extractSymbols(from: content, filePath: filePath)
        return symbols.first { $0.name == name && $0.kind == kind }
    }
    
    /// Extract symbols matching a query (for semantic search)
    func searchSymbols(query: String, in content: String, filePath: String) -> [CodeSymbol] {
        let allSymbols = extractSymbols(from: content, filePath: filePath)
        let queryLower = query.lowercased()
        
        return allSymbols.filter { symbol in
            symbol.name.lowercased().contains(queryLower) ||
            symbol.signature.lowercased().contains(queryLower) ||
            symbol.content.lowercased().contains(queryLower)
        }
    }
}
