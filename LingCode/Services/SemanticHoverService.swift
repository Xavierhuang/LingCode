//
//  SemanticHoverService.swift
//  LingCode
//
//  Semantic "Live" Hover: Use TreeSitterManager.parse results for Peek Definition/Hover UI
//  No Language Server required - uses local AST cache
//

import Foundation

/// Hover information for a symbol
struct HoverInfo {
    let symbolName: String
    let kind: String
    let signature: String?
    let documentation: String?
    let file: URL
    let range: Range<Int>
    let parent: String?
    let relatedSymbols: [String]
}

/// Service for providing semantic hover information without Language Server
class SemanticHoverService {
    static let shared = SemanticHoverService()
    
    private var symbolCache: [String: [HoverInfo]] = [:] // file path -> hover infos
    private var parseCache: [String: Date] = [:] // file path -> last parse time
    private let cacheQueue = DispatchQueue(label: "com.lingcode.hover", qos: .utility)
    
    private init() {}
    
    /// Get hover information for a symbol at a specific position
    func getHoverInfo(
        at line: Int,
        column: Int,
        in fileURL: URL,
        projectURL: URL
    ) async -> HoverInfo? {
        let filePath = fileURL.path
        
        // Check if we need to re-parse (file might have changed)
        let needsReparse = shouldReparse(fileURL: fileURL)
        
        if needsReparse || symbolCache[filePath] == nil {
            await parseFile(fileURL: fileURL, projectURL: projectURL)
        }
        
        // Find symbol at the given position
        guard let hoverInfos = symbolCache[filePath] else {
            return nil
        }
        
        // Find symbol that contains this position
        for info in hoverInfos {
            if info.range.contains(line) {
                return info
            }
        }
        
        return nil
    }
    
    /// Get all symbols in a file for quick lookup
    func getSymbols(in fileURL: URL, projectURL: URL) async -> [HoverInfo] {
        let filePath = fileURL.path
        
        if symbolCache[filePath] == nil || shouldReparse(fileURL: fileURL) {
            await parseFile(fileURL: fileURL, projectURL: projectURL)
        }
        
        return symbolCache[filePath] ?? []
    }
    
    /// Parse file and extract hover information
    private func parseFile(fileURL: URL, projectURL: URL) async {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }
        
        let filePath = fileURL.path
        let language = detectLanguage(for: fileURL)
        
        var hoverInfos: [HoverInfo] = []
        
        #if canImport(EditorParsers)
        if TreeSitterManager.shared.isLanguageSupported(language) {
            let symbols = TreeSitterManager.shared.parse(content: content, language: language, fileURL: fileURL)
            
            for symbol in symbols {
                // Find related symbols using GraphRAG
                let relatedSymbols = await findRelatedSymbols(
                    symbolName: symbol.name,
                    in: projectURL,
                    sourceFile: fileURL
                )
                
                let hoverInfo = HoverInfo(
                    symbolName: symbol.name,
                    kind: String(describing: symbol.kind),
                    signature: symbol.signature,
                    documentation: extractDocumentation(
                        content: content,
                        line: symbol.range.lowerBound
                    ),
                    file: symbol.file,
                    range: symbol.range,
                    parent: symbol.parent,
                    relatedSymbols: relatedSymbols
                )
                
                hoverInfos.append(hoverInfo)
            }
        }
        #endif
        
        // Cache the results
        cacheQueue.async {
            self.symbolCache[filePath] = hoverInfos
            self.parseCache[filePath] = Date()
        }
    }
    
    /// Check if file needs to be re-parsed
    private func shouldReparse(fileURL: URL) -> Bool {
        let filePath = fileURL.path
        
        guard let lastParse = parseCache[filePath],
              let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let modDate = fileAttributes[.modificationDate] as? Date else {
            return true
        }
        
        return modDate > lastParse
    }
    
    /// Find related symbols using GraphRAG
    private func findRelatedSymbols(
        symbolName: String,
        in projectURL: URL,
        sourceFile: URL
    ) async -> [String] {
        let relationships = await GraphRAGService.shared.findRelatedFiles(
            for: symbolName,
            in: projectURL,
            relationshipTypes: [.inheritance, .instantiation, .methodCall]
        )
        
        // Get unique related symbol names
        let relatedNames = Set(relationships.map { $0.targetSymbol })
        return Array(relatedNames).filter { $0 != symbolName }
    }
    
    /// Extract documentation comment above symbol
    private func extractDocumentation(content: String, line: Int) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard line > 0 && line < lines.count else {
            return nil
        }
        
        var docLines: [String] = []
        var currentLine = line - 1
        
        // Look backwards for documentation comments
        while currentLine >= 0 {
            let trimmed = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Check for documentation comment patterns
            if trimmed.hasPrefix("///") {
                docLines.insert(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces), at: 0)
            } else if trimmed.hasPrefix("/**") || trimmed.hasPrefix("*") {
                docLines.insert(trimmed.dropFirst(trimmed.hasPrefix("/**") ? 3 : 1).trimmingCharacters(in: .whitespaces), at: 0)
            } else if trimmed.hasPrefix("#") && (trimmed.hasPrefix("# ") || trimmed.hasPrefix("##")) {
                // Python/JS docstring
                docLines.insert(trimmed.dropFirst(trimmed.hasPrefix("##") ? 2 : 1).trimmingCharacters(in: .whitespaces), at: 0)
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("/*") {
                // Hit non-comment line, stop
                break
            }
            
            currentLine -= 1
            
            // Stop after 10 lines of comments
            if docLines.count >= 10 {
                break
            }
        }
        
        return docLines.isEmpty ? nil : docLines.joined(separator: "\n")
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
        case "go": return "go"
        case "rs": return "rust"
        case "cpp", "cxx", "cc": return "cpp"
        default: return "unknown"
        }
    }
    
    /// Clear cache for a file
    func clearCache(for fileURL: URL) {
        let filePath = fileURL.path
        cacheQueue.async {
            self.symbolCache.removeValue(forKey: filePath)
            self.parseCache.removeValue(forKey: filePath)
        }
    }
    
    /// Clear all caches
    func clearAllCaches() {
        cacheQueue.async {
            self.symbolCache.removeAll()
            self.parseCache.removeAll()
        }
    }
}
