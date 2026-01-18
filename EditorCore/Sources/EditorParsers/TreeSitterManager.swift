//
//  TreeSitterManager.swift
//  EditorParsers
//
//  Production-grade Tree-sitter parser manager for non-Swift languages
//  Supports: Python, JavaScript, TypeScript, Go
//

import Foundation

#if canImport(SwiftTreeSitter)
import SwiftTreeSitter

#if canImport(TreeSitterPython)
import TreeSitterPython
#endif

#if canImport(TreeSitterJavaScript)
import TreeSitterJavaScript
#endif

#if canImport(TreeSitterTypeScript)
import TreeSitterTypeScript
#endif

#if canImport(TreeSitterGo)
import TreeSitterGo
#endif

#if canImport(TreeSitterRust)
import TreeSitterRust
#endif

#if canImport(TreeSitterCpp)
import TreeSitterCpp
#endif

#if canImport(TreeSitterJava)
import TreeSitterJava
#endif

// MARK: - Tree-Sitter Language Manager

public class TreeSitterManager {
    public static let shared = TreeSitterManager()
    
    private var parsers: [String: Parser] = [:]
    private var queries: [String: Query] = [:]
    private var isInitialized = false
    
    private init() {
        setupParsers()
    }
    
    private func setupParsers() {
        guard !isInitialized else { return }
        
        do {
            #if canImport(TreeSitterPython)
            // Python
            let pythonLanguage = Language(language: tree_sitter_python())
            let pythonParser = Parser()
            try pythonParser.setLanguage(pythonLanguage)
            parsers["python"] = pythonParser
            #endif
            
            #if canImport(TreeSitterJavaScript)
            // JavaScript
            let jsLanguage = Language(language: tree_sitter_javascript())
            let jsParser = Parser()
            try jsParser.setLanguage(jsLanguage)
            parsers["javascript"] = jsParser
            parsers["js"] = jsParser
            #endif
            
            #if canImport(TreeSitterTypeScript)
            // TypeScript
            let tsLanguage = Language(language: tree_sitter_typescript())
            let tsParser = Parser()
            try tsParser.setLanguage(tsLanguage)
            parsers["typescript"] = tsParser
            parsers["ts"] = tsParser
            parsers["tsx"] = tsParser
            #endif
            
            #if canImport(TreeSitterGo)
            // Go
            let goLanguage = Language(language: tree_sitter_go())
            let goParser = Parser()
            try goParser.setLanguage(goLanguage)
            parsers["go"] = goParser
            #endif
            
            // NOTE: Rust, C++, and Java parsers can be added when dependencies are available
            // Add to Package.swift:
            // .package(url: "https://github.com/tree-sitter/tree-sitter-rust", from: "0.21.0"),
            // .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", from: "0.21.0"),
            // .package(url: "https://github.com/tree-sitter/tree-sitter-java", from: "0.21.0")
            
            #if canImport(TreeSitterRust)
            // Rust
            let rustLanguage = Language(language: tree_sitter_rust())
            let rustParser = Parser()
            try rustParser.setLanguage(rustLanguage)
            parsers["rust"] = rustParser
            parsers["rs"] = rustParser
            #endif
            
            #if canImport(TreeSitterCpp)
            // C++
            let cppLanguage = Language(language: tree_sitter_cpp())
            let cppParser = Parser()
            try cppParser.setLanguage(cppLanguage)
            parsers["cpp"] = cppParser
            parsers["cxx"] = cppParser
            parsers["cc"] = cppParser
            parsers["c++"] = cppParser
            #endif
            
            #if canImport(TreeSitterJava)
            // Java
            let javaLanguage = Language(language: tree_sitter_java())
            let javaParser = Parser()
            try javaParser.setLanguage(javaLanguage)
            parsers["java"] = javaParser
            #endif
            
            isInitialized = true
        } catch {
            print("⚠️ Tree-sitter: Failed to initialize parsers: \(error)")
            print("   Falling back to regex-based extraction")
        }
    }
    
    /// Check if a language is supported by Tree-sitter
    public func isLanguageSupported(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return parsers[normalized] != nil
    }
    
    /// Parse content and extract symbols using Tree-sitter
    public func parse(content: String, language: String, fileURL: URL) -> [TreeSitterSymbol] {
        let normalized = language.lowercased()
        guard let parser = parsers[normalized] else {
            return []
        }
        
        // Parse the code
        guard let tree = try? parser.parse(content) else {
            return []
        }
        
        // Execute Query to extract symbols
        return extractSymbols(from: tree, content: content, language: normalized, fileURL: fileURL)
    }
    
    private func extractSymbols(from tree: Tree, content: String, language: String, fileURL: URL) -> [TreeSitterSymbol] {
        var symbols: [TreeSitterSymbol] = []
        
        // Get the S-Expression Query for this language
        guard let querySExpr = getQueryForLanguage(language),
              let parser = parsers[language],
              let languagePtr = parser.language,
              let queryData = querySExpr.data(using: .utf8),
              let query = try? Query(language: languagePtr, data: queryData) else {
            return []
        }
        
        // Execute Query
        let cursor = query.execute(node: tree.rootNode, in: tree)
        
        // Map Matches to TreeSitterSymbol
        for match in cursor {
            var name = "anonymous"
            var kind: TreeSitterSymbol.Kind = .variable
            var startLine = 0
            var endLine = 0
            var signature: String? = nil
            
            for capture in match.captures {
                let captureName = capture.name
                let node = capture.node
                
                // Map Range (Tree-sitter uses Point(row, col))
                startLine = Int(node.startPoint.row)
                endLine = Int(node.endPoint.row)
                
                // Extract name from "name" capture
                if captureName == "name" {
                    name = extractStringFromByteRange(content: content, byteRange: node.byteRange)
                }
                
                // Determine kind from capture name
                switch captureName {
                case "function":
                    kind = .function
                case "class", "type":
                    kind = .classSymbol
                case "method":
                    kind = .method
                case "variable":
                    kind = .variable
                case "property":
                    kind = .property
                default:
                    break
                }
                
                // Extract signature from definition capture
                if captureName == "definition" || captureName == "function" || captureName == "class" {
                    signature = extractStringFromByteRange(content: content, byteRange: node.byteRange)
                }
            }
            
            symbols.append(TreeSitterSymbol(
                name: name,
                kind: kind,
                file: fileURL,
                range: startLine..<endLine,
                signature: signature,
                parent: nil  // Will be resolved by resolveHierarchy
            ))
        }
        
        // Resolve parent hierarchy based on line ranges
        return resolveHierarchy(for: symbols)
    }
    
    /// Resolve parent hierarchy by analyzing line ranges
    /// If Symbol B is inside Symbol A's range, then A is the parent
    private func resolveHierarchy(for symbols: [TreeSitterSymbol]) -> [TreeSitterSymbol] {
        // 1. Sort by start line so parents always come before children
        let sorted = symbols.sorted { $0.range.lowerBound < $1.range.lowerBound }
        
        var result: [TreeSitterSymbol] = []
        var stack: [TreeSitterSymbol] = []
        
        for symbol in sorted {
            // Pop closed parents from stack (if current symbol starts after parent ends)
            while let parent = stack.last, symbol.range.lowerBound >= parent.range.upperBound {
                stack.removeLast()
            }
            
            // If stack is not empty, the top is our parent
            let parentName: String?
            if let parent = stack.last {
                parentName = parent.name
            } else {
                parentName = nil
            }
            
            // Create symbol with parent information
            let symbolWithParent = TreeSitterSymbol(
                name: symbol.name,
                kind: symbol.kind,
                file: symbol.file,
                range: symbol.range,
                signature: symbol.signature,
                parent: parentName
            )
            
            // Push container types (Class, Struct, Interface) to stack
            // These can contain methods, properties, and nested classes
            if symbol.kind == .classSymbol {
                stack.append(symbolWithParent)
            }
            
            result.append(symbolWithParent)
        }
        
        return result
    }
    
    // Minimal queries to extract basic symbols
    private func getQueryForLanguage(_ lang: String) -> String? {
        switch lang {
        case "python":
            return """
            (function_definition name: (identifier) @name) @function
            (class_definition name: (identifier) @name) @class
            (decorated_definition (function_definition name: (identifier) @name)) @function
            """
        case "javascript", "js":
            return """
            (function_declaration name: (identifier) @name) @function
            (class_declaration name: (identifier) @name) @class
            (method_definition name: (property_identifier) @name) @method
            (variable_declaration (identifier) @name) @variable
            """
        case "typescript", "ts", "tsx":
            return """
            (function_declaration name: (identifier) @name) @function
            (class_declaration name: (type_identifier) @name) @class
            (method_definition name: (property_identifier) @name) @method
            (interface_declaration name: (type_identifier) @name) @class
            (type_alias_declaration name: (type_identifier) @name) @class
            """
        case "go":
            return """
            (function_declaration name: (identifier) @name) @function
            (type_declaration (type_spec name: (type_identifier) @name)) @class
            (method_declaration name: (field_identifier) @name) @method
            """
        case "rust", "rs":
            return """
            (function_item name: (identifier) @name) @function
            (struct_item name: (type_identifier) @name) @class
            (impl_item (type_identifier) @name) @class
            (trait_item name: (type_identifier) @name) @class
            (enum_item name: (type_identifier) @name) @class
            """
        case "cpp", "cxx", "cc", "c++":
            return """
            (function_definition declarator: (function_declarator declarator: (identifier) @name)) @function
            (class_specifier name: (type_identifier) @name) @class
            (struct_specifier name: (type_identifier) @name) @class
            (namespace_definition name: (identifier) @name) @class
            """
        case "java":
            return """
            (method_declaration name: (identifier) @name) @method
            (class_declaration name: (identifier) @name) @class
            (interface_declaration name: (identifier) @name) @class
            (constructor_declaration name: (identifier) @name) @function
            """
        default:
            return nil
        }
    }
    
    /// Extract relationships (instantiation, method calls, etc.) using AST queries
    /// This replaces string matching with 100% AST-based extraction
    public func extractRelationships(content: String, language: String, fileURL: URL, knownClasses: Set<String>) -> [TreeSitterRelationship] {
        let normalized = language.lowercased()
        guard let parser = parsers[normalized] else {
            return []
        }
        
        // Parse the code
        guard let tree = try? parser.parse(content) else {
            return []
        }
        
        // Get relationship query for this language
        guard let querySExpr = getRelationshipQueryForLanguage(normalized),
              let languagePtr = parser.language,
              let queryData = querySExpr.data(using: .utf8),
              let query = try? Query(language: languagePtr, data: queryData) else {
            return []
        }
        
        // Execute Query
        let cursor = query.execute(node: tree.rootNode, in: tree)
        var relationships: [TreeSitterRelationship] = []
        
        for match in cursor {
            var targetSymbol: String? = nil
            var relationshipType: TreeSitterRelationship.RelationshipType? = nil
            var context: String? = nil
            
            for capture in match.captures {
                let captureName = capture.name
                let node = capture.node
                
                // Extract target symbol from captures
                if captureName == "class" || captureName == "target" || captureName == "type" {
                    let symbol = extractStringFromByteRange(content: content, byteRange: node.byteRange)
                    // Only include if it's a known class (from AST symbols)
                    if knownClasses.contains(symbol) {
                        targetSymbol = symbol
                    }
                }
                
                // Determine relationship type from capture name
                switch captureName {
                case "instantiation", "new_call":
                    relationshipType = .instantiation
                case "method_call", "call":
                    relationshipType = .methodCall
                case "property_access", "attribute":
                    relationshipType = .propertyAccess
                case "type_ref", "type_annotation":
                    relationshipType = .typeReference
                default:
                    break
                }
                
                // Extract context (full expression) from definition capture
                if captureName == "definition" || captureName == "expression" {
                    context = extractStringFromByteRange(content: content, byteRange: node.byteRange)
                }
            }
            
            // Only add if we have both target symbol and relationship type
            if let target = targetSymbol, let type = relationshipType {
                relationships.append(TreeSitterRelationship(
                    targetSymbol: target,
                    relationshipType: type,
                    context: context ?? "",
                    file: fileURL
                ))
            }
        }
        
        return relationships
    }
    
    /// Get relationship extraction queries for each language
    /// These queries target specific AST nodes (call_expression, new_expression, etc.)
    private func getRelationshipQueryForLanguage(_ lang: String) -> String? {
        switch lang {
        case "python":
            // Python: target call nodes with attribute expressions (obj.method()) and direct calls (ClassName())
            return """
            ; Instantiation: ClassName() or ClassName(...)
            (call
              function: (identifier) @class
              (#match? @class "^[A-Z]")) @instantiation
            
            ; Method calls: obj.method() where obj is of known class type
            (call
              function: (attribute
                object: (_) @obj
                attribute: (identifier) @method)) @method_call
            
            ; Property access: obj.property
            (attribute
              object: (_) @obj
              attribute: (identifier) @property) @property_access
            
            ; Type annotations: var: ClassName
            (type: (identifier) @type) @type_ref
            """
            
        case "javascript", "js":
            // JavaScript: target new_expression and call_expression nodes
            return """
            ; Instantiation: new ClassName()
            (new_expression
              constructor: (identifier) @class
              (#match? @class "^[A-Z]")) @instantiation
            
            ; Method calls: obj.method()
            (call_expression
              function: (member_expression
                object: (_) @obj
                property: (property_identifier) @method)) @method_call
            
            ; Property access: obj.property
            (member_expression
              object: (_) @obj
              property: (property_identifier) @property) @property_access
            
            ; Type annotations (JSDoc): @type {ClassName}
            (jsdoc_type (type_identifier) @type) @type_ref
            """
            
        case "typescript", "ts", "tsx":
            // TypeScript: similar to JS but with type annotations
            return """
            ; Instantiation: new ClassName()
            (new_expression
              constructor: (identifier) @class
              (#match? @class "^[A-Z]")) @instantiation
            
            ; Method calls: obj.method()
            (call_expression
              function: (member_expression
                object: (_) @obj
                property: (property_identifier) @method)) @method_call
            
            ; Property access: obj.property
            (member_expression
              object: (_) @obj
              property: (property_identifier) @property) @property_access
            
            ; Type annotations: var: ClassName
            (type_annotation (type_identifier) @type) @type_ref
            """
            
        case "go":
            // Go: target call_expression and composite_literal nodes
            return """
            ; Instantiation: &ClassName{} or ClassName{}
            (composite_literal
              type: (type_identifier) @class) @instantiation
            
            ; Method calls: obj.Method()
            (call_expression
              function: (selector_expression
                operand: (_) @obj
                field: (field_identifier) @method)) @method_call
            
            ; Property access: obj.Field
            (selector_expression
              operand: (_) @obj
              field: (field_identifier) @property) @property_access
            
            ; Type annotations: var x ClassName
            (type_identifier) @type @type_ref
            """
            
        case "rust", "rs":
            // Rust: target call expressions, struct initialization, method calls
            return """
            ; Instantiation: StructName { ... } or StructName::new()
            (call_expression
              function: (scoped_identifier
                path: (identifier) @class
                name: (identifier) @method)) @instantiation
            
            ; Method calls: obj.method()
            (call_expression
              function: (field_expression
                field: (field_identifier) @method)) @method_call
            
            ; Property access: obj.field
            (field_expression
              field: (field_identifier) @property) @property_access
            
            ; Type annotations: let x: TypeName
            (type_identifier) @type @type_ref
            """
            
        case "cpp", "cxx", "cc", "c++":
            // C++: target new expressions, function calls, member access
            return """
            ; Instantiation: new ClassName() or ClassName(...)
            (new_expression
              type: (type_identifier) @class) @instantiation
            
            ; Method calls: obj->method() or obj.method()
            (call_expression
              function: (field_expression
                field: (field_identifier) @method)) @method_call
            
            ; Property access: obj->field or obj.field
            (field_expression
              field: (field_identifier) @property) @property_access
            
            ; Type annotations: TypeName var
            (type_identifier) @type @type_ref
            """
            
        case "java":
            // Java: target new expressions, method calls, field access
            return """
            ; Instantiation: new ClassName()
            (object_creation_expression
              type: (type_identifier) @class) @instantiation
            
            ; Method calls: obj.method()
            (method_invocation
              object: (_) @obj
              name: (identifier) @method) @method_call
            
            ; Field access: obj.field
            (field_access
              field: (identifier) @property) @property_access
            
            ; Type annotations: ClassName var
            (type_identifier) @type @type_ref
            """
            
        default:
            return nil
        }
    }
}

// MARK: - Tree-sitter Symbol Model

public struct TreeSitterSymbol {
    public enum Kind {
        case function
        case classSymbol
        case method
        case variable
        case property
    }
    
    public let name: String
    public let kind: Kind
    public let file: URL
    public let range: Range<Int>
    public let signature: String?
    public let parent: String?  // Parent symbol name (e.g., class containing this method)
    
    public init(name: String, kind: Kind, file: URL, range: Range<Int>, signature: String?, parent: String? = nil) {
        self.name = name
        self.kind = kind
        self.file = file
        self.range = range
        self.signature = signature
        self.parent = parent
    }
}

// MARK: - Tree-sitter Relationship Model

public struct TreeSitterRelationship {
    public enum RelationshipType {
        case instantiation
        case methodCall
        case propertyAccess
        case typeReference
    }
    
    public let targetSymbol: String
    public let relationshipType: RelationshipType
    public let context: String
    public let file: URL
}

extension TreeSitterManager {
    /// Extract string from byte range (Tree-sitter uses byte offsets)
    private func extractStringFromByteRange(content: String, byteRange: Range<UInt32>) -> String {
        let startOffset = Int(byteRange.lowerBound)
        let endOffset = Int(byteRange.upperBound)
        
        // Convert byte offsets to String indices
        guard startOffset < content.utf8.count, endOffset <= content.utf8.count else {
            return ""
        }
        
        let utf8 = content.utf8
        guard let startIndex = utf8.index(utf8.startIndex, offsetBy: startOffset, limitedBy: utf8.endIndex),
              let endIndex = utf8.index(utf8.startIndex, offsetBy: endOffset, limitedBy: utf8.endIndex) else {
            return ""
        }
        
        // Convert UTF8 view slice to String
        let utf8Slice = utf8[startIndex..<endIndex]
        return String(decoding: utf8Slice, as: UTF8.self)
    }

#else
// Fallback when Tree-sitter is not available
public class TreeSitterManager {
    public static let shared = TreeSitterManager()
    
    private init() {}
    
    public func isLanguageSupported(_ language: String) -> Bool {
        return false
    }
    
    public func parse(content: String, language: String, fileURL: URL) -> [TreeSitterSymbol] {
        return []
    }
}

public struct TreeSitterSymbol {
    public enum Kind {
        case function
        case classSymbol
        case method
        case variable
        case property
    }
    
    public let name: String
    public let kind: Kind
    public let file: URL
    public let range: Range<Int>
    public let signature: String?
    public let parent: String?  // Parent symbol name (e.g., class containing this method)
    
    public init(name: String, kind: Kind, file: URL, range: Range<Int>, signature: String?, parent: String? = nil) {
        self.name = name
        self.kind = kind
        self.file = file
        self.range = range
        self.signature = signature
        self.parent = parent
    }
}
#endif
