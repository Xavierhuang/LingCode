//
//  ContextRankingService.swift
//  LingCode
//
//  Cursor-style context ranking with weighted scoring and tier-based system
//

import Foundation

struct ContextRankingItem {
    let file: URL
    let score: Int
    let content: String
    let tier: ContextTier
    let reason: String
    
    enum ContextTier {
        case tier1  // Always include
        case tier2  // Include if space
        case tier3  // Fallback
    }
}

class ContextRankingService {
    static let shared = ContextRankingService()
    
    private init() {}
    
    /// Build context with Cursor-style ranking algorithm
    func buildContext(
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?,
        query: String?,
        tokenLimit: Int = 8000
    ) -> String {
        var items: [ContextRankingItem] = []
        
        // Tier 1: Always include (highest priority)
        if let activeFile = activeFile,
           let content = try? String(contentsOf: activeFile, encoding: .utf8) {
            items.append(ContextRankingItem(
                file: activeFile,
                score: 100,
                content: content,
                tier: .tier1,
                reason: "Active file"
            ))
        }
        
        if let selectedRange = selectedRange, !selectedRange.isEmpty {
            items.append(ContextRankingItem(
                file: activeFile ?? URL(fileURLWithPath: ""),
                score: 80,
                content: selectedRange,
                tier: .tier1,
                reason: "Selected range"
            ))
        }
        
        if let diagnostics = diagnostics, !diagnostics.isEmpty {
            let diagnosticsContent = diagnostics.joined(separator: "\n")
            items.append(ContextRankingItem(
                file: URL(fileURLWithPath: ""),
                score: 60,
                content: diagnosticsContent,
                tier: .tier1,
                reason: "Diagnostics"
            ))
        }
        
        // Tier 2: Include if space (imports, symbols, recent files)
        if let projectURL = projectURL, let activeFile = activeFile {
            let tier2Items = getTier2Items(
                for: activeFile,
                in: projectURL,
                query: query
            )
            items.append(contentsOf: tier2Items)
        }
        
        // Tier 3: Fallback (tests, interfaces, docs)
        if let projectURL = projectURL {
            let tier3Items = getTier3Items(
                in: projectURL,
                query: query
            )
            items.append(contentsOf: tier3Items)
        }
        
        // Sort by score (highest first)
        let sorted = items.sorted { $0.score > $1.score }
        
        // Convert to ContextItem format (from TokenBudgetOptimizer)
        let contextItems = sorted.map { item in
            ContextItem(
                file: item.file,
                content: item.content,
                score: item.score,
                isActive: item.tier == .tier1 && item.reason == "Active file",
                referencedSymbols: Set<String>() // Would be populated from actual references
            )
        }
        
        // Use token budget optimizer
        let optimized = TokenBudgetOptimizer.shared.optimizeContext(
            items: contextItems,
            maxTokens: tokenLimit
        )
        
        // Build result from optimized items
        var result = ""
        for item in optimized {
            if item.isActive {
                result += "\n\n--- Active File: \(item.file.lastPathComponent) ---\n"
            } else {
                result += "\n\n--- \(item.file.lastPathComponent) ---\n"
            }
            result += item.content
        }
        
        return result
    }
    
    private func getTier2Items(
        for activeFile: URL,
        in projectURL: URL,
        query: String?
    ) -> [ContextRankingItem] {
        var items: [ContextRankingItem] = []
        let fileDependencyService = FileDependencyService.shared
        
        // Direct imports (score: 40)
        let importedFiles = fileDependencyService.findImportedFiles(
            for: activeFile,
            in: projectURL
        )
        for file in importedFiles.prefix(5) {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                // Add Git heat score to context score
                let baseScore = 40
                let gitHeat = GitAwareService.shared.getHeatScore(file: file, line: 1) // Use first line as representative
                let finalScore = baseScore + gitHeat
                
                items.append(ContextRankingItem(
                    file: file,
                    score: finalScore,
                    content: content,
                    tier: .tier2,
                    reason: "Direct import"
                ))
            }
        }
        
        // Symbol references (score: 30)
        let referencedFiles = fileDependencyService.findReferencedFiles(
            for: activeFile,
            in: projectURL
        )
        for file in referencedFiles.prefix(5) {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                items.append(ContextRankingItem(
                    file: file,
                    score: 30,
                    content: content,
                    tier: .tier2,
                    reason: "Symbol referenced"
                ))
            }
        }
        
        // Recently edited files (score: 20)
        let recentFiles = getRecentlyEditedFiles(in: projectURL, limit: 3)
        for file in recentFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                items.append(ContextRankingItem(
                    file: file,
                    score: 20,
                    content: content,
                    tier: .tier2,
                    reason: "Recently edited"
                ))
            }
        }
        
        // Penalize autogenerated/vendor files (score: -50)
        items = items.filter { item in
            let path = item.file.path.lowercased()
            let isVendor = path.contains("node_modules") ||
                          path.contains("vendor") ||
                          path.contains("build") ||
                          path.contains(".generated")
            return !isVendor
        }
        
        return items
    }
    
    private func getTier3Items(
        in projectURL: URL,
        query: String?
    ) -> [ContextRankingItem] {
        var items: [ContextRankingItem] = []
        
        // Test files
        let testFiles = findFiles(matching: ["*Test.swift", "*test.*", "*.spec.*"], in: projectURL)
        for file in testFiles.prefix(2) {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                items.append(ContextRankingItem(
                    file: file,
                    score: 15,
                    content: content,
                    tier: .tier3,
                    reason: "Test file"
                ))
            }
        }
        
        // Interface/type files
        let interfaceFiles = findFiles(matching: ["*Interface*", "*Protocol*", "*Type*"], in: projectURL)
        for file in interfaceFiles.prefix(2) {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                items.append(ContextRankingItem(
                    file: file,
                    score: 10,
                    content: content,
                    tier: .tier3,
                    reason: "Interface/type"
                ))
            }
        }
        
        // README/docs
        let docFiles = findFiles(matching: ["README*", "*.md"], in: projectURL)
        for file in docFiles.prefix(1) {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                items.append(ContextRankingItem(
                    file: file,
                    score: 5,
                    content: content,
                    tier: .tier3,
                    reason: "Documentation"
                ))
            }
        }
        
        return items
    }
    
    private func getRecentlyEditedFiles(in projectURL: URL, limit: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        var files: [(URL, Date)] = []
        
        for case let url as URL in enumerator {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  resourceValues.isRegularFile == true,
                  let modDate = resourceValues.contentModificationDate else {
                continue
            }
            
            files.append((url, modDate))
        }
        
        return files
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    private func findFiles(matching patterns: [String], in projectURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        var files: [URL] = []
        
        for case let url as URL in enumerator {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let fileName = url.lastPathComponent
            for pattern in patterns {
                if matchesPattern(fileName, pattern: pattern) {
                    files.append(url)
                    break
                }
            }
        }
        
        return files
    }
    
    private func matchesPattern(_ fileName: String, pattern: String) -> Bool {
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
        
        if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: fileName.utf16.count)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        }
        
        return fileName.lowercased().contains(pattern.lowercased())
    }
    
    private func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
}
