//
//  ContextManager.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct ContextTemplate {
    let name: String
    let description: String
    let filePatterns: [String]
    let includePatterns: [String]
    let maxFiles: Int
}

class ContextManager {
    static let shared = ContextManager()
    
    private init() {}
    
    // Predefined templates
    static let templates: [ContextTemplate] = [
        ContextTemplate(
            name: "Full Stack Feature",
            description: "Frontend + Backend + Tests",
            filePatterns: ["*.swift", "*.ts", "*.tsx", "*.js", "*.jsx"],
            includePatterns: ["*View.swift", "*Controller.swift", "*Service.swift", "*Test.swift"],
            maxFiles: 10
        ),
        ContextTemplate(
            name: "API Endpoint",
            description: "Route + Handler + Model + Tests",
            filePatterns: ["*.swift", "*.ts", "*.js"],
            includePatterns: ["*Route*", "*Handler*", "*Model*", "*Test*"],
            maxFiles: 8
        ),
        ContextTemplate(
            name: "Component",
            description: "Component + Styles + Tests",
            filePatterns: ["*.tsx", "*.jsx", "*.ts", "*.js", "*.css", "*.scss"],
            includePatterns: ["*Component*", "*Style*", "*Test*", "*.test.*"],
            maxFiles: 6
        )
    ]
    
    func getRelevantContext(
        for query: String,
        in files: [URL],
        maxTokens: Int = 8000
    ) -> String {
        // Score files by relevance
        let scoredFiles = files.map { file -> (URL, Double) in
            let score = scoreFileRelevance(file: file, query: query)
            return (file, score)
        }
        .sorted { $0.1 > $1.1 }
        
        var context = ""
        var tokenCount = 0
        
        for (file, _) in scoredFiles {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            
            // Estimate tokens (rough: 1 token ≈ 4 characters)
            let estimatedTokens = content.count / 4
            
            if tokenCount + estimatedTokens > maxTokens {
                // Compress the file content
                let compressed = compressCode(content)
                let compressedTokens = compressed.count / 4
                
                if tokenCount + compressedTokens <= maxTokens {
                    context += "\n\n--- \(file.lastPathComponent) (compressed) ---\n\(compressed)"
                    tokenCount += compressedTokens
                }
                break
            }
            
            context += "\n\n--- \(file.lastPathComponent) ---\n\(content)"
            tokenCount += estimatedTokens
        }
        
        return context
    }
    
    func compressCode(_ code: String) -> String {
        var compressed = code
        
        // Remove comments
        compressed = removeComments(from: compressed)
        
        // Remove extra whitespace
        compressed = removeExtraWhitespace(from: compressed)
        
        // Keep only essential structure (functions, classes, etc.)
        compressed = keepEssentialStructure(compressed)
        
        return compressed
    }
    
    private func scoreFileRelevance(file: URL, query: String) -> Double {
        var score = 0.0
        
        let fileName = file.lastPathComponent.lowercased()
        let queryLower = query.lowercased()
        let keywords = queryLower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        
        // File name matches
        for keyword in keywords {
            if fileName.contains(keyword) {
                score += 10.0
            }
        }
        
        // Path matches
        let path = file.path.lowercased()
        for keyword in keywords {
            if path.contains(keyword) {
                score += 5.0
            }
        }
        
        // Content matches (quick check)
        if let content = try? String(contentsOf: file, encoding: .utf8) {
            let contentLower = content.lowercased()
            for keyword in keywords {
                if contentLower.contains(keyword) {
                    score += 2.0
                }
            }
        }
        
        return score
    }
    
    private func removeComments(from code: String) -> String {
        var result = code
        
        // Remove single-line comments
        result = result.replacingOccurrences(
            of: #"//.*"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove multi-line comments
        result = result.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression
        )
        
        return result
    }
    
    private func removeExtraWhitespace(from code: String) -> String {
        var result = code
        
        // Replace multiple spaces with single space
        result = result.replacingOccurrences(
            of: #" +"#,
            with: " ",
            options: .regularExpression
        )
        
        // Replace multiple newlines with double newline
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        
        return result
    }
    
    private func keepEssentialStructure(_ code: String) -> String {
        // Keep function/class definitions and key statements
        // This is a simplified version - in production, use AST parsing
        let lines = code.components(separatedBy: .newlines)
        var essential: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Keep definitions
            if trimmed.hasPrefix("func ") ||
               trimmed.hasPrefix("class ") ||
               trimmed.hasPrefix("struct ") ||
               trimmed.hasPrefix("enum ") ||
               trimmed.hasPrefix("protocol ") ||
               trimmed.hasPrefix("extension ") ||
               trimmed.hasPrefix("def ") ||
               trimmed.hasPrefix("function ") ||
               trimmed.hasPrefix("export ") ||
               trimmed.hasPrefix("import ") ||
               trimmed.hasPrefix("from ") {
                essential.append(line)
            } else if trimmed.hasPrefix("return ") ||
                      trimmed.hasPrefix("if ") ||
                      trimmed.hasPrefix("guard ") ||
                      trimmed.hasPrefix("for ") ||
                      trimmed.hasPrefix("while ") {
                essential.append(line)
            }
        }
        
        return essential.joined(separator: "\n")
    }
    
    func getContextUsingTemplate(
        _ template: ContextTemplate,
        for file: URL,
        in projectURL: URL
    ) -> String {
        // Find files matching template patterns
        var matchingFiles: [URL] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ""
        }
        
        for case let url as URL in enumerator {
            guard !url.hasDirectoryPath else { continue }
            
            let fileName = url.lastPathComponent
            var matches = false
            
            // Check file patterns
            for pattern in template.filePatterns {
                if matchesPattern(fileName, pattern: pattern) {
                    matches = true
                    break
                }
            }
            
            // Check include patterns
            if matches {
                for includePattern in template.includePatterns {
                    if matchesPattern(fileName, pattern: includePattern) {
                        matchingFiles.append(url)
                        break
                    }
                }
            }
        }
        
        // Limit to maxFiles
        let selectedFiles = Array(matchingFiles.prefix(template.maxFiles))
        
        // Build context
        var context = ""
        for file in selectedFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                context += "\n\n--- \(file.lastPathComponent) ---\n\(content.prefix(2000))"
            }
        }
        
        return context
    }
    
    private func matchesPattern(_ fileName: String, pattern: String) -> Bool {
        // Simple pattern matching (supports * wildcard)
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
        
        if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: fileName.utf16.count)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        }
        
        return fileName.lowercased().contains(pattern.lowercased())
    }
}

