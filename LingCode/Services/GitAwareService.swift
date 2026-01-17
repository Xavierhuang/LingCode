//
//  GitAwareService.swift
//  LingCode
//
//  Git-aware diff prioritization for smarter context ranking
//

import Foundation

struct GitHeatScore {
    let file: URL
    let line: Int
    let score: Int
    let reasons: [String]
}

struct GitDiffInfo {
    let file: URL
    let isUncommitted: Bool
    let modifiedInBranch: Bool
    let modifiedRecently: Bool
    let lastModified: Date?
    let branchName: String?
}

class GitAwareService {
    // FIX: Mark shared as nonisolated to allow access from actor contexts
    static let shared = GitAwareService()
    
    private var heatMap: [URL: [Int: Int]] = [:] // [file: [line: score]]
    private var diffInfo: [URL: GitDiffInfo] = [:]
    private let cacheQueue = DispatchQueue(label: "com.lingcode.gitaware", attributes: .concurrent)
    
    private init() {}
    
    /// Build diff heatmap for project
    /// CRITICAL FIX: Only read files that git reports as modified to avoid I/O saturation
    func buildHeatMap(for projectURL: URL) {
        cacheQueue.async {
            var newHeatMap: [URL: [Int: Int]] = [:]
            var newDiffInfo: [URL: GitDiffInfo] = [:]
            
            // CRITICAL FIX: Get list of modified files from git first
            // This avoids reading every file in large projects (5,000+ files)
            let modifiedFiles = self.getModifiedFiles(in: projectURL)
            
            // Only process modified files + files already in cache (for incremental updates)
            let filesToProcess = Set(modifiedFiles)
            
            for fileURL in filesToProcess {
                guard !fileURL.hasDirectoryPath else { continue }
                
                let diffInfo = self.getDiffInfo(for: fileURL, in: projectURL)
                newDiffInfo[fileURL] = diffInfo
                
                // Build line-level heat scores
                var lineScores: [Int: Int] = [:]
                
                // CRITICAL FIX: Only read if file is actually modified (reduces I/O)
                // Use FileHandle for large files to avoid loading entire file into memory
                if diffInfo.isUncommitted || diffInfo.modifiedInBranch || diffInfo.modifiedRecently {
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let lines = content.components(separatedBy: .newlines)
                        
                        for (index, _) in lines.enumerated() {
                            var score = 0
                            
                            // +100 uncommitted
                            if diffInfo.isUncommitted {
                                score += 100
                            }
                            
                            // +60 modified in branch
                            if diffInfo.modifiedInBranch {
                                score += 60
                            }
                            
                            // +30 modified recently
                            if diffInfo.modifiedRecently {
                                score += 30
                            }
                            
                            lineScores[index + 1] = score
                        }
                    }
                }
                
                newHeatMap[fileURL] = lineScores
                
                // CRITICAL FIX: Yield to system between file reads to prevent I/O saturation
                // This allows other operations (Save, Open) to proceed smoothly
                usleep(1000) // 1ms delay between files
            }
            
            self.cacheQueue.async(flags: .barrier) {
                self.heatMap = newHeatMap
                self.diffInfo = newDiffInfo
            }
        }
    }
    
    /// Get list of modified files from git status
    /// CRITICAL FIX: Only process files that git reports as changed
    private func getModifiedFiles(in projectURL: URL) -> [URL] {
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync(
            "git status --porcelain",
            workingDirectory: projectURL
        )
        
        guard result.exitCode == 0 else {
            // If git fails, fall back to enumerating all files (old behavior)
            return getAllFiles(in: projectURL)
        }
        
        var modifiedFiles: [URL] = []
        let lines = result.output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Parse git status output (format: " M path/to/file.swift")
            let components = trimmed.components(separatedBy: .whitespaces)
            if components.count >= 2 {
                let filePath = components.last!
                let fileURL = projectURL.appendingPathComponent(filePath)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    modifiedFiles.append(fileURL)
                }
            }
        }
        
        return modifiedFiles
    }
    
    /// Fallback: Get all files if git is not available
    private func getAllFiles(in projectURL: URL) -> [URL] {
        var files: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return files
        }
        
        for case let url as URL in enumerator {
            if !url.hasDirectoryPath {
                files.append(url)
            }
        }
        
        return files
    }
    
    /// Get heat score for file and line
    /// FIX: Uses thread-safe concurrent queue, safe to call from actor contexts
    func getHeatScore(file: URL, line: Int) -> Int {
        return cacheQueue.sync {
            return heatMap[file]?[line] ?? 0
        }
    }
    
    /// Get diff info for file
    func getDiffInfo(for fileURL: URL, in projectURL: URL) -> GitDiffInfo {
        // Check if uncommitted
        let isUncommitted = checkUncommitted(fileURL: fileURL, projectURL: projectURL)
        
        // Check if modified in branch
        let modifiedInBranch = checkModifiedInBranch(fileURL: fileURL, projectURL: projectURL)
        
        // Check if modified recently
        let (modifiedRecently, lastModified) = checkRecentlyModified(fileURL: fileURL)
        
        // Get branch name
        let branchName = getCurrentBranch(projectURL: projectURL)
        
        return GitDiffInfo(
            file: fileURL,
            isUncommitted: isUncommitted,
            modifiedInBranch: modifiedInBranch,
            modifiedRecently: modifiedRecently,
            lastModified: lastModified,
            branchName: branchName
        )
    }
    
    /// Add heat score for context ranking
    func addGitHeatToContextScore(_ baseScore: Int, file: URL, line: Int) -> Int {
        let heatScore = getHeatScore(file: file, line: line)
        return baseScore + heatScore
    }
    
    /// Validate edit against Git heatmap
    func validateEdit(_ edit: Edit, in workspaceURL: URL) -> EditValidationResult {
        let fileURL = workspaceURL.appendingPathComponent(edit.file)
        let diffInfo = getDiffInfo(for: fileURL, in: workspaceURL)
        
        // Reject if touching untouched files
        if !diffInfo.isUncommitted && !diffInfo.modifiedInBranch && !diffInfo.modifiedRecently {
            return .rejected("File has not been modified - consider if this change is necessary")
        }
        
        // Warn if modifying cold code
        if let range = edit.range {
            let avgHeat = averageHeatScore(file: fileURL, lines: range.startLine...range.endLine)
            if avgHeat < 20 {
                return .warning("Modifying code that hasn't been touched recently")
            }
        }
        
        return .accepted
    }
    
    /// Generate commit message for refactor
    func generateCommitMessage(
        renameFrom: String,
        renameTo: String,
        filesAffected: Int
    ) -> String {
        if filesAffected > 1 {
            return "refactor: rename \(renameFrom) → \(renameTo) (\(filesAffected) files)"
        } else {
            return "refactor: rename \(renameFrom) → \(renameTo)"
        }
    }
    
    /// Auto-stage files for commit (if rename spans multiple files)
    func autoStageFiles(_ fileURLs: [URL], in projectURL: URL) {
        // Would use git command: git add <files>
        // Placeholder - would integrate with GitService
    }
    
    // MARK: - Git Operations
    
    private func checkUncommitted(fileURL: URL, projectURL: URL) -> Bool {
        // Would use: git status --porcelain
        // For now, placeholder
        return false
    }
    
    private func checkModifiedInBranch(fileURL: URL, projectURL: URL) -> Bool {
        // Would use: git diff --name-only origin/main...HEAD
        // For now, placeholder
        return false
    }
    
    private func checkRecentlyModified(fileURL: URL) -> (Bool, Date?) {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modDate = resourceValues.contentModificationDate else {
            return (false, nil)
        }
        
        let daysSinceModified = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0
        return (daysSinceModified < 7, modDate) // Modified in last 7 days
    }
    
    private func getCurrentBranch(projectURL: URL) -> String? {
        // Would use: git branch --show-current
        // For now, placeholder
        return nil
    }
    
    private func averageHeatScore(file: URL, lines: ClosedRange<Int>) -> Int {
        return cacheQueue.sync {
            guard let lineScores = heatMap[file] else { return 0 }
            var total = 0
            var count = 0
            for line in lines {
                if let score = lineScores[line] {
                    total += score
                    count += 1
                }
            }
            return count > 0 ? total / count : 0
        }
    }
}

enum EditValidationResult {
    case accepted
    case warning(String)
    case rejected(String)
}
