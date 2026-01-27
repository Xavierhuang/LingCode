//
//  AutoImportService.swift
//  LingCode
//
//  Automatically adds missing import statements when generating code (Cursor feature)
//

import Foundation

/// Service that automatically adds missing import statements to generated code
class AutoImportService {
    static let shared = AutoImportService()
    
    private let codebaseIndex = CodebaseIndexService.shared
    private let fileDependencyService = FileDependencyService.shared
    
    private init() {}
    
    /// Analyze generated code and add missing imports based on symbols used
    func addMissingImports(
        to code: String,
        filePath: String,
        projectURL: URL?,
        language: String?
    ) -> String {
        guard let projectURL = projectURL else { return code }
        
        let lang = language ?? detectLanguage(from: filePath)
        let usedSymbols = extractUsedSymbols(from: code, language: lang)
        
        guard !usedSymbols.isEmpty else { return code }
        
        // Find where imports should be added
        let existingImports = extractExistingImports(from: code, language: lang)
        let missingImports = findMissingImports(
            usedSymbols: usedSymbols,
            existingImports: existingImports,
            filePath: filePath,
            projectURL: projectURL,
            language: lang
        )
        
        guard !missingImports.isEmpty else { return code }
        
        // Add imports at the appropriate location
        return insertImports(
            into: code,
            imports: missingImports,
            existingImports: existingImports,
            language: lang
        )
    }
    
    // MARK: - Private Helpers
    
    private func detectLanguage(from filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "java": return "java"
        case "kt": return "kotlin"
        case "go": return "go"
        default: return "swift"
        }
    }
    
    private func extractUsedSymbols(from code: String, language: String) -> Set<String> {
        var symbols: Set<String> = []
        
        switch language {
        case "swift":
            // Extract class, struct, enum, protocol names, and common Swift types
            let patterns = [
                #"\b(class|struct|enum|protocol)\s+(\w+)"#,
                #"\b(UI[A-Z]\w+|NS[A-Z]\w+|CG[A-Z]\w+|SK[A-Z]\w+)"#, // UIKit/AppKit types
                #"\b(ObservableObject|Published|State|Binding)\b"#, // SwiftUI
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(code.startIndex..<code.endIndex, in: code)
                    regex.enumerateMatches(in: code, options: [], range: range) { match, _, _ in
                        if let match = match, match.numberOfRanges > 2 {
                            if let symbolRange = Range(match.range(at: 2), in: code) {
                                symbols.insert(String(code[symbolRange]))
                            }
                        }
                    }
                }
            }
        case "javascript", "typescript":
            // Extract imported/used module names
            let patterns = [
                #"from\s+['"]([^'"]+)['"]"#,
                #"require\(['"]([^'"]+)['"]\)"#,
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(code.startIndex..<code.endIndex, in: code)
                    regex.enumerateMatches(in: code, options: [], range: range) { match, _, _ in
                        if let match = match, match.numberOfRanges > 1,
                           let moduleRange = Range(match.range(at: 1), in: code) {
                            symbols.insert(String(code[moduleRange]))
                        }
                    }
                }
            }
        case "python":
            // Extract module names from usage
            let patterns = [
                #"\b([a-z_][a-z0-9_]*)\."#, // module.function pattern
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(code.startIndex..<code.endIndex, in: code)
                    regex.enumerateMatches(in: code, options: [], range: range) { match, _, _ in
                        if let match = match, match.numberOfRanges > 1,
                           let moduleRange = Range(match.range(at: 1), in: code) {
                            let module = String(code[moduleRange])
                            // Skip built-in modules and common patterns
                            if !["self", "super", "cls", "str", "int", "list", "dict"].contains(module) {
                                symbols.insert(module)
                            }
                        }
                    }
                }
            }
        default:
            break
        }
        
        return symbols
    }
    
    private func extractExistingImports(from code: String, language: String) -> [String] {
        var imports: [String] = []
        let lines = code.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            switch language {
            case "swift":
                if trimmed.hasPrefix("import ") {
                    let module = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    imports.append(module)
                }
            case "javascript", "typescript":
                if trimmed.hasPrefix("import ") || trimmed.hasPrefix("export ") {
                    if let fromRange = trimmed.range(of: #"from\s+['"]([^'"]+)['"]"#, options: .regularExpression) {
                        let importLine = String(trimmed[fromRange])
                        imports.append(importLine)
                    }
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
    
    private func findMissingImports(
        usedSymbols: Set<String>,
        existingImports: [String],
        filePath: String,
        projectURL: URL,
        language: String
    ) -> [String] {
        var missing: [String] = []
        
        // Check codebase index for symbol definitions
        for symbol in usedSymbols {
            let symbolInfos = codebaseIndex.findSymbol(named: symbol)
            if let symbolInfo = symbolInfos.first {
                // Symbol exists in codebase - check if import is needed
                if needsImport(symbol: symbol, filePath: filePath, symbolPath: symbolInfo.filePath, language: language) {
                    let importStatement = generateImport(
                        for: symbol,
                        symbolPath: symbolInfo.filePath,
                        filePath: filePath,
                        projectURL: projectURL,
                        language: language
                    )
                    if let importStmt = importStatement, !existingImports.contains(importStmt) {
                        missing.append(importStmt)
                    }
                }
            } else {
                // Check if it's a standard library/framework import
                if let stdImport = getStandardLibraryImport(for: symbol, language: language),
                   !existingImports.contains(stdImport) {
                    missing.append(stdImport)
                }
            }
        }
        
        return missing.sorted()
    }
    
    private func needsImport(symbol: String, filePath: String, symbolPath: String, language: String) -> Bool {
        // Same file - no import needed
        if filePath == symbolPath { return false }
        
        // Same directory - might not need import (depends on language)
        let fileDir = (filePath as NSString).deletingLastPathComponent
        let symbolDir = (symbolPath as NSString).deletingLastPathComponent
        
        switch language {
        case "swift":
            // Swift needs imports for different modules
            return fileDir != symbolDir
        case "python":
            // Python needs imports for different packages
            return fileDir != symbolDir
        case "javascript", "typescript":
            // JS/TS needs imports for different files
            return filePath != symbolPath
        default:
            return true
        }
    }
    
    private func generateImport(
        for symbol: String,
        symbolPath: String,
        filePath: String,
        projectURL: URL,
        language: String
    ) -> String? {
        switch language {
        case "swift":
            // For Swift, we'd need to determine the module name
            // This is simplified - in practice, you'd parse the module structure
            let relativePath = (symbolPath as NSString).replacingOccurrences(of: projectURL.path + "/", with: "")
            let components = relativePath.components(separatedBy: "/")
            if components.count > 1 {
                // Assume first component is module name
                return "import \(components[0])"
            }
            return nil
        case "python":
            // Convert file path to module path
            let relativePath = (symbolPath as NSString).replacingOccurrences(of: projectURL.path + "/", with: "")
            let modulePath = relativePath.replacingOccurrences(of: ".py", with: "").replacingOccurrences(of: "/", with: ".")
            return "from \(modulePath) import \(symbol)"
        case "javascript", "typescript":
            // Calculate relative import path
            let fileDir = (filePath as NSString).deletingLastPathComponent
            let symbolDir = (symbolPath as NSString).deletingLastPathComponent
            let relativePath = calculateRelativePath(from: fileDir, to: symbolPath)
            let ext = language == "typescript" ? ".ts" : ".js"
            return "import { \(symbol) } from '\(relativePath.replacingOccurrences(of: ext, with: ""))'"
        default:
            return nil
        }
    }
    
    private func getStandardLibraryImport(for symbol: String, language: String) -> String? {
        switch language {
        case "swift":
            // Common Swift frameworks
            let swiftFrameworks: [String: String] = [
                "UIView": "UIKit",
                "NSView": "AppKit",
                "View": "SwiftUI",
                "ObservableObject": "Combine",
                "Published": "Combine",
            ]
            return swiftFrameworks[symbol].map { "import \($0)" }
        case "python":
            // Common Python stdlib
            let pythonModules = ["os", "sys", "json", "datetime", "collections", "itertools"]
            if pythonModules.contains(symbol.lowercased()) {
                return "import \(symbol.lowercased())"
            }
        default:
            break
        }
        return nil
    }
    
    private func calculateRelativePath(from: String, to: String) -> String {
        let fromComponents = from.components(separatedBy: "/").filter { !$0.isEmpty }
        let toComponents = to.components(separatedBy: "/").filter { !$0.isEmpty }
        
        var commonPrefix = 0
        for (i, component) in fromComponents.enumerated() {
            if i < toComponents.count && component == toComponents[i] {
                commonPrefix += 1
            } else {
                break
            }
        }
        
        let upLevels = fromComponents.count - commonPrefix
        let relativePath = String(repeating: "../", count: upLevels) +
                          toComponents.dropFirst(commonPrefix).joined(separator: "/")
        
        return relativePath
    }
    
    private func insertImports(
        into code: String,
        imports: [String],
        existingImports: [String],
        language: String
    ) -> String {
        let lines = code.components(separatedBy: .newlines)
        var result: [String] = []
        var importsInserted = false
        
        // Find insertion point
        var insertIndex = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this is an import line
            let isImport: Bool
            switch language {
            case "swift":
                isImport = trimmed.hasPrefix("import ")
            case "javascript", "typescript":
                isImport = trimmed.hasPrefix("import ") || trimmed.hasPrefix("export ")
            case "python":
                isImport = trimmed.hasPrefix("import ") || trimmed.hasPrefix("from ")
            default:
                isImport = false
            }
            
            if isImport {
                insertIndex = index + 1
            } else if !trimmed.isEmpty && insertIndex == 0 {
                // First non-empty, non-import line - insert before this
                insertIndex = index
                break
            }
        }
        
        // Build result with imports inserted
        for (index, line) in lines.enumerated() {
            if index == insertIndex && !importsInserted {
                // Insert new imports
                for importStmt in imports {
                    result.append(importStmt)
                }
                if !existingImports.isEmpty {
                    result.append("") // Blank line after imports
                }
                importsInserted = true
            }
            result.append(line)
        }
        
        // If no insertion point found, prepend imports
        if !importsInserted {
            return imports.joined(separator: "\n") + "\n\n" + code
        }
        
        return result.joined(separator: "\n")
    }
}
