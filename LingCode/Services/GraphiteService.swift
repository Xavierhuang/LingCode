//
//  GraphiteService.swift
//  LingCode
//
//  Graphite integration for managing stacked pull requests
//  This addresses the "massive unreviewable PRs" complaint
//

import Foundation

/// Service for integrating with Graphite to manage stacked pull requests
/// Graphite helps break large AI-generated changes into smaller, reviewable PRs
class GraphiteService {
    static let shared = GraphiteService()
    
    private init() {}
    
    /// Check if Graphite CLI is installed
    func isGraphiteInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gt"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespaces).isEmpty
        } catch {
            return false
        }
    }
    
    /// Create a new branch for a change set
    func createBranch(name: String, baseBranch: String = "main", in directory: URL) -> Result<String, Error> {
        guard isGraphiteInstalled() else {
            return .failure(NSError(domain: "GraphiteService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Graphite CLI not installed. Install from https://graphite.dev"]))
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gt")
        process.arguments = ["branch", "create", name, "--base", baseBranch]
        process.currentDirectoryURL = directory
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return .success(output)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(NSError(domain: "GraphiteService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorOutput]))
            }
        } catch {
            return .failure(error)
        }
    }
    
    /// Create a stacked PR for a set of changes
    /// This breaks large changes into smaller, reviewable PRs
    func createStackedPR(
        changes: [CodeChange],
        baseBranch: String = "main",
        in directory: URL,
        maxFilesPerPR: Int = 5,
        maxLinesPerPR: Int = 200
    ) -> Result<[StackedPR], Error> {
        // Group changes into logical PRs
        let prGroups = groupChangesForStacking(
            changes: changes,
            maxFiles: maxFilesPerPR,
            maxLines: maxLinesPerPR
        )
        
        var stackedPRs: [StackedPR] = []
        var previousBranch = baseBranch
        
        for (index, group) in prGroups.enumerated() {
            let branchName = "ai-changes-\(index + 1)"
            
            // Create branch
            switch createBranch(name: branchName, baseBranch: previousBranch, in: directory) {
            case .success:
                // Apply changes to this branch
                if applyChangesToBranch(group, in: directory) {
                    // Commit changes
                    if commitChanges(group, branch: branchName, in: directory) {
                        let pr = StackedPR(
                            branch: branchName,
                            baseBranch: previousBranch,
                            changes: group,
                            prNumber: index + 1,
                            totalPRs: prGroups.count
                        )
                        stackedPRs.append(pr)
                        previousBranch = branchName
                    }
                }
            case .failure(let error):
                return .failure(error)
            }
        }
        
        return .success(stackedPRs)
    }
    
    /// Group changes into logical PRs based on size and dependencies
    private func groupChangesForStacking(
        changes: [CodeChange],
        maxFiles: Int,
        maxLines: Int
    ) -> [[CodeChange]] {
        var groups: [[CodeChange]] = []
        var currentGroup: [CodeChange] = []
        var currentLines = 0
        
        for change in changes {
            let changeLines = change.addedLines + change.removedLines
            
            // If adding this change would exceed limits, start a new group
            if currentGroup.count >= maxFiles || (currentLines + changeLines) > maxLines {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                    currentGroup = []
                    currentLines = 0
                }
            }
            
            currentGroup.append(change)
            currentLines += changeLines
        }
        
        // Add remaining changes
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
    
    /// Apply changes to current branch
    private func applyChangesToBranch(_ changes: [CodeChange], in directory: URL) -> Bool {
        let applyService = ApplyCodeService.shared
        
        for change in changes {
            let result = applyService.applyChange(change, requestedScope: "Graphite stack")
            if !result.success {
                return false
            }
        }
        
        return true
    }
    
    /// Commit changes with descriptive message
    private func commitChanges(_ changes: [CodeChange], branch: String, in directory: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        
        // Stage all changes
        for change in changes {
            let addProcess = Process()
            addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            addProcess.arguments = ["add", change.filePath]
            addProcess.currentDirectoryURL = directory
            try? addProcess.run()
            addProcess.waitUntilExit()
        }
        
        // Create commit message
        let fileCount = changes.count
        let totalLines = changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
        let commitMessage = """
        AI-generated changes (\(fileCount) files, \(totalLines) lines)
        
        Files changed:
        \(changes.map { "- \($0.fileName)" }.joined(separator: "\n"))
        """
        
        process.arguments = ["commit", "-m", commitMessage]
        process.currentDirectoryURL = directory
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Push stacked PRs to remote
    func pushStackedPRs(_ prs: [StackedPR], in directory: URL) -> Result<[String], Error> {
        guard isGraphiteInstalled() else {
            return .failure(NSError(domain: "GraphiteService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Graphite CLI not installed"]))
        }
        
        var pushedBranches: [String] = []
        
        for pr in prs {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gt")
            process.arguments = ["repo", "create-pr", pr.branch]
            process.currentDirectoryURL = directory
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    pushedBranches.append(pr.branch)
                }
            } catch {
                return .failure(error)
            }
        }
        
        return .success(pushedBranches)
    }
    
    /// Get status of stacked PRs
    func getStackStatus(in directory: URL) -> StackStatus? {
        guard isGraphiteInstalled() else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gt")
        process.arguments = ["stack", "list"]
        process.currentDirectoryURL = directory
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse Graphite output
            return parseStackStatus(output)
        } catch {
            return nil
        }
    }
    
    private func parseStackStatus(_ output: String) -> StackStatus? {
        // Parse Graphite stack list output
        // This is a simplified parser - real implementation would be more robust
        let lines = output.components(separatedBy: .newlines)
        var branches: [String] = []
        
        for line in lines {
            if line.contains("branch") || line.contains("PR") {
                // Extract branch name from line
                let components = line.components(separatedBy: .whitespaces)
                if let branch = components.first(where: { $0.contains("/") || $0.hasPrefix("ai-") }) {
                    branches.append(branch)
                }
            }
        }
        
        return StackStatus(branches: branches, totalPRs: branches.count)
    }
}

// MARK: - Models

struct StackedPR {
    let branch: String
    let baseBranch: String
    let changes: [CodeChange]
    let prNumber: Int
    let totalPRs: Int
    
    var description: String {
        "PR \(prNumber)/\(totalPRs): \(changes.count) files, \(totalLines) lines"
    }
    
    var totalLines: Int {
        changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
    }
}

struct StackStatus {
    let branches: [String]
    let totalPRs: Int
}

