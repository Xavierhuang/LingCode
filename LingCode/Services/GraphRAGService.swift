//
//  GraphRAGService.swift
//  LingCode
//
//  Enhanced GraphRAG: Finds files that inherit from, instantiate, or catch errors from symbols
//  AST-based parsing using TreeSitter/SwiftSyntax for accuracy
//  Actor-based for thread safety and parallel execution
//
//  STATUS: Production-ready with hybrid AST+string matching for non-Swift languages
//  FUTURE: Implement TreeSitterQuery (SCM files) for 100% AST-based extraction across all languages
//

import Foundation

#if canImport(SwiftSyntax)
import SwiftSyntax
import SwiftParser
#endif

#if canImport(EditorParsers)
import EditorParsers
#endif

struct CodeRelationship: Sendable {
    let sourceFile: URL
    let targetSymbol: String
    let relationshipType: RelationshipType
    let context: String // Line of code showing the relationship
    
    enum RelationshipType: Sendable, Hashable, CaseIterable, Equatable {
        case inheritance // class B : A
        case instantiation // let x = AuthService()
        case errorHandling // catch AuthError
        case methodCall // authService.login()
        case propertyAccess // authService.token
        case typeReference // var user: AuthUser
        
        // Explicit nonisolated Equatable conformance for Swift 6
        nonisolated static func == (lhs: RelationshipType, rhs: RelationshipType) -> Bool {
            switch (lhs, rhs) {
            case (.inheritance, .inheritance),
                 (.instantiation, .instantiation),
                 (.errorHandling, .errorHandling),
                 (.methodCall, .methodCall),
                 (.propertyAccess, .propertyAccess),
                 (.typeReference, .typeReference):
                return true
            default:
                return false
            }
        }
    }
}

// IMPROVEMENT: Convert to Actor for thread safety and parallel execution
// This enables parallel file processing without data races
actor GraphRAGService {
    static let shared = GraphRAGService()
    
    private var relationshipCache: [String: [CodeRelationship]] = [:] // symbol -> relationships
    private var graphCache: CodeRelationshipGraph?
    private var lastProjectURL: URL?
    
    private init() {}
    
    /// Find all files related to a symbol through GraphRAG relationships
    /// Returns files that inherit from, instantiate, catch errors, or reference the symbol
    func findRelatedFiles(
        for symbolName: String,
        in projectURL: URL,
        relationshipTypes: Set<CodeRelationship.RelationshipType> = Set(CodeRelationship.RelationshipType.allCases)
    ) async -> [CodeRelationship] {
        // Rebuild graph if project changed
        if lastProjectURL != projectURL {
            graphCache = await buildRelationshipGraph(projectURL: projectURL)
            lastProjectURL = projectURL
        }
        
        guard let graph = graphCache else {
            return []
        }
        
        // Check cache first
        let cacheKey = "\(symbolName):\(relationshipTypes.hashValue)"
        if let cached = relationshipCache[cacheKey] {
            return cached
        }
        
        // Find relationships matching the symbol and types
        let relationships = graph.relationships.filter { rel in
            rel.targetSymbol == symbolName && relationshipTypes.contains(rel.relationshipType)
        }
        
        relationshipCache[cacheKey] = relationships
        return relationships
    }
    
    /// Build relationship graph by analyzing AST for inheritance, instantiation, error handling
    /// IMPROVEMENT: Uses parallel processing with TaskGroup for speed
    private func buildRelationshipGraph(projectURL: URL) async -> CodeRelationshipGraph {
        var graph = CodeRelationshipGraph()
        
        // Collect all files first
        let files = await collectFiles(in: projectURL)
        
        // IMPROVEMENT: Process files in parallel using TaskGroup
        await withTaskGroup(of: [CodeRelationship].self) { group in
            for fileURL in files {
                group.addTask {
                    // Extract relationships using AST parsing (no regex)
                    await self.extractRelationshipsAST(from: fileURL, projectURL: projectURL)
                }
            }
            
            // Collect all relationships
            for await relationships in group {
                graph.relationships.append(contentsOf: relationships)
            }
        }
        
        return graph
    }
    
    /// Collect all supported files in project
    private func collectFiles(in projectURL: URL) async -> [URL] {
        var files: [URL] = []
        let supportedExtensions = ["swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "go"]
        let blockedFolders = ["node_modules", "vendor", "build", "dist", ".git", ".build", "Pods", "DerivedData", ".swiftpm"]
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return files
        }
        
        for case let fileURL as URL in enumerator {
            // Skip blocked directories
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
               resourceValues.isDirectory == true,
               blockedFolders.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            
            guard !fileURL.hasDirectoryPath,
                  supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            
            files.append(fileURL)
        }
        
        return files
    }
    
    /// Extract relationships from code using AST parsing (no regex)
    /// IMPROVEMENT: Uses TreeSitterBridge for all languages (SwiftSyntax for Swift, Tree-sitter for others)
    private func extractRelationshipsAST(from fileURL: URL, projectURL: URL) async -> [CodeRelationship] {
        var relationships: [CodeRelationship] = []
        
        // Get symbols using AST parsing
        let symbols = await ASTIndex.shared.getSymbols(for: fileURL)
        
        // For Swift files, use SwiftSyntax AST to extract relationships
        if fileURL.pathExtension.lowercased() == "swift" {
            relationships.append(contentsOf: await extractSwiftRelationships(from: fileURL, symbols: symbols))
        } else {
            // For other languages, use Tree-sitter AST
            relationships.append(contentsOf: await extractTreeSitterRelationships(from: fileURL, symbols: symbols))
        }
        
        return relationships
    }
    
    /// Extract relationships from Swift files using SwiftSyntax AST
    private func extractSwiftRelationships(from fileURL: URL, symbols: [ASTSymbol]) async -> [CodeRelationship] {
        var relationships: [CodeRelationship] = []
        
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return relationships
        }
        
        // Parse with SwiftSyntax to get AST
        // FIX: Run SwiftSyntax parsing on MainActor to avoid actor isolation issues
        #if canImport(SwiftSyntax)
        let parsedRelationships = await MainActor.run {
            let sourceFile = Parser.parse(source: content)
            let visitor = RelationshipExtractorVisitor(fileURL: fileURL, symbols: symbols)
            visitor.walk(sourceFile)
            return visitor.relationships
        }
        relationships.append(contentsOf: parsedRelationships)
        #endif
        
        return relationships
    }
    
    /// Extract relationships from non-Swift files using Tree-sitter AST
    private func extractTreeSitterRelationships(from fileURL: URL, symbols: [ASTSymbol]) async -> [CodeRelationship] {
        var relationships: [CodeRelationship] = []
        
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return relationships
        }
        
        let ext = fileURL.pathExtension.lowercased()
        let language = mapExtensionToLanguage(ext)
        
        #if canImport(EditorParsers)
        // Use TreeSitterManager for AST-based parsing
        if TreeSitterManager.shared.isLanguageSupported(language) {
            let treeSitterSymbols = TreeSitterManager.shared.parse(content: content, language: language, fileURL: fileURL)
            
            // Extract relationships from Tree-sitter AST
            relationships.append(contentsOf: extractRelationshipsFromTreeSitterSymbols(
                symbols: treeSitterSymbols,
                fileURL: fileURL,
                content: content
            ))
        }
        #endif
        
        return relationships
    }
    
    /// Extract relationships from Tree-sitter symbols
    #if canImport(EditorParsers)
    private func extractRelationshipsFromTreeSitterSymbols(
        symbols: [TreeSitterSymbol],
        fileURL: URL,
        content: String
    ) -> [CodeRelationship] {
        var relationships: [CodeRelationship] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Group symbols by type for efficient lookup
        // TreeSitterSymbol.Kind uses .classSymbol for both classes and structs
        let classSymbols = Set(symbols.filter { $0.kind == .classSymbol }.map { $0.name })
        
        // Extract inheritance relationships from AST
        for symbol in symbols {
            // Check for inheritance (parent field indicates inheritance)
            if let parent = symbol.parent, !parent.isEmpty {
                relationships.append(CodeRelationship(
                    sourceFile: fileURL,
                    targetSymbol: parent,
                    relationshipType: .inheritance,
                    context: symbol.signature ?? symbol.name
                ))
            }
        }
        
        // Extract instantiation and method calls from content using AST context
        // NOTE: This uses a hybrid approach (AST symbols + string matching) as a fallback
        // for non-Swift languages. This is more accurate than pure regex because we:
        // 1. Only check against known class/struct symbols (from AST)
        // 2. Use AST context to filter candidates
        //
        // FUTURE IMPROVEMENT: For production-grade accuracy, implement TreeSitterQuery (SCM files)
        // for each language to directly target AST nodes:
        // - Python: target `call` nodes with `attribute` expressions
        // - JavaScript/TypeScript: target `new_expression` and `call_expression` nodes
        // - Go: target `call_expression` and `composite_literal` nodes
        // This would eliminate string matching entirely and provide 100% AST-based extraction.
        //
        // Example TreeSitterQuery for Python instantiation:
        // (call function: (attribute object: (identifier) @obj attribute: (identifier) @method))
        // (call function: (identifier) @class (#match? @class "^[A-Z]"))
        //
        // For now, this hybrid approach is acceptable and provides good accuracy for most use cases.
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
        // Check for instantiation patterns (AST-aware, but uses string matching as fallback)
        for className in classSymbols {
                // Pattern: let x = ClassName() or var x = ClassName()
                // FUTURE: Replace with TreeSitterQuery targeting instantiation_expression nodes
                if trimmed.contains("= \(className)(") || trimmed.contains(": \(className)") {
                    relationships.append(CodeRelationship(
                        sourceFile: fileURL,
                        targetSymbol: className,
                        relationshipType: .instantiation,
                        context: trimmed
                    ))
                }
                
                // Pattern: object.method() where object is of type ClassName
                // FUTURE: Replace with TreeSitterQuery targeting call_expression nodes
                if trimmed.contains("\(className.lowercased()).") || trimmed.contains("\(className).") {
                    relationships.append(CodeRelationship(
                        sourceFile: fileURL,
                        targetSymbol: className,
                        relationshipType: .methodCall,
                        context: trimmed
                    ))
                }
            }
        }
        
        return relationships
    }
    #endif
    
    /// Map file extension to language identifier
    private func mapExtensionToLanguage(_ ext: String) -> String {
        switch ext {
        case "py": return "python"
        case "js": return "javascript"
        case "ts", "tsx": return "typescript"
        case "jsx": return "javascript"
        case "go": return "go"
        case "java": return "java"
        case "kt": return "kotlin"
        default: return ext
        }
    }
}

struct CodeRelationshipGraph: Sendable {
    var relationships: [CodeRelationship] = []
}

#if canImport(SwiftSyntax)
import SwiftSyntax
import SwiftParser

/// SwiftSyntax visitor to extract relationships from AST
/// FIX: Mark as nonisolated to avoid actor isolation issues
private nonisolated class RelationshipExtractorVisitor: SyntaxVisitor {
    let fileURL: URL
    let symbols: [ASTSymbol]
    var relationships: [CodeRelationship] = []
    
    nonisolated init(fileURL: URL, symbols: [ASTSymbol]) {
        self.fileURL = fileURL
        self.symbols = symbols
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extract inheritance relationships
        if let inheritanceClause = node.inheritanceClause {
            for inheritedType in inheritanceClause.inheritedTypes {
                if let typeName = inheritedType.type.as(IdentifierTypeSyntax.self) {
                    relationships.append(CodeRelationship(
                        sourceFile: fileURL,
                        targetSymbol: typeName.name.text,
                        relationshipType: .inheritance,
                        context: node.description
                    ))
                }
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extract protocol conformance
        if let inheritanceClause = node.inheritanceClause {
            for inheritedType in inheritanceClause.inheritedTypes {
                if let typeName = inheritedType.type.as(IdentifierTypeSyntax.self) {
                    relationships.append(CodeRelationship(
                        sourceFile: fileURL,
                        targetSymbol: typeName.name.text,
                        relationshipType: .inheritance,
                        context: node.description
                    ))
                }
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extract type references and instantiations
        for binding in node.bindings {
            // Check for type annotation
            if let typeAnnotation = binding.typeAnnotation {
                if let identifierType = typeAnnotation.type.as(IdentifierTypeSyntax.self) {
                    let typeName = identifierType.name.text
                    // Check if it's a known class/struct
                    if symbols.contains(where: { $0.name == typeName && ($0.kind == .classSymbol || $0.kind == .structSymbol) }) {
                        relationships.append(CodeRelationship(
                            sourceFile: fileURL,
                            targetSymbol: typeName,
                            relationshipType: .typeReference,
                            context: node.description
                        ))
                    }
                }
            }
            
            // Check for initialization
            if let initializer = binding.initializer {
                if let functionCall = initializer.value.as(FunctionCallExprSyntax.self) {
                    if let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
                        let calledName = calledExpression.baseName.text
                        // Check if it's a known class/struct constructor
                        if symbols.contains(where: { $0.name == calledName && ($0.kind == .classSymbol || $0.kind == .structSymbol) }) {
                            relationships.append(CodeRelationship(
                                sourceFile: fileURL,
                                targetSymbol: calledName,
                                relationshipType: .instantiation,
                                context: node.description
                            ))
                        }
                    }
                }
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Extract method calls
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                let baseName = base.baseName.text
                // Check if base is a known symbol
                if let symbol = symbols.first(where: { $0.name == baseName }) {
                    relationships.append(CodeRelationship(
                        sourceFile: fileURL,
                        targetSymbol: symbol.name,
                        relationshipType: .methodCall,
                        context: node.description
                    ))
                }
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        // Extract error handling relationships
        // FIX: Use a visitor to extract TypeSyntax from catch item patterns
        for catchItem in node.catchItems {
            // Use a helper visitor to find type nodes in the pattern
            let typeExtractor = TypeExtractorVisitor()
            if let pattern = catchItem.pattern {
                typeExtractor.walk(pattern)
                // Extract all found types
                for typeName in typeExtractor.foundTypes {
                    relationships.append(CodeRelationship(
                        sourceFile: fileURL,
                        targetSymbol: typeName,
                        relationshipType: .errorHandling,
                        context: node.description
                    ))
                }
            }
        }
        return .visitChildren
    }
    
    /// Helper visitor to extract type names from patterns
    private nonisolated class TypeExtractorVisitor: SyntaxVisitor {
        var foundTypes: [String] = []
        
        nonisolated init() {
            super.init(viewMode: .sourceAccurate)
        }
        
        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            foundTypes.append(node.name.text)
            return .visitChildren
        }
    }
}
#endif
