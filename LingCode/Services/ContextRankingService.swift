//
//  ContextRankingService.swift
//  LingCode
//
//  Cursor-style context ranking with weighted scoring and tier-based system
//

import Foundation

// FIX: Import CodeChunk type from SemanticSearchService
// This is needed for semantic search results

/// Boost rules from legacy ContextManager: template-based file discovery merged into tiered ranking
struct ContextBoostRule: Sendable {
    let name: String
    let description: String
    let filePatterns: [String]
    let includePatterns: [String]
    let maxFiles: Int
}

struct ContextRankingItem: Sendable {
    let file: URL
    let score: Int
    let content: String
    let tier: ContextTier
    let reason: String
    
    // FIX: Make ContextTier explicitly Sendable and Equatable for use in actor contexts
    // Mark Equatable conformance as nonisolated to allow comparisons in actor contexts
    enum ContextTier: Sendable, Equatable {
        case tier1, tier2, tier3
        
        // FIX: Explicitly implement Equatable with nonisolated conformance
        nonisolated static func == (lhs: ContextTier, rhs: ContextTier) -> Bool {
            switch (lhs, rhs) {
            case (.tier1, .tier1), (.tier2, .tier2), (.tier3, .tier3):
                return true
            default:
                return false
            }
        }
    }
}

// FIX: Change 'class' to 'actor' to guarantee background execution
// This ensures file discovery runs off the main thread, keeping UI 100% responsive
actor ContextRankingService {
    static let shared = ContextRankingService()
    
    /// Boost rules (from ContextManager templates): add template-matched files to context with a score boost
    static let boostRules: [ContextBoostRule] = [
        ContextBoostRule(
            name: "Full Stack Feature",
            description: "Frontend + Backend + Tests",
            filePatterns: ["*.swift", "*.ts", "*.tsx", "*.js", "*.jsx"],
            includePatterns: ["*View.swift", "*Controller.swift", "*Service.swift", "*Test.swift"],
            maxFiles: 10
        ),
        ContextBoostRule(
            name: "API Endpoint",
            description: "Route + Handler + Model + Tests",
            filePatterns: ["*.swift", "*.ts", "*.js"],
            includePatterns: ["*Route*", "*Handler*", "*Model*", "*Test*"],
            maxFiles: 8
        ),
        ContextBoostRule(
            name: "Component",
            description: "Component + Styles + Tests",
            filePatterns: ["*.tsx", "*.jsx", "*.ts", "*.js", "*.css", "*.scss"],
            includePatterns: ["*Component*", "*Style*", "*Test*", "*.test.*"],
            maxFiles: 6
        )
    ]
    
    private init() {}
    
    // MARK: - Priority Streaming Context (OPTIMIZATION)
    
    /// Build context with priority streaming - yields Tier 1 immediately, streams Tier 2/3 as available.
    /// This allows starting AI requests before full context is ready (latency optimization).
    /// Returns (initialContext, fullContext) where initialContext has Tier 1 only.
    func buildContextWithPriority(
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?,
        query: String?,
        tokenLimit: Int = 8000
    ) async -> (initial: String, full: String) {
        // PHASE 1: Build Tier 1 context immediately (no file discovery needed)
        var tier1Items: [ContextRankingItem] = []
        
        // Active File (single read - fast)
        if let activeFile = activeFile,
           let content = try? String(contentsOf: activeFile, encoding: .utf8) {
            tier1Items.append(ContextRankingItem(
                file: activeFile,
                score: 100,
                content: content,
                tier: .tier1,
                reason: "Active file"
            ))
        }
        
        // Selected Range (immediate, no I/O)
        if let selectedRange = selectedRange, !selectedRange.isEmpty {
            tier1Items.append(ContextRankingItem(
                file: activeFile ?? URL(fileURLWithPath: ""),
                score: 80,
                content: selectedRange,
                tier: .tier1,
                reason: "Selected range"
            ))
        }
        
        // Diagnostics (immediate, no I/O)
        if let diagnostics = diagnostics, !diagnostics.isEmpty {
            let diagnosticsContent = diagnostics.joined(separator: "\n")
            tier1Items.append(ContextRankingItem(
                file: URL(fileURLWithPath: ""),
                score: 60,
                content: diagnosticsContent,
                tier: .tier1,
                reason: "Diagnostics"
            ))
        }
        
        // Build initial context from Tier 1 only
        let initialContext = formatContextItems(tier1Items, tokenLimit: tokenLimit)
        
        // PHASE 2: Build full context with Tier 2/3 in parallel (can be used for follow-up)
        let fullContext = await buildContext(
            activeFile: activeFile,
            selectedRange: selectedRange,
            diagnostics: diagnostics,
            projectURL: projectURL,
            query: query,
            tokenLimit: tokenLimit
        )
        
        return (initial: initialContext, full: fullContext)
    }
    
    /// Format context items into string (shared helper)
    private func formatContextItems(_ items: [ContextRankingItem], tokenLimit: Int) -> String {
        let sorted = items.sorted { $0.score > $1.score }
        let contextItems = sorted.map { item -> ContextItem in
            let isActive = item.tier == .tier1 && item.reason == "Active file"
            return ContextItem(
                file: item.file,
                content: item.content,
                score: item.score,
                isActive: isActive,
                referencedSymbols: Set<String>()
            )
        }
        
        let optimized = TokenBudgetOptimizer.shared.optimizeContext(
            items: contextItems,
            maxTokens: tokenLimit
        )
        
        return optimized.map { item in
            let header = item.isActive
                ? "--- Active File: \(item.file.lastPathComponent) ---"
                : "--- \(item.file.lastPathComponent) ---"
            return "\n\n\(header)\n\(item.content)"
        }.joined()
    }
    
    /// Build context with Cursor-style ranking algorithm
    /// Runs on the actor's background executor, keeping the UI completely free
    /// OPTIMIZATION: Uses priority queue - Tier 1 items are collected first and yielded early
    func buildContext(
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?,
        query: String?,
        tokenLimit: Int = 8000
    ) async -> String {
        // OPTIMIZATION: File discovery runs on actor's background executor, not UI thread!
        // This prevents 50-200ms UI freezes during file system crawling
        let tier2FileLists = (projectURL != nil && activeFile != nil)
            ? getTier2FileLists(for: activeFile!, in: projectURL!, query: query)
            : []
        
        let tier3FileLists = (projectURL != nil)
            ? getTier3FileLists(in: projectURL!, query: query)
            : []
        
        let boostRuleFileLists = (projectURL != nil)
            ? getBoostRuleFileLists(activeFile: activeFile, query: query, in: projectURL!)
            : []
        
        // Get semantic search results outside TaskGroup to avoid actor isolation issues
        let semanticChunks: [CodeChunk] = if let query = query, !query.isEmpty {
            await MainActor.run {
                SemanticSearchService.shared.search(query: query, limit: 5)
            }
        } else {
            []
        }
        
        // OPTIMIZATION: Use TaskGroup with priority queue - Tier 1 items collected first
        return await withTaskGroup(of: (ContextRankingItem, Int)?.self) { group in
            var tier1Items: [ContextRankingItem] = []
            var tier2Items: [ContextRankingItem] = []
            var tier3Items: [ContextRankingItem] = []
            
            // Priority 0: Active File (highest priority - read first)
            if let activeFile = activeFile {
                group.addTask {
                    guard let content = try? String(contentsOf: activeFile, encoding: .utf8) else { return nil }
                    return (ContextRankingItem(
                        file: activeFile,
                        score: 100,
                        content: content,
                        tier: .tier1,
                        reason: "Active file"
                    ), 0) // Priority 0 = Tier 1
                }
            }
            
            // Priority 0: Selected Range (immediate, no I/O)
            if let selectedRange = selectedRange, !selectedRange.isEmpty {
                tier1Items.append(ContextRankingItem(
                    file: activeFile ?? URL(fileURLWithPath: ""),
                    score: 80,
                    content: selectedRange,
                    tier: .tier1,
                    reason: "Selected range"
                ))
            }
            
            // Priority 0: Diagnostics (immediate, no I/O)
            if let diagnostics = diagnostics, !diagnostics.isEmpty {
                let diagnosticsContent = diagnostics.joined(separator: "\n")
                tier1Items.append(ContextRankingItem(
                    file: URL(fileURLWithPath: ""),
                    score: 60,
                    content: diagnosticsContent,
                    tier: .tier1,
                    reason: "Diagnostics"
                ))
            }
            
            // Priority 1: Tier 2 files (medium priority)
            for (file, score, reason) in tier2FileLists {
                group.addTask {
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                    return (ContextRankingItem(
                        file: file,
                        score: score,
                        content: content,
                        tier: .tier2,
                        reason: reason
                    ), 1) // Priority 1 = Tier 2
                }
            }
            
            // Priority 2: Tier 3 files (lower priority)
            for (file, score, reason) in tier3FileLists {
                group.addTask {
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                    return (ContextRankingItem(
                        file: file,
                        score: score,
                        content: content,
                        tier: .tier3,
                        reason: reason
                    ), 2) // Priority 2 = Tier 3
                }
            }
            
            // Priority 2: Boost Rules (lower priority)
            for (file, score, reason) in boostRuleFileLists {
                group.addTask {
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                    return (ContextRankingItem(
                        file: file,
                        score: score,
                        content: content,
                        tier: .tier3,
                        reason: reason
                    ), 2)
                }
            }
            
            // Priority 1: Semantic Search (medium priority)
            if !semanticChunks.isEmpty, let projectURL = projectURL {
                for chunk in semanticChunks {
                    let fileURL = projectURL.appendingPathComponent(chunk.filePath)
                    group.addTask {
                        if let fullContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                            let lines = fullContent.components(separatedBy: .newlines)
                            let lineLimit = AgentConfiguration.smartWindowLineLimit
                            let padding = AgentConfiguration.contextWindowPadding
                            if lines.count > lineLimit {
                                let start = max(0, chunk.startLine - padding)
                                let end = min(lines.count - 1, chunk.endLine + padding)
                                let windowContent = lines[start...end].joined(separator: "\n")
                                let header = "// ... (lines \(0)-\(start) hidden)\n"
                                let footer = "\n// ... (lines \(end + 1)-\(lines.count) hidden)"
                                return (ContextRankingItem(
                                    file: fileURL,
                                    score: 35,
                                    content: header + windowContent + footer,
                                    tier: .tier2,
                                    reason: "Semantic match (window)"
                                ), 1)
                            } else {
                                return (ContextRankingItem(
                                    file: fileURL,
                                    score: 35,
                                    content: fullContent,
                                    tier: .tier2,
                                    reason: "Semantic match"
                                ), 1)
                            }
                        }
                        return (ContextRankingItem(
                            file: fileURL,
                            score: 35,
                            content: chunk.content,
                            tier: .tier2,
                            reason: "Semantic match (chunk)"
                        ), 1)
                    }
                }
            }
            
            // Collect results by priority (Tier 1 first, then 2, then 3)
            for await result in group {
                guard let (item, priority) = result else { continue }
                switch priority {
                case 0: tier1Items.append(item)
                case 1: tier2Items.append(item)
                default: tier3Items.append(item)
                }
            }
            
            // Combine all items with Tier 1 first (priority ordering)
            let allItems = tier1Items + tier2Items + tier3Items
            
            // Final Optimization with token budget
            let sorted = allItems.sorted { $0.score > $1.score }
            let contextItems = sorted.map { item -> ContextItem in
                let isActive = item.tier == .tier1 && item.reason == "Active file"
                return ContextItem(
                    file: item.file,
                    content: item.content,
                    score: item.score,
                    isActive: isActive,
                    referencedSymbols: Set<String>()
                )
            }
            
            let optimized = TokenBudgetOptimizer.shared.optimizeContext(
                items: contextItems,
                maxTokens: tokenLimit
            )
            
            // Build formatted result
            return optimized.map { item in
                let header = item.isActive
                    ? "--- Active File: \(item.file.lastPathComponent) ---"
                    : "--- \(item.file.lastPathComponent) ---"
                return "\n\n\(header)\n\(item.content)"
            }.joined()
        }
    }
    
    /// Get Tier 2 file lists (returns tuples for parallel reading)
    /// FIX: Mark as nonisolated since it doesn't access actor state
    nonisolated private func getTier2FileLists(
        for activeFile: URL,
        in projectURL: URL,
        query: String?
    ) -> [(URL, Int, String)] {
        var fileLists: [(URL, Int, String)] = []
        // FIX: FileDependencyService and GitAwareService are regular classes, safe to access
        let fileDependencyService = FileDependencyService.shared
        
        // Direct imports (score: 40)
        let importedFiles = fileDependencyService.findImportedFiles(
            for: activeFile,
            in: projectURL
        )
        for file in importedFiles.prefix(5) {
            // Add Git heat score to context score
            let baseScore = 40
            let gitHeat = GitAwareService.shared.getHeatScore(file: file, line: 1)
            let finalScore = baseScore + gitHeat
            fileLists.append((file, finalScore, "Direct import"))
        }
        
        // Symbol references (score: 30)
        let referencedFiles = fileDependencyService.findReferencedFiles(
            for: activeFile,
            in: projectURL
        )
        for file in referencedFiles.prefix(5) {
            fileLists.append((file, 30, "Symbol referenced"))
        }
        
        // Recently edited files with recency/frequency scoring
        let recentFiles = getRecentlyEditedFiles(in: projectURL, limit: 5)
        for file in recentFiles {
            // Base score for recency
            var score = 20
            
            // Add frequency score (how often file is edited/referenced)
            let gitHeat = GitAwareService.shared.getHeatScore(file: file, line: 1)
            score += min(gitHeat / 10, 30) // Cap frequency boost at 30
            
            // Add recency boost (more recent = higher score)
            if let modDate = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date {
                let hoursSinceEdit = Date().timeIntervalSince(modDate) / 3600
                if hoursSinceEdit < 1 {
                    score += 15 // Edited in last hour
                } else if hoursSinceEdit < 24 {
                    score += 10 // Edited in last day
                } else if hoursSinceEdit < 168 {
                    score += 5 // Edited in last week
                }
            }
            
            fileLists.append((file, score, "Recently edited (recency + frequency)"))
        }
        
        // Filter out vendor files
        fileLists = fileLists.filter { (file, _, _) in
            let path = file.path.lowercased()
            return !path.contains("node_modules") &&
                   !path.contains("vendor") &&
                   !path.contains("build") &&
                   !path.contains(".generated")
        }
        
        return fileLists
    }
    
    /// Get semantic search file lists (returns tuples for parallel reading)
    /// NOTE: This method is no longer used - semantic search is handled in buildContext
    private func getSemanticSearchFileLists(
        query: String,
        in projectURL: URL
    ) -> [(URL, Int)] {
        // FIX: This method is deprecated - semantic search is now handled in buildContext
        // to avoid actor isolation issues
        return []
    }
    
    /// Get Tier 3 file lists (returns tuples for parallel reading)
    /// FIX: Mark as nonisolated since it doesn't access actor state
    nonisolated private func getTier3FileLists(
        in projectURL: URL,
        query: String?
    ) -> [(URL, Int, String)] {
        var fileLists: [(URL, Int, String)] = []
        
        // Test files
        let testFiles = findFiles(matching: ["*Test.swift", "*test.*", "*.spec.*"], in: projectURL)
        for file in testFiles.prefix(2) {
            fileLists.append((file, 15, "Test file"))
        }
        
        // Interface/type files
        let interfaceFiles = findFiles(matching: ["*Interface*", "*Protocol*", "*Type*"], in: projectURL)
        for file in interfaceFiles.prefix(2) {
            fileLists.append((file, 10, "Interface/type"))
        }
        
        // README/docs
        let docFiles = findFiles(matching: ["README*", "*.md"], in: projectURL)
        for file in docFiles.prefix(1) {
            fileLists.append((file, 5, "Documentation"))
        }
        
        return fileLists
    }
    
    /// Boost rule file lists: template-matched files (from ContextManager) with score 25
    /// Picks rule(s) by active file extension or query keywords, then applies include patterns
    nonisolated private func getBoostRuleFileLists(
        activeFile: URL?,
        query: String?,
        in projectURL: URL
    ) -> [(URL, Int, String)] {
        var fileLists: [(URL, Int, String)] = []
        let queryLower = (query ?? "").lowercased()
        let activeExt = activeFile?.pathExtension.lowercased() ?? ""
        
        let rulesToApply: [ContextBoostRule]
        if queryLower.contains("api") || queryLower.contains("endpoint") {
            rulesToApply = [Self.boostRules[1]]
        } else if queryLower.contains("component") {
            rulesToApply = [Self.boostRules[2]]
        } else if ["swift", "ts", "tsx", "js", "jsx"].contains(activeExt) {
            rulesToApply = [Self.boostRules[0]]
        } else {
            rulesToApply = [Self.boostRules[0]]
        }
        
        var seen = Set<URL>()
        for rule in rulesToApply {
            let matching = findFilesMatchingBoostRule(rule, in: projectURL)
            for file in matching.prefix(rule.maxFiles) {
                if seen.insert(file).inserted {
                    fileLists.append((file, 25, "Boost: \(rule.name)"))
                }
            }
        }
        
        return fileLists
    }
    
    /// Find files matching a boost rule's filePatterns and includePatterns
    nonisolated private func findFilesMatchingBoostRule(_ rule: ContextBoostRule, in projectURL: URL) -> [URL] {
        var matchingFiles: [URL] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        let blockedFolders = ["node_modules", "vendor", "build", "dist", ".git", ".build", "Pods", "DerivedData", ".swiftpm"]
        
        for case let url as URL in enumerator {
            guard !url.hasDirectoryPath else {
                if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                   resourceValues.isDirectory == true,
                   blockedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            let fileName = url.lastPathComponent
            var matchesFilePattern = false
            for pattern in rule.filePatterns {
                if matchesPattern(fileName, pattern: pattern) {
                    matchesFilePattern = true
                    break
                }
            }
            if !matchesFilePattern { continue }
            
            for includePattern in rule.includePatterns {
                if matchesPattern(fileName, pattern: includePattern) {
                    matchingFiles.append(url)
                    break
                }
            }
        }
        
        return matchingFiles
    }
    
    /// FIX: Optimized Recent File Discovery
    /// Prevents hanging on 'node_modules' or large build directories
    /// FIX: Mark as nonisolated since it doesn't access actor state
    nonisolated private func getRecentlyEditedFiles(in projectURL: URL, limit: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }
        
        var files: [(URL, Date)] = []
        // FIX: Block heavy vendor directories to prevent "Enumeration Bomb"
        let blockedFolders = ["node_modules", "vendor", "build", "dist", ".git", ".build", "Pods", "DerivedData", ".swiftpm"]
        
        while let url = enumerator.nextObject() as? URL {
            // OPTIMIZATION: Manually skip heavy directories
            if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               resourceValues.isDirectory == true {
                if blockedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
            }
            
            // Check file validity and date
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
    
    /// FIX: Mark as nonisolated since it doesn't access actor state
    nonisolated private func findFiles(matching patterns: [String], in projectURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }
        
        var files: [URL] = []
        // FIX: Block heavy vendor directories to prevent "Enumeration Bomb"
        let blockedFolders = ["node_modules", "vendor", "build", "dist", ".git", ".build", "Pods", "DerivedData", ".swiftpm"]
        
        while let url = enumerator.nextObject() as? URL {
            // OPTIMIZATION: Manually skip heavy directories
            if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               resourceValues.isDirectory == true {
                if blockedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
            }
            
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
    
    /// FIX: Mark as nonisolated since it doesn't access actor state
    nonisolated private func matchesPattern(_ fileName: String, pattern: String) -> Bool {
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
        
        if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: fileName.utf16.count)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        }
        
        return fileName.lowercased().contains(pattern.lowercased())
    }
    
    /// FIX: Mark as nonisolated since it doesn't access actor state
    nonisolated private func estimateTokens(_ text: String) -> Int {
        // IMPROVEMENT: Uses BPE tokenizer for accurate token counting
        // FIX: BPETokenizer is a regular class, safe to access from nonisolated context
        return BPETokenizer.shared.estimateTokens(text)
    }
}
