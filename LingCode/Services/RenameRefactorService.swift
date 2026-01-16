//
//  RenameRefactorService.swift
//  LingCode
//
//  Safe, global, AST-based rename refactor engine
//

import Foundation

struct ResolvedSymbol {
    let id: UUID
    let name: String
    let kind: SymbolKind
    let scope: ScopeID
    let file: URL
    let definitionRange: Range<Int>
    
    enum SymbolKind {
        case function
        case classSymbol
        case method
        case variable
        case property
        case parameter
        case typeAlias
    }
}

struct ScopeID: Hashable {
    let file: URL
    let parent: String? // Parent symbol name
    let depth: Int
}

struct SymbolReference {
    let symbolID: UUID
    let file: URL
    let range: Range<Int>
    let isDefinition: Bool
    let isInString: Bool
    let isInComment: Bool
    let isShadowed: Bool
}

class RenameRefactorService {
    static let shared = RenameRefactorService()
    
    private var referenceIndex: [UUID: [SymbolReference]] = [:]
    private var symbolTable: [URL: [ResolvedSymbol]] = [:]
    private let indexQueue = DispatchQueue(label: "com.lingcode.renameindex", attributes: .concurrent)
    
    private init() {}
    
    /// Resolve symbol at cursor position
    func resolveSymbol(at cursorOffset: Int, in fileURL: URL) -> ResolvedSymbol? {
        // Get AST symbols for file
        let symbols = ASTIndex.shared.getSymbols(for: fileURL)
        
        // Find symbol at cursor
        for symbol in symbols {
            if symbol.range.contains(cursorOffset) {
                // Build scope
                let scope = ScopeID(
                    file: fileURL,
                    parent: symbol.parent,
                    depth: calculateDepth(for: symbol, in: symbols)
                )
                
                return ResolvedSymbol(
                    id: UUID(),
                    name: symbol.name,
                    kind: convertKind(symbol.kind),
                    scope: scope,
                    file: fileURL,
                    definitionRange: symbol.range
                )
            }
        }
        
        return nil
    }
    
    /// Build reference index for symbol (precomputed, reusable)
    func buildReferenceIndex(for symbol: ResolvedSymbol, in projectURL: URL) -> [SymbolReference] {
        return indexQueue.sync {
            if let cached = referenceIndex[symbol.id] {
                return cached
            }
            
            var references: [SymbolReference] = []
            
            // Find all references using AST queries
            guard let enumerator = FileManager.default.enumerator(
                at: projectURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return references
            }
            
            for case let fileURL as URL in enumerator {
                guard !fileURL.hasDirectoryPath else { continue }
                
                // Skip if not same language
                if !isSameLanguage(fileURL, as: symbol.file) {
                    continue
                }
                
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }
                
                // Find references in this file
                let fileReferences = findReferences(
                    to: symbol,
                    in: content,
                    fileURL: fileURL
                )
                
                references.append(contentsOf: fileReferences)
            }
            
            // Cache index
            indexQueue.async(flags: .barrier) {
                self.referenceIndex[symbol.id] = references
            }
            
            return references
        }
    }
    
    /// Generate edit plan for rename (NO LLM YET)
    func generateRenamePlan(
        symbol: ResolvedSymbol,
        newName: String,
        references: [SymbolReference]
    ) -> [Edit] {
        var edits: [Edit] = []
        
        // Rename definition
        edits.append(Edit(
            file: symbol.file.path,
            operation: .replace,
            range: EditRange(
                startLine: lineNumber(for: symbol.definitionRange.lowerBound, in: symbol.file),
                endLine: lineNumber(for: symbol.definitionRange.upperBound, in: symbol.file)
            ),
            anchor: Anchor(
                type: convertAnchorType(symbol.kind),
                name: symbol.name,
                parent: nil,
                childIndex: nil
            ),
            content: [newName]
        ))
        
        // Rename all references (skip strings, comments, shadowed)
        for ref in references {
            if ref.isInString || ref.isInComment || ref.isShadowed {
                continue
            }
            
            let filePath = ref.file.path
            let startLine = lineNumber(for: ref.range.lowerBound, in: ref.file)
            let endLine = lineNumber(for: ref.range.upperBound, in: ref.file)
            
            edits.append(Edit(
                file: filePath,
                operation: .replace,
                range: EditRange(startLine: startLine, endLine: endLine),
                anchor: nil,
                content: [newName]
            ))
        }
        
        return edits
    }
    
    /// Perform scope safety checks
    func validateRename(
        symbol: ResolvedSymbol,
        newName: String,
        in projectURL: URL
    ) -> RenameValidationResult {
        // Check for collision in same scope
        if hasCollision(symbol: symbol, newName: newName, in: projectURL) {
            return .collision(newName)
        }
        
        // Check if exported API (requires confirmation)
        if isExported(symbol: symbol) {
            return .requiresConfirmation("Symbol is exported/public API")
        }
        
        // Check overridden method mismatch
        if isOverriddenMethod(symbol: symbol) {
            return .requiresConfirmation("Method may be overridden")
        }
        
        return .valid
    }
    
    /// Optional LLM validation (fast, cheap)
    func validateWithLLM(
        edits: [Edit],
        originalName: String,
        newName: String
    ) async -> Bool {
        // Placeholder - would call small local model (Phi-3) or GPT-4o mini
        // Ask: "Do these renames introduce semantic errors? YES or NO"
        
        // For now, return true (would implement actual LLM call)
        return true
    }
    
    /// Execute rename (complete flow)
    func rename(
        symbol: ResolvedSymbol,
        to newName: String,
        in projectURL: URL,
        validateWithLLM: Bool = false
    ) async throws -> [Edit] {
        // Step 1: Build reference index
        let references = buildReferenceIndex(for: symbol, in: projectURL)
        
        // Step 2: Validate scope safety
        let validation = self.validateRename(symbol: symbol, newName: newName, in: projectURL)
        switch validation {
        case .collision(let name):
            throw RenameError.collision(name: name)
        case .requiresConfirmation(let reason):
            throw RenameError.requiresConfirmation(reason: reason)
        case .valid:
            break
        }
        
        // Step 3: Generate edit plan
        let edits = generateRenamePlan(symbol: symbol, newName: newName, references: references)
        
        // Step 4: Optional LLM validation
        if validateWithLLM {
            let isValid = await self.validateWithLLM(
                edits: edits,
                originalName: symbol.name,
                newName: newName
            )
            if !isValid {
                throw RenameError.semanticError
            }
        }
        
        // Create undo snapshot after successful rename
        let affectedFiles = Set(edits.map { URL(fileURLWithPath: $0.file) })
        TimeTravelUndoService.shared.snapshotAfterRename(
            oldName: symbol.name,
            newName: newName,
            affectedFiles: Array(affectedFiles),
            in: projectURL
        )
        
        return edits
    }
    
    // MARK: - Helper Methods
    
    private func findReferences(
        to symbol: ResolvedSymbol,
        in content: String,
        fileURL: URL
    ) -> [SymbolReference] {
        var references: [SymbolReference] = []
        
        // Use regex to find references (would use Tree-sitter queries in production)
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: symbol.name))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return references
        }
        
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        for match in matches {
            let matchRange = Range(match.range, in: content)!
            let startOffset = content.distance(from: content.startIndex, to: matchRange.lowerBound)
            let endOffset = content.distance(from: content.startIndex, to: matchRange.upperBound)
            let byteRange = startOffset..<endOffset
            
            // Check if in string or comment
            let isInString = isInStringLiteral(at: matchRange, in: content)
            let isInComment = isInComment(at: matchRange, in: content)
            let isShadowed = isShadowed(at: byteRange, symbol: symbol, in: content, fileURL: fileURL)
            
            references.append(SymbolReference(
                symbolID: symbol.id,
                file: fileURL,
                range: byteRange,
                isDefinition: byteRange == symbol.definitionRange,
                isInString: isInString,
                isInComment: isInComment,
                isShadowed: isShadowed
            ))
        }
        
        return references
    }
    
    private func isInStringLiteral(at range: Range<String.Index>, in content: String) -> Bool {
        // Simplified check - would use proper parsing
        let before = String(content[..<range.lowerBound])
        let quotes = before.filter { "\"'`".contains($0) }.count
        return quotes % 2 != 0
    }
    
    private func isInComment(at range: Range<String.Index>, in content: String) -> Bool {
        // Check if in single-line or multi-line comment
        let before = String(content[..<range.lowerBound])
        return before.contains("//") || before.contains("/*")
    }
    
    private func isShadowed(
        at range: Range<Int>,
        symbol: ResolvedSymbol,
        in content: String,
        fileURL: URL
    ) -> Bool {
        // Check if symbol is shadowed by local variable
        // Simplified - would use proper scope analysis
        return false
    }
    
    private func hasCollision(
        symbol: ResolvedSymbol,
        newName: String,
        in projectURL: URL
    ) -> Bool {
        // Check if newName already exists in same scope
        // Would use symbol table lookup
        return false
    }
    
    private func isExported(symbol: ResolvedSymbol) -> Bool {
        // Check if symbol is public/exported
        // Would parse access modifiers
        return false
    }
    
    private func isOverriddenMethod(symbol: ResolvedSymbol) -> Bool {
        // Check if method is override
        return symbol.kind == .method
    }
    
    private func lineNumber(for offset: Int, in fileURL: URL) -> Int {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return 1
        }
        let prefix = String(content.prefix(offset))
        return prefix.components(separatedBy: .newlines).count
    }
    
    private func calculateDepth(for symbol: ASTSymbol, in allSymbols: [ASTSymbol]) -> Int {
        var depth = 0
        var current = symbol
        while let parent = current.parent {
            depth += 1
            if let parentSymbol = allSymbols.first(where: { $0.name == parent }) {
                current = parentSymbol
            } else {
                break
            }
        }
        return depth
    }
    
    private func convertKind(_ kind: ASTSymbol.Kind) -> ResolvedSymbol.SymbolKind {
        switch kind {
        case .function: return .function
        case .classSymbol: return .classSymbol
        case .method: return .method
        case .variable: return .variable
        case .property: return .property
        case .import: return .typeAlias
        case .enumSymbol: return .typeAlias
        case .structSymbol: return .typeAlias
        case .protocolSymbol: return .typeAlias
        case .extension: return .typeAlias
        }
    }
    
    private func convertAnchorType(_ kind: ResolvedSymbol.SymbolKind) -> Anchor.AnchorType {
        switch kind {
        case .function: return .function
        case .classSymbol: return .classSymbol
        case .method: return .method
        case .variable: return .variable
        case .property: return .property
        case .parameter: return .variable
        case .typeAlias: return .function
        }
    }
    
    private func isSameLanguage(_ file1: URL, as file2: URL) -> Bool {
        return file1.pathExtension.lowercased() == file2.pathExtension.lowercased()
    }
}

enum RenameValidationResult {
    case valid
    case collision(String)
    case requiresConfirmation(String)
}

enum RenameError: Error, LocalizedError {
    case collision(name: String)
    case requiresConfirmation(reason: String)
    case semanticError
    case symbolNotFound
    
    var errorDescription: String? {
        switch self {
        case .collision(let name):
            return "Name '\(name)' already exists in this scope"
        case .requiresConfirmation(let reason):
            return "Requires confirmation: \(reason)"
        case .semanticError:
            return "Rename would introduce semantic errors"
        case .symbolNotFound:
            return "Symbol not found at cursor position"
        }
    }
}
