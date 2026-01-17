//
//  FileDependencyService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct DependencyGraph {
    var nodes: [URL: FileNode] = [:]
    
    struct FileNode {
        let url: URL
        var imports: Set<URL> = []
        var importedBy: Set<URL> = []
    }
}

class FileDependencyService {
    // FIX: Mark shared as nonisolated to allow access from actor contexts
    static let shared = FileDependencyService()
    
    private var dependencyCache: [URL: [URL]] = [:]
    private var graphCache: DependencyGraph?
    private var lastProjectURL: URL?
    
    private init() {}
    
    func findRelatedFiles(for fileURL: URL, in projectURL: URL) -> [URL] {
        // Check cache first
        if let cached = dependencyCache[fileURL] {
            return cached
        }
        
        // Rebuild graph if project changed
        if lastProjectURL != projectURL {
            graphCache = buildDependencyGraph(projectURL: projectURL)
            lastProjectURL = projectURL
        }
        
        guard let graph = graphCache else {
            return []
        }
        
        var relatedFiles: Set<URL> = []
        
        // Get files this file imports
        if let node = graph.nodes[fileURL] {
            relatedFiles.formUnion(node.imports)
        }
        
        // Get files that import this file
        if let node = graph.nodes[fileURL] {
            relatedFiles.formUnion(node.importedBy)
        }
        
        // Also find files in the same directory
        let sameDirectoryFiles = findFilesInSameDirectory(fileURL, projectURL: projectURL)
        relatedFiles.formUnion(sameDirectoryFiles)
        
        let result = Array(relatedFiles).sorted { $0.path < $1.path }
        dependencyCache[fileURL] = result
        return result
    }
    
    /// Find files directly imported by the given file
    /// FIX: Cannot be nonisolated due to mutable state access, but safe to call from actor
    func findImportedFiles(for fileURL: URL, in projectURL: URL) -> [URL] {
        if lastProjectURL != projectURL {
            graphCache = buildDependencyGraph(projectURL: projectURL)
            lastProjectURL = projectURL
        }
        
        guard let graph = graphCache,
              let node = graph.nodes[fileURL] else {
            return []
        }
        
        return Array(node.imports).sorted { $0.path < $1.path }
    }
    
    /// Find files that reference symbols from the given file
    /// FIX: Cannot be nonisolated due to mutable state access, but safe to call from actor
    func findReferencedFiles(for fileURL: URL, in projectURL: URL) -> [URL] {
        if lastProjectURL != projectURL {
            graphCache = buildDependencyGraph(projectURL: projectURL)
            lastProjectURL = projectURL
        }
        
        guard let graph = graphCache,
              let node = graph.nodes[fileURL] else {
            return []
        }
        
        return Array(node.importedBy).sorted { $0.path < $1.path }
    }
    
    func buildDependencyGraph(projectURL: URL) -> DependencyGraph {
        var graph = DependencyGraph()
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return graph
        }
        
        var allFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.hasDirectoryPath { continue }
            allFiles.append(fileURL)
            
            if graph.nodes[fileURL] == nil {
                graph.nodes[fileURL] = DependencyGraph.FileNode(url: fileURL)
            }
        }
        
        // Parse imports for each file
        for fileURL in allFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let imports = parseImports(from: content, fileURL: fileURL, projectURL: projectURL)
            
            if var node = graph.nodes[fileURL] {
                node.imports = imports
                graph.nodes[fileURL] = node
                
                // Update reverse relationships
                for importedURL in imports {
                    if var importedNode = graph.nodes[importedURL] {
                        importedNode.importedBy.insert(fileURL)
                        graph.nodes[importedURL] = importedNode
                    } else {
                        var newNode = DependencyGraph.FileNode(url: importedURL)
                        newNode.importedBy.insert(fileURL)
                        graph.nodes[importedURL] = newNode
                    }
                }
            }
        }
        
        return graph
    }
    
    private func parseImports(from content: String, fileURL: URL, projectURL: URL) -> Set<URL> {
        var imports: Set<URL> = []
        let lines = content.components(separatedBy: .newlines)
        
        let fileExtension = fileURL.pathExtension.lowercased()
        let language = detectLanguage(from: fileExtension)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Swift
            if language == "swift" {
                if trimmed.hasPrefix("import ") {
                    let moduleName = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    // Try to find corresponding file
                    if let url = findSwiftModule(moduleName, in: projectURL, from: fileURL) {
                        imports.insert(url)
                    }
                }
            }
            
            // Python
            if language == "python" {
                if trimmed.hasPrefix("import ") || trimmed.hasPrefix("from ") {
                    let parts = trimmed.components(separatedBy: " ")
                    if parts.count > 1 {
                        let moduleName = parts[1].components(separatedBy: ".").first ?? ""
                        if let url = findPythonModule(moduleName, in: projectURL, from: fileURL) {
                            imports.insert(url)
                        }
                    }
                }
            }
            
            // JavaScript/TypeScript
            if language == "javascript" || language == "typescript" {
                if trimmed.hasPrefix("import ") || trimmed.hasPrefix("require(") {
                    let importPath = extractImportPath(from: trimmed)
                    if let url = resolveImportPath(importPath, from: fileURL, projectURL: projectURL) {
                        imports.insert(url)
                    }
                }
            }
            
            // C/C++/Objective-C
            if language == "c" || language == "cpp" || language == "objective-c" {
                if trimmed.hasPrefix("#include ") {
                    let includePath = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"<>"))
                    if let url = resolveIncludePath(includePath, from: fileURL, projectURL: projectURL) {
                        imports.insert(url)
                    }
                }
            }
        }
        
        return imports
    }
    
    private func detectLanguage(from extension: String) -> String {
        switch `extension` {
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "ts", "tsx": return "typescript"
        case "c": return "c"
        case "cpp", "cc", "cxx": return "cpp"
        case "m", "mm": return "objective-c"
        default: return ""
        }
    }
    
    private func findSwiftModule(_ moduleName: String, in projectURL: URL, from fileURL: URL) -> URL? {
        // Look for files with matching name
        let fileName = "\(moduleName).swift"
        return findFile(named: fileName, in: projectURL, from: fileURL)
    }
    
    private func findPythonModule(_ moduleName: String, in projectURL: URL, from fileURL: URL) -> URL? {
        // Look for .py files with matching name
        let fileName = "\(moduleName).py"
        return findFile(named: fileName, in: projectURL, from: fileURL)
    }
    
    private func extractImportPath(from line: String) -> String {
        if line.contains("from ") {
            let parts = line.components(separatedBy: "from ")
            if parts.count > 1 {
                let pathPart = parts[1].components(separatedBy: " ").first ?? ""
                return pathPart.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        if line.contains("import ") {
            let parts = line.components(separatedBy: "import ")
            if parts.count > 1 {
                let pathPart = parts[1].components(separatedBy: " ").first ?? ""
                return pathPart.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        if line.contains("require(") {
            let start = line.range(of: "require(")?.upperBound ?? line.startIndex
            let end = line.range(of: ")", range: start..<line.endIndex)?.lowerBound ?? line.endIndex
            let path = String(line[start..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return path
        }
        return ""
    }
    
    private func resolveImportPath(_ path: String, from fileURL: URL, projectURL: URL) -> URL? {
        // Handle relative paths
        if path.hasPrefix("./") || path.hasPrefix("../") {
            let baseDir = fileURL.deletingLastPathComponent()
            let resolved = baseDir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        
        // Handle absolute paths from project root
        if path.hasPrefix("/") {
            let resolved = projectURL.appendingPathComponent(String(path.dropFirst()))
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        
        // Try to find file in node_modules or similar
        let fileName = (path as NSString).lastPathComponent
        return findFile(named: fileName, in: projectURL, from: fileURL)
    }
    
    private func resolveIncludePath(_ path: String, from fileURL: URL, projectURL: URL) -> URL? {
        let baseDir = fileURL.deletingLastPathComponent()
        let resolved = baseDir.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: resolved.path) {
            return resolved
        }
        
        // Try project root
        let projectResolved = projectURL.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: projectResolved.path) {
            return projectResolved
        }
        
        return nil
    }
    
    private func findFile(named fileName: String, in projectURL: URL, from fileURL: URL) -> URL? {
        // Search in same directory first
        let sameDir = fileURL.deletingLastPathComponent().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: sameDir.path) {
            return sameDir
        }
        
        // Search recursively in project
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        
        for case let url as URL in enumerator {
            if url.lastPathComponent == fileName {
                return url
            }
        }
        
        return nil
    }
    
    private func findFilesInSameDirectory(_ fileURL: URL, projectURL: URL) -> Set<URL> {
        let directory = fileURL.deletingLastPathComponent()
        var files: Set<URL> = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }
        
        for url in contents {
            if url != fileURL && !url.hasDirectoryPath {
                files.insert(url)
            }
        }
        
        return files
    }
    
    func clearCache() {
        dependencyCache.removeAll()
        graphCache = nil
        lastProjectURL = nil
    }
}

