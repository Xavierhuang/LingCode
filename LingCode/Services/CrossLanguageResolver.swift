//
//  CrossLanguageResolver.swift
//  LingCode
//
//  Cross-Language Symbol Resolution: Detect relationships between different languages
//  Example: TypeScript frontend instantiating models that correspond to Python FastAPI backend schemas
//

import Foundation

#if canImport(EditorParsers)
import EditorParsers
#endif

/// Cross-language relationship between symbols in different languages
struct CrossLanguageRelationship {
    let sourceSymbol: String
    let sourceLanguage: String
    let sourceFile: URL
    let targetSymbol: String
    let targetLanguage: String
    let targetFile: URL
    let relationshipType: RelationshipType
    let confidence: Double // 0.0 to 1.0
    
    enum RelationshipType {
        case schemaMapping      // TypeScript interface <-> Python Pydantic model
        case apiMapping         // TypeScript API call <-> Python FastAPI endpoint
        case typeMapping        // TypeScript type <-> Python type annotation
        case nameMatch          // Same name across languages (lower confidence)
    }
}

/// Service for detecting cross-language symbol relationships
actor CrossLanguageResolver {
    static let shared = CrossLanguageResolver()
    
    private var crossLanguageCache: [String: [CrossLanguageRelationship]] = [:]
    private var symbolMappings: [String: Set<String>] = [:] // symbol name -> set of matching symbols in other languages
    
    private init() {}
    
    /// Find cross-language relationships for a symbol
    func findCrossLanguageRelationships(
        for symbolName: String,
        in projectURL: URL,
        sourceLanguage: String
    ) async -> [CrossLanguageRelationship] {
        // Check cache
        let cacheKey = "\(symbolName):\(sourceLanguage)"
        if let cached = crossLanguageCache[cacheKey] {
            return cached
        }
        
        var relationships: [CrossLanguageRelationship] = []
        
        // Collect all files in project
        let allFiles = await collectAllFiles(in: projectURL)
        
        // Group files by language
        let filesByLanguage = Dictionary(grouping: allFiles) { fileURL in
            detectLanguage(for: fileURL)
        }
        
        // Find potential matches in other languages
        for (targetLanguage, targetFiles) in filesByLanguage where targetLanguage != sourceLanguage {
            let matches = await findMatches(
                symbolName: symbolName,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                targetFiles: targetFiles,
                projectURL: projectURL
            )
            relationships.append(contentsOf: matches)
        }
        
        // Sort by confidence
        relationships.sort { $0.confidence > $1.confidence }
        
        crossLanguageCache[cacheKey] = relationships
        return relationships
    }
    
    /// Find potential matches for a symbol in target language files
    private func findMatches(
        symbolName: String,
        sourceLanguage: String,
        targetLanguage: String,
        targetFiles: [URL],
        projectURL: URL
    ) async -> [CrossLanguageRelationship] {
        var matches: [CrossLanguageRelationship] = []
        
        // Extract symbols from target language files
        for targetFile in targetFiles {
            guard let content = try? String(contentsOf: targetFile, encoding: .utf8) else {
                continue
            }
            
            let symbols = extractSymbols(from: content, language: targetLanguage, fileURL: targetFile)
            
            for symbol in symbols {
                let confidence = calculateConfidence(
                    sourceName: symbolName,
                    targetName: symbol.name,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
                
                if confidence > 0.5 { // Only include high-confidence matches
                    let relationshipType = determineRelationshipType(
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage,
                        sourceName: symbolName,
                        targetName: symbol.name
                    )
                    
                    matches.append(CrossLanguageRelationship(
                        sourceSymbol: symbolName,
                        sourceLanguage: sourceLanguage,
                        sourceFile: URL(fileURLWithPath: ""), // Will be set by caller
                        targetSymbol: symbol.name,
                        targetLanguage: targetLanguage,
                        targetFile: targetFile,
                        relationshipType: relationshipType,
                        confidence: confidence
                    ))
                }
            }
        }
        
        return matches
    }
    
    /// Calculate confidence score for a potential match
    private func calculateConfidence(
        sourceName: String,
        targetName: String,
        sourceLanguage: String,
        targetLanguage: String
    ) -> Double {
        var confidence: Double = 0.0
        
        // Exact name match
        if sourceName.lowercased() == targetName.lowercased() {
            confidence += 0.6
        }
        
        // Case-insensitive match
        if sourceName.lowercased() == targetName.lowercased() {
            confidence += 0.2
        }
        
        // Common naming pattern matches
        // TypeScript: PascalCase, Python: snake_case or PascalCase
        let tsPattern = convertToSnakeCase(sourceName)
        let pyPattern = convertToPascalCase(targetName)
        
        if tsPattern.lowercased() == targetName.lowercased() ||
           sourceName == pyPattern {
            confidence += 0.3
        }
        
        // Schema/model pattern matching
        if isSchemaPattern(sourceName, language: sourceLanguage) &&
           isModelPattern(targetName, language: targetLanguage) {
            confidence += 0.4
        }
        
        // API endpoint pattern matching
        if isAPIPattern(sourceName, language: sourceLanguage) &&
           isEndpointPattern(targetName, language: targetLanguage) {
            confidence += 0.4
        }
        
        return min(confidence, 1.0)
    }
    
    /// Determine relationship type based on languages and names
    private func determineRelationshipType(
        sourceLanguage: String,
        targetLanguage: String,
        sourceName: String,
        targetName: String
    ) -> CrossLanguageRelationship.RelationshipType {
        // Schema mapping: TypeScript interface <-> Python Pydantic model
        if (sourceLanguage == "typescript" && targetLanguage == "python") ||
           (sourceLanguage == "python" && targetLanguage == "typescript") {
            if isSchemaPattern(sourceName, language: sourceLanguage) ||
               isModelPattern(targetName, language: targetLanguage) {
                return .schemaMapping
            }
        }
        
        // API mapping: TypeScript API call <-> Python FastAPI endpoint
        if sourceName.lowercased().contains("api") ||
           targetName.lowercased().contains("api") ||
           sourceName.lowercased().contains("endpoint") ||
           targetName.lowercased().contains("endpoint") {
            return .apiMapping
        }
        
        // Type mapping: Similar type names
        if sourceName.lowercased() == targetName.lowercased() {
            return .typeMapping
        }
        
        return .nameMatch
    }
    
    /// Check if symbol matches schema pattern
    private func isSchemaPattern(_ name: String, language: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix("schema") ||
               lower.hasSuffix("interface") ||
               lower.hasSuffix("type") ||
               (language == "typescript" && name.first?.isUppercase == true)
    }
    
    /// Check if symbol matches model pattern
    private func isModelPattern(_ name: String, language: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix("model") ||
               lower.hasSuffix("class") ||
               (language == "python" && name.first?.isUppercase == true)
    }
    
    /// Check if symbol matches API pattern
    private func isAPIPattern(_ name: String, language: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("api") ||
               lower.contains("client") ||
               lower.contains("service")
    }
    
    /// Check if symbol matches endpoint pattern
    private func isEndpointPattern(_ name: String, language: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("endpoint") ||
               lower.contains("route") ||
               lower.contains("handler") ||
               (language == "python" && lower.hasPrefix("get_") || lower.hasPrefix("post_") || lower.hasPrefix("put_") || lower.hasPrefix("delete_"))
    }
    
    /// Convert PascalCase to snake_case
    private func convertToSnakeCase(_ input: String) -> String {
        var result = ""
        for (index, char) in input.enumerated() {
            if char.isUppercase && index > 0 {
                result += "_"
            }
            result += char.lowercased()
        }
        return result
    }
    
    /// Convert snake_case to PascalCase
    private func convertToPascalCase(_ input: String) -> String {
        let components = input.components(separatedBy: "_")
        return components.map { $0.capitalized }.joined()
    }
    
    /// Collect all files in project
    private func collectAllFiles(in projectURL: URL) async -> [URL] {
        var files: [URL] = []
        let supportedExtensions = ["swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "go", "rs", "cpp", "h", "hpp"]
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return files
        }
        
        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath,
                  supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            files.append(fileURL)
        }
        
        return files
    }
    
    /// Detect language from file extension
    private func detectLanguage(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "java": return "java"
        case "kt": return "kotlin"
        case "go": return "go"
        case "rs": return "rust"
        case "cpp", "cxx", "cc", "h", "hpp": return "cpp"
        default: return "unknown"
        }
    }
    
    /// Extract symbols from file content
    private func extractSymbols(from content: String, language: String, fileURL: URL) -> [SymbolInfo] {
        #if canImport(EditorParsers)
        if TreeSitterManager.shared.isLanguageSupported(language) {
            let treeSitterSymbols = TreeSitterManager.shared.parse(content: content, language: language, fileURL: fileURL)
            return treeSitterSymbols.map { SymbolInfo(name: $0.name, kind: $0.kind, file: $0.file) }
        }
        #endif
        
        // Fallback: simple regex extraction
        return []
    }
    
    private struct SymbolInfo {
        let name: String
        let kind: Any
        let file: URL
    }
}
