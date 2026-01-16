//
//  SwiftSyntaxParser.swift
//  LingCode
//
//  Modern code parser using SwiftSyntax (with regex fallback)
//  Replaces brittle regex parsing with robust AST-based extraction
//

import Foundation

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

// MARK: - SwiftSyntax Parser (Optional)

class SwiftSyntaxParser {
    static let shared = SwiftSyntaxParser()
    
    private var isSwiftSyntaxAvailable: Bool {
        // Check if SwiftSyntax is available at runtime
        // This will be true once the package is added to the project
        #if canImport(SwiftSyntax)
        return true
        #else
        return false
        #endif
    }
    
    private init() {}
    
    /// Extract symbols from Swift code using SwiftSyntax (or regex fallback)
    func extractSymbols(from content: String, filePath: String) -> [CodeSymbol] {
        if isSwiftSyntaxAvailable {
            return extractSymbolsWithSwiftSyntax(from: content, filePath: filePath)
        } else {
            return extractSymbolsWithRegex(from: content, filePath: filePath)
        }
    }
    
    /// Extract symbols using SwiftSyntax (robust AST parsing)
    private func extractSymbolsWithSwiftSyntax(from content: String, filePath: String) -> [CodeSymbol] {
        #if canImport(SwiftSyntax)
        // TODO: Implement SwiftSyntax parsing once package is added
        // This will use SwiftSyntax's SyntaxVisitor to walk the AST
        // and extract function/class/struct definitions robustly
        
        // Placeholder implementation - will be replaced with actual SwiftSyntax code
        return extractSymbolsWithRegex(from: content, filePath: filePath)
        #else
        return extractSymbolsWithRegex(from: content, filePath: filePath)
        #endif
    }
    
    /// Extract symbols using regex (fallback for when SwiftSyntax isn't available)
    private func extractSymbolsWithRegex(from content: String, filePath: String) -> [CodeSymbol] {
        var symbols: [CodeSymbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Track nested structures for accurate line ranges
        var braceDepth = 0
        var currentSymbol: (name: String, kind: CodeSymbol.Kind, startLine: Int, signature: String)? = nil
        var symbolContent: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Count braces for structure tracking
            braceDepth += line.filter { $0 == "{" }.count
            braceDepth -= line.filter { $0 == "}" }.count
            
            // Detect function definitions
            if let match = extractFunctionDefinition(from: trimmed) {
                // Save previous symbol if exists
                if let prev = currentSymbol {
                    symbols.append(CodeSymbol(
                        name: prev.name,
                        kind: prev.kind,
                        filePath: filePath,
                        startLine: prev.startLine,
                        endLine: index - 1,
                        signature: prev.signature,
                        content: symbolContent.joined(separator: "\n")
                    ))
                }
                
                currentSymbol = (match.name, match.kind, index + 1, match.signature)
                symbolContent = [line]
                continue
            }
            
            // Detect class/struct/enum/protocol definitions
            if let match = extractTypeDefinition(from: trimmed) {
                if let prev = currentSymbol {
                    symbols.append(CodeSymbol(
                        name: prev.name,
                        kind: prev.kind,
                        filePath: filePath,
                        startLine: prev.startLine,
                        endLine: index - 1,
                        signature: prev.signature,
                        content: symbolContent.joined(separator: "\n")
                    ))
                }
                
                currentSymbol = (match.name, match.kind, index + 1, match.signature)
                symbolContent = [line]
                continue
            }
            
            // Accumulate content for current symbol
            if currentSymbol != nil {
                symbolContent.append(line)
                
                // End symbol when brace depth returns to 0 (or negative)
                if braceDepth <= 0 && !trimmed.isEmpty {
                    if let prev = currentSymbol {
                        symbols.append(CodeSymbol(
                            name: prev.name,
                            kind: prev.kind,
                            filePath: filePath,
                            startLine: prev.startLine,
                            endLine: index,
                            signature: prev.signature,
                            content: symbolContent.joined(separator: "\n")
                        ))
                    }
                    currentSymbol = nil
                    symbolContent = []
                }
            }
        }
        
        // Add final symbol if exists
        if let prev = currentSymbol {
            symbols.append(CodeSymbol(
                name: prev.name,
                kind: prev.kind,
                filePath: filePath,
                startLine: prev.startLine,
                endLine: lines.count,
                signature: prev.signature,
                content: symbolContent.joined(separator: "\n")
            ))
        }
        
        return symbols
    }
    
    // MARK: - Regex Helpers
    
    private func extractFunctionDefinition(from line: String) -> (name: String, kind: CodeSymbol.Kind, signature: String)? {
        // Match: func functionName(...) or func functionName<T>(...)
        let patterns = [
            #"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:static\s+|class\s+)?func\s+(\w+)"#,
            #"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:static\s+|class\s+)?func\s+(\w+)\s*<"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
               let nameRange = Range(match.range(at: 1), in: line) {
                let name = String(line[nameRange])
                let kind: CodeSymbol.Kind = line.contains("static") || line.contains("class") ? .method : .function
                return (name, kind, line.trimmingCharacters(in: .whitespaces))
            }
        }
        
        return nil
    }
    
    private func extractTypeDefinition(from line: String) -> (name: String, kind: CodeSymbol.Kind, signature: String)? {
        let patterns: [(String, CodeSymbol.Kind)] = [
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?class\s+(\w+)"#, .class),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?struct\s+(\w+)"#, .struct),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?enum\s+(\w+)"#, .enum),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?protocol\s+(\w+)"#, .protocol),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?extension\s+(\w+)"#, .extension)
        ]
        
        for (pattern, kind) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
               let nameRange = Range(match.range(at: 1), in: line) {
                let name = String(line[nameRange])
                return (name, kind, line.trimmingCharacters(in: .whitespaces))
            }
        }
        
        return nil
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
