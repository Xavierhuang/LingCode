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
    static let shared = GitAwareService()
    
    private var heatMap: [URL: [Int: Int]] = [:] // [file: [line: score]]
    private var diffInfo: [URL: GitDiffInfo] = [:]
    private let cacheQueue = DispatchQueue(label: "com.lingcode.gitaware", attributes: .concurrent)
    
    private init() {}
    
    /// Build diff heatmap for project
    func buildHeatMap(for projectURL: URL) {
        cacheQueue.async {
            var newHeatMap: [URL: [Int: Int]] = [:]
            var newDiffInfo: [URL: GitDiffInfo] = [:]
            
            guard let enumerator = FileManager.default.enumerator(
                at: projectURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return
            }
            
            for case let fileURL as URL in enumerator {
                guard !fileURL.hasDirectoryPath else { continue }
                
                let diffInfo = self.getDiffInfo(for: fileURL, in: projectURL)
                newDiffInfo[fileURL] = diffInfo
                
                // Build line-level heat scores
                var lineScores: [Int: Int] = [:]
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines)
                    
                    for (index, _) in lines.enumerated() {
                        var score = 0
                        var reasons: [String] = []
                        
                        // +100 uncommitted
                        if diffInfo.isUncommitted {
                            score += 100
                            reasons.append("uncommitted")
                        }
                        
                        // +60 modified in branch
                        if diffInfo.modifiedInBranch {
                            score += 60
                            reasons.append("modified in branch")
                        }
                        
                        // +30 modified recently
                        if diffInfo.modifiedRecently {
                            score += 30
                            reasons.append("modified recently")
                        }
                        
                        lineScores[index + 1] = score
                    }
                }
                
                newHeatMap[fileURL] = lineScores
            }
            
            self.cacheQueue.async(flags: .barrier) {
                self.heatMap = newHeatMap
                self.diffInfo = newDiffInfo
            }
        }
    }
    
    /// Get heat score for file and line
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
