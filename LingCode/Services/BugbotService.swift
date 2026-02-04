//
//  BugbotService.swift
//  LingCode
//
//  AI-powered PR review and auto-fix (like Cursor's Bugbot)
//  Reviews pull requests, identifies issues, and proposes fixes
//

import Foundation
import Combine

// MARK: - PR Review Types

struct PRInfo: Identifiable {
    let id: Int
    let title: String
    let body: String?
    let author: String
    let branch: String
    let baseBranch: String
    let url: URL
    let files: [PRFile]
    let commits: [PRCommit]
    let createdAt: Date
}

struct PRFile {
    let filename: String
    let status: FileStatus
    let additions: Int
    let deletions: Int
    let patch: String?
    
    enum FileStatus: String {
        case added, modified, removed, renamed
    }
}

struct PRCommit {
    let sha: String
    let message: String
    let author: String
    let date: Date
}

// MARK: - Review Results

struct PRReview: Identifiable {
    let id = UUID()
    let prId: Int
    let timestamp: Date
    let summary: String
    let issues: [PRIssue]
    let suggestions: [PRSuggestion]
    let overallScore: Int  // 0-100
    let autoFixable: Int   // Count of auto-fixable issues
}

struct PRIssue: Identifiable {
    let id = UUID()
    let severity: IssueSeverity
    let category: IssueCategory
    let file: String
    let line: Int?
    let description: String
    let suggestion: String?
    let canAutoFix: Bool
    
    enum IssueSeverity: String, CaseIterable {
        case critical = "Critical"
        case warning = "Warning"
        case info = "Info"
        
        var icon: String {
            switch self {
            case .critical: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    enum IssueCategory: String, CaseIterable {
        case bug = "Bug"
        case security = "Security"
        case performance = "Performance"
        case style = "Style"
        case logic = "Logic"
        case testing = "Testing"
        case documentation = "Documentation"
    }
}

struct PRSuggestion: Identifiable {
    let id = UUID()
    let file: String
    let lineStart: Int
    let lineEnd: Int
    let originalCode: String
    let suggestedCode: String
    let explanation: String
    let isAutoApplied: Bool
}

// MARK: - Bugbot Service

class BugbotService: ObservableObject {
    static let shared = BugbotService()
    
    @Published var isReviewing: Bool = false
    @Published var currentReview: PRReview?
    @Published var reviewHistory: [PRReview] = []
    @Published var lastError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - PR Review
    
    /// Review a PR by number (requires git remote to be GitHub)
    func reviewPR(number: Int, projectURL: URL) async throws -> PRReview {
        await MainActor.run { isReviewing = true }
        defer { Task { @MainActor in isReviewing = false } }
        
        // Get PR info from GitHub
        let prInfo = try await fetchPRInfo(number: number, projectURL: projectURL)
        
        // Analyze the PR
        let review = try await analyzePR(prInfo)
        
        await MainActor.run {
            currentReview = review
            reviewHistory.insert(review, at: 0)
            if reviewHistory.count > 20 {
                reviewHistory = Array(reviewHistory.prefix(20))
            }
        }
        
        return review
    }
    
    /// Review current branch changes (local review)
    func reviewCurrentBranch(projectURL: URL) async throws -> PRReview {
        await MainActor.run { isReviewing = true }
        defer { Task { @MainActor in isReviewing = false } }
        
        // Get diff from current branch
        let diff = try await getGitDiff(projectURL: projectURL)
        let files = parseDiffToFiles(diff)
        
        // Create pseudo-PR info
        let prInfo = PRInfo(
            id: 0,
            title: "Local Changes Review",
            body: nil,
            author: "local",
            branch: try await getCurrentBranch(projectURL: projectURL),
            baseBranch: "main",
            url: projectURL,
            files: files,
            commits: [],
            createdAt: Date()
        )
        
        let review = try await analyzePR(prInfo)
        
        await MainActor.run {
            currentReview = review
        }
        
        return review
    }
    
    // MARK: - Analysis
    
    private func analyzePR(_ pr: PRInfo) async throws -> PRReview {
        var allIssues: [PRIssue] = []
        var allSuggestions: [PRSuggestion] = []
        
        // Analyze each file
        for file in pr.files where file.patch != nil {
            let (issues, suggestions) = try await analyzeFile(file, in: pr)
            allIssues.append(contentsOf: issues)
            allSuggestions.append(contentsOf: suggestions)
        }
        
        // Generate summary
        let summary = generateSummary(pr: pr, issues: allIssues)
        
        // Calculate score
        let score = calculateScore(issues: allIssues)
        
        // Count auto-fixable
        let autoFixable = allIssues.filter { $0.canAutoFix }.count
        
        return PRReview(
            prId: pr.id,
            timestamp: Date(),
            summary: summary,
            issues: allIssues,
            suggestions: allSuggestions,
            overallScore: score,
            autoFixable: autoFixable
        )
    }
    
    private func analyzeFile(_ file: PRFile, in pr: PRInfo) async throws -> ([PRIssue], [PRSuggestion]) {
        guard let patch = file.patch else { return ([], []) }
        
        let prompt = """
        Review this code change and identify issues:
        
        File: \(file.filename)
        Status: \(file.status.rawValue)
        
        Diff:
        ```
        \(patch)
        ```
        
        Analyze for:
        1. Bugs and logic errors
        2. Security vulnerabilities
        3. Performance issues
        4. Style/convention violations
        5. Missing tests or documentation
        
        For each issue found, provide:
        - Severity (critical/warning/info)
        - Category (bug/security/performance/style/logic/testing/documentation)
        - Line number if applicable
        - Description
        - Suggestion to fix
        - Whether it can be auto-fixed (true/false)
        
        Format as JSON array:
        [{"severity": "warning", "category": "bug", "line": 42, "description": "...", "suggestion": "...", "canAutoFix": true}]
        
        If no issues, return empty array: []
        """
        
        let response = try await callAI(prompt: prompt)
        let (issues, suggestions) = parseAnalysisResponse(response, file: file.filename)
        
        return (issues, suggestions)
    }
    
    private func parseAnalysisResponse(_ response: String, file: String) -> ([PRIssue], [PRSuggestion]) {
        var issues: [PRIssue] = []
        var suggestions: [PRSuggestion] = []
        
        // Try to extract JSON from response
        if let jsonStart = response.firstIndex(of: "["),
           let jsonEnd = response.lastIndex(of: "]") {
            let jsonString = String(response[jsonStart...jsonEnd])
            
            if let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                
                for item in parsed {
                    let severityStr = item["severity"] as? String ?? "info"
                    let categoryStr = item["category"] as? String ?? "style"
                    let severity = PRIssue.IssueSeverity(rawValue: severityStr.capitalized) ?? .info
                    let category = PRIssue.IssueCategory(rawValue: categoryStr.capitalized) ?? .style
                    
                    let issue = PRIssue(
                        severity: severity,
                        category: category,
                        file: file,
                        line: item["line"] as? Int,
                        description: item["description"] as? String ?? "",
                        suggestion: item["suggestion"] as? String,
                        canAutoFix: item["canAutoFix"] as? Bool ?? false
                    )
                    issues.append(issue)
                }
            }
        }
        
        return (issues, suggestions)
    }
    
    private func generateSummary(pr: PRInfo, issues: [PRIssue]) -> String {
        let criticalCount = issues.filter { $0.severity == .critical }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        let infoCount = issues.filter { $0.severity == .info }.count
        
        var summary = "Reviewed \(pr.files.count) file(s) with \(pr.files.reduce(0) { $0 + $1.additions }) additions and \(pr.files.reduce(0) { $0 + $1.deletions }) deletions.\n\n"
        
        if issues.isEmpty {
            summary += "No issues found. Code looks good!"
        } else {
            summary += "Found \(issues.count) issue(s):\n"
            if criticalCount > 0 { summary += "- \(criticalCount) critical\n" }
            if warningCount > 0 { summary += "- \(warningCount) warning(s)\n" }
            if infoCount > 0 { summary += "- \(infoCount) info\n" }
            
            // Group by category
            let byCategory = Dictionary(grouping: issues) { $0.category }
            summary += "\nBy category:\n"
            for (category, categoryIssues) in byCategory.sorted(by: { $0.value.count > $1.value.count }) {
                summary += "- \(category.rawValue): \(categoryIssues.count)\n"
            }
        }
        
        return summary
    }
    
    private func calculateScore(issues: [PRIssue]) -> Int {
        var score = 100
        
        for issue in issues {
            switch issue.severity {
            case .critical: score -= 20
            case .warning: score -= 5
            case .info: score -= 1
            }
        }
        
        return max(0, score)
    }
    
    // MARK: - Auto-Fix
    
    /// Apply auto-fixes for all fixable issues
    func applyAutoFixes(for review: PRReview, projectURL: URL) async throws -> Int {
        var fixCount = 0
        
        let fixableIssues = review.issues.filter { $0.canAutoFix && $0.suggestion != nil }
        
        for issue in fixableIssues {
            do {
                try await applyFix(issue, projectURL: projectURL)
                fixCount += 1
            } catch {
                print("Bugbot: Failed to apply fix for \(issue.file): \(error)")
            }
        }
        
        return fixCount
    }
    
    private func applyFix(_ issue: PRIssue, projectURL: URL) async throws {
        guard let suggestion = issue.suggestion else { return }
        
        let fileURL = projectURL.appendingPathComponent(issue.file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        // Read current file
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        
        // Apply fix if we have a line number
        if let line = issue.line, line > 0 && line <= lines.count {
            // Ask AI for the specific fix
            let prompt = """
            Fix this issue in the code:
            
            Issue: \(issue.description)
            Suggestion: \(suggestion)
            
            Current line \(line):
            ```
            \(lines[line - 1])
            ```
            
            Provide ONLY the fixed line, nothing else.
            """
            
            let fixedLine = try await callAI(prompt: prompt)
            lines[line - 1] = fixedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            
            content = lines.joined(separator: "\n")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Git Operations
    
    private func fetchPRInfo(number: Int, projectURL: URL) async throws -> PRInfo {
        // Use gh CLI to get PR info
        let ghOutput = try await runCommand("gh", args: ["pr", "view", String(number), "--json", "title,body,author,headRefName,baseRefName,url,files,commits"], at: projectURL)
        
        guard let data = ghOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BugbotError.failedToFetchPR
        }
        
        let title = json["title"] as? String ?? ""
        let body = json["body"] as? String
        let author = (json["author"] as? [String: Any])?["login"] as? String ?? ""
        let branch = json["headRefName"] as? String ?? ""
        let baseBranch = json["baseRefName"] as? String ?? "main"
        let urlString = json["url"] as? String ?? ""
        
        var files: [PRFile] = []
        if let filesJson = json["files"] as? [[String: Any]] {
            files = filesJson.map { fileJson in
                PRFile(
                    filename: fileJson["path"] as? String ?? "",
                    status: PRFile.FileStatus(rawValue: fileJson["status"] as? String ?? "modified") ?? .modified,
                    additions: fileJson["additions"] as? Int ?? 0,
                    deletions: fileJson["deletions"] as? Int ?? 0,
                    patch: fileJson["patch"] as? String
                )
            }
        }
        
        // Get the actual diff
        let diff = try await runCommand("gh", args: ["pr", "diff", String(number)], at: projectURL)
        let patchedFiles = parseDiffToFiles(diff)
        
        // Merge patch data
        files = files.map { file in
            if let patchedFile = patchedFiles.first(where: { $0.filename == file.filename }) {
                return PRFile(
                    filename: file.filename,
                    status: file.status,
                    additions: file.additions,
                    deletions: file.deletions,
                    patch: patchedFile.patch
                )
            }
            return file
        }
        
        return PRInfo(
            id: number,
            title: title,
            body: body,
            author: author,
            branch: branch,
            baseBranch: baseBranch,
            url: URL(string: urlString) ?? projectURL,
            files: files,
            commits: [],
            createdAt: Date()
        )
    }
    
    private func getGitDiff(projectURL: URL) async throws -> String {
        return try await runCommand("git", args: ["diff", "HEAD"], at: projectURL)
    }
    
    private func getCurrentBranch(projectURL: URL) async throws -> String {
        return try await runCommand("git", args: ["branch", "--show-current"], at: projectURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseDiffToFiles(_ diff: String) -> [PRFile] {
        var files: [PRFile] = []
        var currentFile: String?
        var currentPatch = ""
        var additions = 0
        var deletions = 0
        
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git") {
                // Save previous file
                if let file = currentFile {
                    files.append(PRFile(
                        filename: file,
                        status: .modified,
                        additions: additions,
                        deletions: deletions,
                        patch: currentPatch
                    ))
                }
                
                // Extract filename
                if let match = line.range(of: "b/", options: .backwards) {
                    currentFile = String(line[match.upperBound...])
                }
                currentPatch = ""
                additions = 0
                deletions = 0
            } else if currentFile != nil {
                currentPatch += line + "\n"
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    additions += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    deletions += 1
                }
            }
        }
        
        // Save last file
        if let file = currentFile {
            files.append(PRFile(
                filename: file,
                status: .modified,
                additions: additions,
                deletions: deletions,
                patch: currentPatch
            ))
        }
        
        return files
    }
    
    // MARK: - Helpers
    
    private func runCommand(_ command: String, args: [String], at directory: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = [command] + args
            task.currentDirectoryURL = directory
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func callAI(prompt: String) async throws -> String {
        var fullResponse = ""
        
        let stream = AIService.shared.streamMessage(
            prompt,
            context: nil,
            images: [],
            maxTokens: 2000,
            systemPrompt: "You are a code review expert. Be precise and concise."
        )
        
        for try await chunk in stream {
            fullResponse += chunk
        }
        
        return fullResponse
    }
}

// MARK: - Errors

enum BugbotError: Error, LocalizedError {
    case failedToFetchPR
    case noChangesToReview
    case fixFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .failedToFetchPR: return "Failed to fetch PR information"
        case .noChangesToReview: return "No changes to review"
        case .fixFailed(let msg): return "Fix failed: \(msg)"
        }
    }
}
