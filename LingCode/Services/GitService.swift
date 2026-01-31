//
//  GitService.swift
//  LingCode
//
//  Git integration service with commit/push/pull support
//

import Foundation
import Combine

enum GitStatus: String {
    case clean = "clean"
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case untracked = "?"
    case renamed = "R"
    case copied = "C"
    case staged = "staged"
}

struct GitFileStatus: Identifiable {
    let id = UUID()
    let path: String
    let status: GitStatus
    let isStaged: Bool
}

struct GitBranch: Identifiable {
    let id = UUID()
    let name: String
    let isCurrent: Bool
    let isRemote: Bool
}

struct GitCommit: Identifiable {
    let id: String  // commit hash
    let shortHash: String
    let message: String
    let author: String
    let date: Date
}

struct GitResult {
    let success: Bool
    let output: String
    let error: String?
}

class GitService: ObservableObject {
    static let shared = GitService()
    
    @Published var currentBranch: String = ""
    @Published var fileStatuses: [GitFileStatus] = []
    @Published var branches: [GitBranch] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var hasUncommittedChanges: Bool = false
    @Published var aheadBehind: (ahead: Int, behind: Int) = (0, 0)
    
    private var repositoryURL: URL?
    
    private init() {}
    
    // MARK: - Repository Setup
    
    func setRepository(_ url: URL) {
        guard isGitRepository(url) else { return }
        repositoryURL = url
        refreshStatus()
    }
    
    func refreshStatus() {
        guard let url = repositoryURL else { return }
        
        Task { @MainActor in
            isLoading = true
            
            // Get current branch
            currentBranch = await getCurrentBranch(in: url) ?? "main"
            
            // Get file statuses
            fileStatuses = await getStatusAsync(for: url)
            hasUncommittedChanges = !fileStatuses.isEmpty
            
            // Get branches
            branches = await getBranches(in: url)
            
            // Get ahead/behind count
            aheadBehind = await getAheadBehind(in: url)
            
            isLoading = false
        }
    }
    
    // MARK: - Status
    
    func getStatus(for directory: URL) -> [GitFileStatus] {
        let result = runGit(["status", "--porcelain", "-u"], in: directory)
        return parseGitStatus(result.output)
    }
    
    func getStatusAsync(for directory: URL) async -> [GitFileStatus] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.getStatus(for: directory)
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Diff
    
    func getDiff(for file: URL) -> String? {
        let result = runGit(["diff", file.path], in: file.deletingLastPathComponent())
        return result.success ? result.output : nil
    }
    
    func getStagedDiff(in directory: URL) -> String? {
        let result = runGit(["diff", "--cached"], in: directory)
        return result.success ? result.output : nil
    }
    
    // MARK: - Staging
    
    func stage(files: [String], in directory: URL) -> GitResult {
        return runGit(["add"] + files, in: directory)
    }
    
    func stageAll(in directory: URL) -> GitResult {
        return runGit(["add", "-A"], in: directory)
    }
    
    func unstage(files: [String], in directory: URL) -> GitResult {
        return runGit(["restore", "--staged"] + files, in: directory)
    }
    
    func unstageAll(in directory: URL) -> GitResult {
        return runGit(["restore", "--staged", "."], in: directory)
    }
    
    // MARK: - Commit
    
    func commit(message: String, in directory: URL) -> GitResult {
        let result = runGit(["commit", "-m", message], in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    func amendCommit(message: String?, in directory: URL) -> GitResult {
        var args = ["commit", "--amend"]
        if let msg = message {
            args.append(contentsOf: ["-m", msg])
        } else {
            args.append("--no-edit")
        }
        let result = runGit(args, in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    // MARK: - Push/Pull
    
    func push(in directory: URL, setUpstream: Bool = false) -> GitResult {
        var args = ["push"]
        if setUpstream {
            args.append(contentsOf: ["-u", "origin", currentBranch])
        }
        let result = runGit(args, in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    func pull(in directory: URL, rebase: Bool = false) -> GitResult {
        var args = ["pull"]
        if rebase {
            args.append("--rebase")
        }
        let result = runGit(args, in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    func fetch(in directory: URL) -> GitResult {
        let result = runGit(["fetch", "--all", "--prune"], in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    // MARK: - Branches
    
    func getBranches(in directory: URL) async -> [GitBranch] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runGit(["branch", "-a"], in: directory)
                var branches: [GitBranch] = []
                
                for line in result.output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    
                    let isCurrent = trimmed.hasPrefix("*")
                    let name = trimmed.replacingOccurrences(of: "* ", with: "")
                                     .replacingOccurrences(of: "remotes/", with: "")
                    let isRemote = line.contains("remotes/")
                    
                    // Skip HEAD pointer
                    if name.contains("HEAD ->") { continue }
                    
                    branches.append(GitBranch(name: name, isCurrent: isCurrent, isRemote: isRemote))
                }
                
                continuation.resume(returning: branches)
            }
        }
    }
    
    func createBranch(name: String, in directory: URL, checkout: Bool = true) -> GitResult {
        if checkout {
            return runGit(["checkout", "-b", name], in: directory)
        } else {
            return runGit(["branch", name], in: directory)
        }
    }
    
    func checkoutBranch(name: String, in directory: URL) -> GitResult {
        let result = runGit(["checkout", name], in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    func deleteBranch(name: String, in directory: URL, force: Bool = false) -> GitResult {
        let flag = force ? "-D" : "-d"
        return runGit(["branch", flag, name], in: directory)
    }
    
    func mergeBranch(name: String, in directory: URL) -> GitResult {
        let result = runGit(["merge", name], in: directory)
        if result.success {
            refreshStatus()
        }
        return result
    }
    
    // MARK: - Log
    
    func getLog(in directory: URL, limit: Int = 50) -> [GitCommit] {
        let format = "%H|%h|%s|%an|%at"
        let result = runGit(["log", "--pretty=format:\(format)", "-\(limit)"], in: directory)
        
        var commits: [GitCommit] = []
        for line in result.output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 5 else { continue }
            
            let timestamp = TimeInterval(parts[4]) ?? 0
            commits.append(GitCommit(
                id: parts[0],
                shortHash: parts[1],
                message: parts[2],
                author: parts[3],
                date: Date(timeIntervalSince1970: timestamp)
            ))
        }
        
        return commits
    }
    
    // MARK: - Stash
    
    func stash(in directory: URL, message: String? = nil) -> GitResult {
        var args = ["stash", "push"]
        if let msg = message {
            args.append(contentsOf: ["-m", msg])
        }
        return runGit(args, in: directory)
    }
    
    func stashPop(in directory: URL) -> GitResult {
        return runGit(["stash", "pop"], in: directory)
    }
    
    func stashList(in directory: URL) -> [String] {
        let result = runGit(["stash", "list"], in: directory)
        return result.output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
    
    // MARK: - Discard Changes
    
    func discardChanges(for files: [String], in directory: URL) -> GitResult {
        return runGit(["checkout", "--"] + files, in: directory)
    }
    
    func discardAllChanges(in directory: URL) -> GitResult {
        return runGit(["checkout", "--", "."], in: directory)
    }
    
    // MARK: - Helpers
    
    func isGitRepository(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let gitDir = url.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    func getCurrentBranch(in directory: URL) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
                let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: branch.isEmpty ? nil : branch)
            }
        }
    }
    
    func getAheadBehind(in directory: URL) async -> (ahead: Int, behind: Int) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runGit(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], in: directory)
                let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces)
                
                if parts.count >= 2 {
                    let behind = Int(parts[0]) ?? 0
                    let ahead = Int(parts[1]) ?? 0
                    continuation.resume(returning: (ahead, behind))
                } else {
                    continuation.resume(returning: (0, 0))
                }
            }
        }
    }
    
    // MARK: - Process Execution
    
    private func runGit(_ arguments: [String], in directory: URL) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8)
            
            return GitResult(
                success: process.terminationStatus == 0,
                output: output,
                error: error?.isEmpty == true ? nil : error
            )
        } catch {
            return GitResult(success: false, output: "", error: error.localizedDescription)
        }
    }
    
    private func parseGitStatus(_ output: String) -> [GitFileStatus] {
        var results: [GitFileStatus] = []
        
        for line in output.components(separatedBy: .newlines) {
            guard line.count >= 3 else { continue }
            
            let index = line.index(line.startIndex, offsetBy: 2)
            let statusCode = String(line[..<index])
            let path = String(line[index...]).trimmingCharacters(in: .whitespaces)
            
            // First character is index status, second is worktree status
            let indexStatus = statusCode.first ?? " "
            let worktreeStatus = statusCode.last ?? " "
            
            let status: GitStatus
            let isStaged: Bool
            
            if statusCode.hasPrefix("??") {
                status = .untracked
                isStaged = false
            } else if statusCode.hasPrefix("A") {
                status = .added
                isStaged = true
            } else if indexStatus == "D" || worktreeStatus == "D" {
                status = .deleted
                isStaged = indexStatus == "D"
            } else if indexStatus == "M" || worktreeStatus == "M" {
                status = .modified
                isStaged = indexStatus == "M"
            } else if statusCode.hasPrefix("R") {
                status = .renamed
                isStaged = true
            } else {
                status = .clean
                isStaged = false
            }
            
            results.append(GitFileStatus(path: path, status: status, isStaged: isStaged))
        }
        
        return results
    }
}








