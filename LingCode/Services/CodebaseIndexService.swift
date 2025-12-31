//
//  CodebaseIndexService.swift
//  LingCode
//
//  Smart codebase indexing for faster, smarter AI context
//

import Foundation
import Combine

/// Indexed symbol information
struct IndexedSymbol: Identifiable, Codable {
    let id: UUID
    let name: String
    let kind: SymbolKind
    let filePath: String
    let line: Int
    let signature: String?
    let documentation: String?
    
    enum SymbolKind: String, Codable {
        case `class`, `struct`, `enum`, `protocol`, `function`, `variable`, `property`, `typealias`, `extension`
    }
}

/// Indexed file information
struct IndexedFile: Identifiable, Codable {
    let id: UUID
    let path: String
    let relativePath: String
    let language: String
    let lastModified: Date
    let lineCount: Int
    let symbols: [IndexedSymbol]
    let imports: [String]
    let summary: String?
}

/// Codebase index for fast lookups
class CodebaseIndexService: ObservableObject {
    static let shared = CodebaseIndexService()
    
    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var indexedFileCount = 0
    @Published var totalSymbolCount = 0
    @Published var lastIndexDate: Date?
    
    private var indexedFiles: [String: IndexedFile] = [:]
    private var symbolIndex: [String: [IndexedSymbol]] = [:] // name -> symbols
    private var fileQueue = DispatchQueue(label: "com.lingcode.indexer", qos: .utility)
    
    private let supportedExtensions = ["swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "go", "rs", "c", "cpp", "h", "hpp", "m", "mm"]
    
    private init() {}
    
    // MARK: - Index Project
    
    /// Index entire project
    func indexProject(at url: URL, completion: ((Int, Int) -> Void)? = nil) {
        guard !isIndexing else { return }
        
        DispatchQueue.main.async {
            self.isIndexing = true
            self.indexProgress = 0
        }
        
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            
            var files: [URL] = []
            self.collectFiles(in: url, into: &files)
            
            let total = files.count
            var processed = 0
            
            for fileURL in files {
                if let indexed = self.indexFile(at: fileURL, relativeTo: url) {
                    self.indexedFiles[indexed.relativePath] = indexed
                    
                    // Update symbol index
                    for symbol in indexed.symbols {
                        if self.symbolIndex[symbol.name] == nil {
                            self.symbolIndex[symbol.name] = []
                        }
                        self.symbolIndex[symbol.name]?.append(symbol)
                    }
                }
                
                processed += 1
                let progress = Double(processed) / Double(total)
                
                DispatchQueue.main.async {
                    self.indexProgress = progress
                    self.indexedFileCount = processed
                }
            }
            
            let symbolCount = self.symbolIndex.values.reduce(0) { $0 + $1.count }
            
            DispatchQueue.main.async {
                self.isIndexing = false
                self.indexProgress = 1.0
                self.totalSymbolCount = symbolCount
                self.lastIndexDate = Date()
                completion?(processed, symbolCount)
            }
        }
    }
    
    // MARK: - File Collection
    
    private func collectFiles(in directory: URL, into files: inout [URL]) {
        let ignoredDirs = [".git", "node_modules", ".build", "build", "DerivedData", "Pods", ".swiftpm", "__pycache__", "venv", ".venv"]
        
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            
            // Skip ignored directories
            if ignoredDirs.contains(fileName) {
                enumerator.skipDescendants()
                continue
            }
            
            // Check if it's a supported file
            let ext = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                files.append(fileURL)
            }
        }
    }
    
    // MARK: - File Indexing
    
    private func indexFile(at url: URL, relativeTo base: URL) -> IndexedFile? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        let relativePath = url.path.replacingOccurrences(of: base.path + "/", with: "")
        let language = detectLanguage(for: url)
        let lines = content.components(separatedBy: .newlines)
        
        let symbols = extractSymbols(from: content, language: language, filePath: relativePath)
        let imports = extractImports(from: content, language: language)
        let summary = generateSummary(from: content, symbols: symbols)
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modDate = attributes?[.modificationDate] as? Date ?? Date()
        
        return IndexedFile(
            id: UUID(),
            path: url.path,
            relativePath: relativePath,
            language: language,
            lastModified: modDate,
            lineCount: lines.count,
            symbols: symbols,
            imports: imports,
            summary: summary
        )
    }
    
    // MARK: - Symbol Extraction
    
    private func extractSymbols(from content: String, language: String, filePath: String) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            switch language {
            case "swift":
                symbols.append(contentsOf: extractSwiftSymbols(from: trimmed, line: index + 1, filePath: filePath))
            case "javascript", "typescript":
                symbols.append(contentsOf: extractJSSymbols(from: trimmed, line: index + 1, filePath: filePath))
            case "python":
                symbols.append(contentsOf: extractPythonSymbols(from: trimmed, line: index + 1, filePath: filePath))
            default:
                break
            }
        }
        
        return symbols
    }
    
    private func extractSwiftSymbols(from line: String, line lineNum: Int, filePath: String) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []
        
        let patterns: [(String, IndexedSymbol.SymbolKind)] = [
            ("^(public |private |internal |fileprivate |open )?class\\s+(\\w+)", .class),
            ("^(public |private |internal |fileprivate )?struct\\s+(\\w+)", .struct),
            ("^(public |private |internal |fileprivate )?enum\\s+(\\w+)", .enum),
            ("^(public |private |internal |fileprivate )?protocol\\s+(\\w+)", .protocol),
            ("^(public |private |internal |fileprivate |open )?(static |class )?func\\s+(\\w+)", .function),
            ("^extension\\s+(\\w+)", .extension)
        ]
        
        for (pattern, kind) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let lastRange = match.range(at: match.numberOfRanges - 1)
                if let swiftRange = Range(lastRange, in: line) {
                    let name = String(line[swiftRange])
                    symbols.append(IndexedSymbol(
                        id: UUID(),
                        name: name,
                        kind: kind,
                        filePath: filePath,
                        line: lineNum,
                        signature: line,
                        documentation: nil
                    ))
                }
            }
        }
        
        return symbols
    }
    
    private func extractJSSymbols(from line: String, line lineNum: Int, filePath: String) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []
        
        let patterns: [(String, IndexedSymbol.SymbolKind)] = [
            ("^(export )?(default )?(async )?function\\s+(\\w+)", .function),
            ("^(export )?(const|let|var)\\s+(\\w+)\\s*=\\s*(async )?\\(", .function),
            ("^class\\s+(\\w+)", .class),
            ("^(export )?(const|let|var)\\s+(\\w+)", .variable)
        ]
        
        for (pattern, kind) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let lastRange = match.range(at: match.numberOfRanges - 1)
                if let swiftRange = Range(lastRange, in: line) {
                    let name = String(line[swiftRange])
                    symbols.append(IndexedSymbol(
                        id: UUID(),
                        name: name,
                        kind: kind,
                        filePath: filePath,
                        line: lineNum,
                        signature: line,
                        documentation: nil
                    ))
                }
            }
        }
        
        return symbols
    }
    
    private func extractPythonSymbols(from line: String, line lineNum: Int, filePath: String) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []
        
        let patterns: [(String, IndexedSymbol.SymbolKind)] = [
            ("^def\\s+(\\w+)", .function),
            ("^async def\\s+(\\w+)", .function),
            ("^class\\s+(\\w+)", .class)
        ]
        
        for (pattern, kind) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let lastRange = match.range(at: match.numberOfRanges - 1)
                if let swiftRange = Range(lastRange, in: line) {
                    let name = String(line[swiftRange])
                    symbols.append(IndexedSymbol(
                        id: UUID(),
                        name: name,
                        kind: kind,
                        filePath: filePath,
                        line: lineNum,
                        signature: line,
                        documentation: nil
                    ))
                }
            }
        }
        
        return symbols
    }
    
    // MARK: - Import Extraction
    
    private func extractImports(from content: String, language: String) -> [String] {
        var imports: [String] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            switch language {
            case "swift":
                if trimmed.hasPrefix("import ") {
                    let module = trimmed.replacingOccurrences(of: "import ", with: "")
                    imports.append(module)
                }
            case "javascript", "typescript":
                if let match = trimmed.range(of: "from ['\"](.+)['\"]", options: .regularExpression) {
                    let modulePart = String(trimmed[match])
                    let module = modulePart.replacingOccurrences(of: "from ", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    imports.append(module)
                }
            case "python":
                if trimmed.hasPrefix("import ") || trimmed.hasPrefix("from ") {
                    imports.append(trimmed)
                }
            default:
                break
            }
        }
        
        return imports
    }
    
    // MARK: - Summary Generation
    
    private func generateSummary(from content: String, symbols: [IndexedSymbol]) -> String {
        let classes = symbols.filter { $0.kind == .class }.count
        let structs = symbols.filter { $0.kind == .struct }.count
        let functions = symbols.filter { $0.kind == .function }.count
        let protocols = symbols.filter { $0.kind == .protocol }.count
        
        var parts: [String] = []
        if classes > 0 { parts.append("\(classes) class\(classes > 1 ? "es" : "")") }
        if structs > 0 { parts.append("\(structs) struct\(structs > 1 ? "s" : "")") }
        if protocols > 0 { parts.append("\(protocols) protocol\(protocols > 1 ? "s" : "")") }
        if functions > 0 { parts.append("\(functions) function\(functions > 1 ? "s" : "")") }
        
        return parts.isEmpty ? "No symbols" : parts.joined(separator: ", ")
    }
    
    // MARK: - Language Detection
    
    private func detectLanguage(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "java": return "java"
        case "kt": return "kotlin"
        case "go": return "go"
        case "rs": return "rust"
        case "c", "h": return "c"
        case "cpp", "hpp", "cc": return "cpp"
        case "m", "mm": return "objc"
        default: return "unknown"
        }
    }
    
    // MARK: - Queries
    
    /// Find symbol by name
    func findSymbol(named name: String) -> [IndexedSymbol] {
        return symbolIndex[name] ?? []
    }
    
    /// Search symbols with prefix
    func searchSymbols(prefix: String) -> [IndexedSymbol] {
        return symbolIndex
            .filter { $0.key.lowercased().hasPrefix(prefix.lowercased()) }
            .flatMap { $0.value }
    }
    
    /// Get file summary for AI context
    func getFileSummary(path: String) -> IndexedFile? {
        return indexedFiles[path]
    }
    
    /// Get relevant files for a query
    func getRelevantFiles(for query: String, limit: Int = 10) -> [IndexedFile] {
        let queryWords = query.lowercased().components(separatedBy: .whitespaces)
        
        return indexedFiles.values
            .map { file -> (IndexedFile, Int) in
                var score = 0
                
                // Match file path
                for word in queryWords {
                    if file.relativePath.lowercased().contains(word) { score += 5 }
                }
                
                // Match symbols
                for symbol in file.symbols {
                    for word in queryWords {
                        if symbol.name.lowercased().contains(word) { score += 3 }
                    }
                }
                
                // Match imports
                for imp in file.imports {
                    for word in queryWords {
                        if imp.lowercased().contains(word) { score += 1 }
                    }
                }
                
                return (file, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Generate codebase overview for AI
    func generateCodebaseOverview() -> String {
        var overview = "## Codebase Overview\n\n"
        overview += "- **Files**: \(indexedFiles.count)\n"
        overview += "- **Symbols**: \(totalSymbolCount)\n\n"
        
        // Group by language
        let byLanguage = Dictionary(grouping: indexedFiles.values) { $0.language }
        overview += "### Languages\n"
        for (lang, files) in byLanguage.sorted(by: { $0.value.count > $1.value.count }) {
            overview += "- \(lang): \(files.count) files\n"
        }
        
        // Key files (most symbols)
        overview += "\n### Key Files\n"
        let topFiles = indexedFiles.values.sorted { $0.symbols.count > $1.symbols.count }.prefix(10)
        for file in topFiles {
            overview += "- `\(file.relativePath)`: \(file.summary ?? "N/A")\n"
        }
        
        return overview
    }
    
    /// Get key files (most symbols) for context
    func getKeyFiles(limit: Int = 3) -> [IndexedFile] {
        return Array(indexedFiles.values.sorted { $0.symbols.count > $1.symbols.count }.prefix(limit))
    }
}

