//
//  DefinitionService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct Definition: Identifiable {
    let id = UUID()
    let name: String
    let kind: DefinitionKind
    let file: URL
    let line: Int
    let column: Int
    let preview: String
    
    enum DefinitionKind {
        case function
        case variable
        case classDefinition
        case structure
        case enumeration
        case interface
        case type
        case module
    }
}

struct Reference: Identifiable {
    let id = UUID()
    let file: URL
    let line: Int
    let column: Int
    let context: String
}

class DefinitionService {
    static let shared = DefinitionService()
    
    private init() {}
    
    func findDefinition(
        for symbol: String,
        in projectURL: URL,
        currentFile: URL?,
        language: String?
    ) -> [Definition] {
        var definitions: [Definition] = []
        
        guard !symbol.isEmpty else { return definitions }
        
        // Search in current file first
        if let currentFile = currentFile,
           let content = try? String(contentsOf: currentFile, encoding: .utf8) {
            definitions.append(contentsOf: findDefinitionsInFile(
                symbol: symbol,
                content: content,
                file: currentFile,
                language: language
            ))
        }
        
        // Search in project
        if let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL == currentFile || fileURL.hasDirectoryPath {
                    continue
                }
                
                // Only search code files
                let supportedExtensions = ["swift", "py", "js", "ts", "java", "kt", "go", "rs", "cpp", "c", "h"]
                guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                    continue
                }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    definitions.append(contentsOf: findDefinitionsInFile(
                        symbol: symbol,
                        content: content,
                        file: fileURL,
                        language: fileURL.pathExtension
                    ))
                }
                
                // Limit to avoid performance issues
                if definitions.count > 50 {
                    break
                }
            }
        }
        
        return definitions
    }
    
    private func findDefinitionsInFile(
        symbol: String,
        content: String,
        file: URL,
        language: String?
    ) -> [Definition] {
        var definitions: [Definition] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Function definitions
            let functionPatterns: [(String, Definition.DefinitionKind)] = [
                (#"func\s+\#(NSRegularExpression.escapedPattern(for: symbol))\s*\("#, .function),
                (#"def\s+\#(NSRegularExpression.escapedPattern(for: symbol))\s*\("#, .function),
                (#"function\s+\#(NSRegularExpression.escapedPattern(for: symbol))\s*\("#, .function),
                (#"const\s+\#(NSRegularExpression.escapedPattern(for: symbol))\s*="#, .variable),
                (#"let\s+\#(NSRegularExpression.escapedPattern(for: symbol))\s*[=:]"#, .variable),
                (#"var\s+\#(NSRegularExpression.escapedPattern(for: symbol))\s*[=:]"#, .variable),
                (#"class\s+\#(NSRegularExpression.escapedPattern(for: symbol))\b"#, .classDefinition),
                (#"struct\s+\#(NSRegularExpression.escapedPattern(for: symbol))\b"#, .structure),
                (#"enum\s+\#(NSRegularExpression.escapedPattern(for: symbol))\b"#, .enumeration),
                (#"interface\s+\#(NSRegularExpression.escapedPattern(for: symbol))\b"#, .interface),
                (#"protocol\s+\#(NSRegularExpression.escapedPattern(for: symbol))\b"#, .interface),
                (#"type\s+\#(NSRegularExpression.escapedPattern(for: symbol))\b"#, .type)
            ]
            
            for (pattern, kind) in functionPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                    
                    // Get column
                    let column = line.range(of: symbol)?.lowerBound.utf16Offset(in: line) ?? 0
                    
                    definitions.append(Definition(
                        name: symbol,
                        kind: kind,
                        file: file,
                        line: index + 1,
                        column: column,
                        preview: String(trimmed.prefix(100))
                    ))
                    break
                }
            }
        }
        
        return definitions
    }
    
    func findReferences(
        for symbol: String,
        in projectURL: URL,
        excludeDefinitions: Bool = true
    ) -> [Reference] {
        var references: [Reference] = []
        
        guard !symbol.isEmpty else { return references }
        
        if let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.hasDirectoryPath {
                    continue
                }
                
                // Only search code files
                let supportedExtensions = ["swift", "py", "js", "ts", "java", "kt", "go", "rs", "cpp", "c", "h", "m", "mm"]
                guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                    continue
                }
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    references.append(contentsOf: findReferencesInFile(
                        symbol: symbol,
                        content: content,
                        file: fileURL
                    ))
                }
                
                // Limit to avoid performance issues
                if references.count > 100 {
                    break
                }
            }
        }
        
        return references
    }
    
    private func findReferencesInFile(
        symbol: String,
        content: String,
        file: URL
    ) -> [Reference] {
        var references: [Reference] = []
        let lines = content.components(separatedBy: .newlines)
        
        let pattern = #"\b\#(NSRegularExpression.escapedPattern(for: symbol))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return references
        }
        
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, options: [], range: range)
            
            for match in matches {
                if let matchRange = Range(match.range, in: line) {
                    references.append(Reference(
                        file: file,
                        line: index + 1,
                        column: line.distance(from: line.startIndex, to: matchRange.lowerBound),
                        context: String(line.trimmingCharacters(in: .whitespaces).prefix(100))
                    ))
                }
            }
        }
        
        return references
    }
    
    func getSymbolAtPosition(
        in content: String,
        at position: Int
    ) -> String? {
        guard position >= 0 && position <= content.count else { return nil }
        
        let index = content.index(content.startIndex, offsetBy: min(position, content.count - 1))
        
        // Find word boundaries
        var start = index
        var end = index
        
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        
        // Go backward to find start
        while start > content.startIndex {
            let prevIndex = content.index(before: start)
            let char = content[prevIndex]
            if char.unicodeScalars.allSatisfy({ validChars.contains($0) }) {
                start = prevIndex
            } else {
                break
            }
        }
        
        // Go forward to find end
        while end < content.endIndex {
            let char = content[end]
            if char.unicodeScalars.allSatisfy({ validChars.contains($0) }) {
                end = content.index(after: end)
            } else {
                break
            }
        }
        
        if start < end {
            return String(content[start..<end])
        }
        
        return nil
    }
}

