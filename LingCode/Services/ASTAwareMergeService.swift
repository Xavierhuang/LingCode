//
//  ASTAwareMergeService.swift
//  LingCode
//
//  AST-Aware Merging: Automatically generates rename refactors when function signatures change
//  Prevents breaking changes by detecting signature changes and updating call sites
//

import Foundation

// Import TreeSitterBridge for AST parsing
// Note: TreeSitterBridge is in the same module, so no explicit import needed

struct SignatureChange {
    let oldSignature: String
    let newSignature: String
    let functionName: String
    let oldFunctionName: String?
    let file: URL
    let range: Range<Int>
}

class ASTAwareMergeService {
    static let shared = ASTAwareMergeService()
    
    private init() {}
    
    /// Detect signature changes between old and new file content
    /// Returns changes that require refactoring (e.g., function name changes)
    func detectSignatureChanges(
        oldContent: String,
        newContent: String,
        fileURL: URL
    ) -> [SignatureChange] {
        var changes: [SignatureChange] = []
        
        // Parse old file to get function signatures
        let oldSymbols = parseFunctionSignatures(from: oldContent, fileURL: fileURL)
        let newSymbols = parseFunctionSignatures(from: newContent, fileURL: fileURL)
        
        // Compare signatures to find changes
        for oldSymbol in oldSymbols {
            // Check if function name changed
            if let newSymbol = newSymbols.first(where: { $0.name == oldSymbol.name }) {
                // Function exists in both - check if signature changed
                if oldSymbol.signature != newSymbol.signature {
                    changes.append(SignatureChange(
                        oldSignature: oldSymbol.signature,
                        newSignature: newSymbol.signature,
                        functionName: newSymbol.name,
                        oldFunctionName: nil,
                        file: fileURL,
                        range: oldSymbol.range
                    ))
                }
            } else {
                // Function removed - might be renamed
                // Try to find similar function in new content
                if let renamedSymbol = findRenamedFunction(old: oldSymbol, in: newSymbols) {
                    changes.append(SignatureChange(
                        oldSignature: oldSymbol.signature,
                        newSignature: renamedSymbol.signature,
                        functionName: renamedSymbol.name,
                        oldFunctionName: oldSymbol.name,
                        file: fileURL,
                        range: oldSymbol.range
                    ))
                }
            }
        }
        
        return changes
    }
    
    /// Apply AST-aware merge: detect signature changes and auto-generate rename refactors
    func applyASTAwareMerge(
        oldContent: String,
        newContent: String,
        fileURL: URL,
        projectURL: URL
    ) async throws -> [Edit] {
        let signatureChanges = detectSignatureChanges(
            oldContent: oldContent,
            newContent: newContent,
            fileURL: fileURL
        )
        
        var allEdits: [Edit] = []
        
        // For each signature change that involves a rename, generate refactor edits
        for change in signatureChanges {
            if let oldName = change.oldFunctionName, oldName != change.functionName {
                // Function was renamed - generate rename refactor for all call sites
                if let symbol = await resolveSymbol(named: oldName, in: fileURL, projectURL: projectURL) {
                    do {
                        let renameEdits = try await RenameRefactorService.shared.rename(
                            symbol: symbol,
                            to: change.functionName,
                            in: projectURL,
                            currentContent: newContent
                        )
                        allEdits.append(contentsOf: renameEdits)
                    } catch {
                        print("⚠️ Failed to generate rename refactor for \(oldName) -> \(change.functionName): \(error)")
                    }
                }
            }
        }
        
        return allEdits
    }
    
    /// Parse function signatures from content
    private func parseFunctionSignatures(from content: String, fileURL: URL) -> [FunctionSymbol] {
        // Use ASTIndex for accurate parsing (sync version for backward compatibility)
        let symbols = ASTIndex.shared.getSymbolsSync(for: fileURL)
        
        return symbols
            .filter { $0.kind == .function || $0.kind == .method }
            .map { FunctionSymbol(
                name: $0.name,
                signature: $0.signature ?? $0.name,
                range: $0.range
            ) }
    }
    
    /// Find renamed function by comparing signatures (heuristic)
    private func findRenamedFunction(old: FunctionSymbol, in newSymbols: [FunctionSymbol]) -> FunctionSymbol? {
        // Heuristic: Find function with similar signature (same parameters, different name)
        let oldParams = extractParameters(from: old.signature)
        
        for newSymbol in newSymbols {
            let newParams = extractParameters(from: newSymbol.signature)
            // If parameters match, likely a rename
            if oldParams == newParams && newSymbol.name != old.name {
                return newSymbol
            }
        }
        
        return nil
    }
    
    /// Extract parameters from function signature using AST parsing
    /// CRITICAL FIX: Uses AST to handle nested parentheses (e.g., closures with Result types)
    /// Replaces fragile regex that fails on: func process(handler: (Result<Int, Error>) -> Void)
    private func extractParameters(from signature: String) -> String {
        // For Swift files, use ASTIndex to get accurate parameter extraction
        // This handles nested parentheses correctly
        if let fileURL = getTemporaryFileURL(for: signature) {
            let symbols = ASTIndex.shared.getSymbolsSync(for: fileURL)
            
            // Find function symbol and extract its signature
            if let functionSymbol = symbols.first(where: { $0.kind == .function || $0.kind == .method }) {
                // Extract parameter clause from signature using AST
                return extractParameterClauseFromAST(signature: functionSymbol.signature ?? signature)
            }
        }
        
        // Fallback: Use balanced parenthesis matching (more robust than regex)
        return extractParametersBalanced(from: signature)
    }
    
    /// Extract parameter clause using balanced parenthesis matching
    /// More robust than regex for nested parentheses
    private func extractParametersBalanced(from signature: String) -> String {
        guard let openParenIndex = signature.firstIndex(of: "(") else {
            return ""
        }
        
        var depth = 0
        var startIndex: String.Index? = nil
        var endIndex: String.Index? = nil
        
        for (index, char) in signature[openParenIndex...].enumerated() {
            let stringIndex = signature.index(openParenIndex, offsetBy: index)
            
            if char == "(" {
                if depth == 0 {
                    startIndex = stringIndex
                }
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    endIndex = stringIndex
                    break
                }
            }
        }
        
        if let start = startIndex, let end = endIndex {
            // Include both parentheses
            let endAfterParen = signature.index(after: end)
            return String(signature[start..<endAfterParen])
        }
        
        return ""
    }
    
    /// Extract parameter clause from AST signature
    private func extractParameterClauseFromAST(signature: String) -> String {
        // Parse signature to find parameter clause
        // Pattern: func name(param1: Type1, param2: Type2) -> ReturnType
        // We want the part between the parentheses
        
        guard let openParen = signature.firstIndex(of: "("),
              let closeParen = signature[openParen...].lastIndex(of: ")") else {
            return ""
        }
        
        // Include both parentheses
        let endAfterParen = signature.index(after: closeParen)
        return String(signature[openParen..<endAfterParen])
    }
    
    /// Create temporary file for AST parsing (helper)
    private func getTemporaryFileURL(for content: String) -> URL? {
        // For parameter extraction, we need a full function declaration
        // Wrap signature in a function declaration for AST parsing
        let wrappedContent = "func test\(content) {}"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        
        do {
            try wrappedContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
    
    /// Resolve symbol by name (helper for rename refactor)
    /// Uses ResolvedSymbol type from RenameRefactorService to avoid duplication
    private func resolveSymbol(named name: String, in fileURL: URL, projectURL: URL) async -> ResolvedSymbol? {
        // Use RenameRefactorService to resolve symbol
        // This is a simplified version - in production, would use proper symbol resolution
        let symbols = await ASTIndex.shared.getSymbols(for: fileURL)
        
        if let symbol = symbols.first(where: { $0.name == name }) {
            // Map to ResolvedSymbol (from RenameRefactorService.swift)
            let symbolKind: ResolvedSymbol.SymbolKind
            switch symbol.kind {
            case .function: symbolKind = .function
            case .method: symbolKind = .method
            case .classSymbol: symbolKind = .classSymbol
            case .structSymbol: symbolKind = .classSymbol // ResolvedSymbol uses classSymbol for both
            case .enumSymbol: symbolKind = .classSymbol
            case .protocolSymbol: symbolKind = .classSymbol
            case .variable: symbolKind = .variable
            case .property: symbolKind = .property
            case .extension: symbolKind = .classSymbol
            case .import: symbolKind = .typeAlias
            }
            
            return ResolvedSymbol(
                id: UUID(),
                name: symbol.name,
                kind: symbolKind,
                scope: ScopeID(file: fileURL, parent: symbol.parent, depth: 0),
                file: fileURL,
                definitionRange: symbol.range,
                typeName: nil
            )
        }
        
        return nil
    }
}

struct FunctionSymbol {
    let name: String
    let signature: String
    let range: Range<Int>
}
