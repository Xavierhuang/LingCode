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
        let result = TerminalExecutionService.shared.executeSync("which gt")
        return result.exitCode == 0 && !result.output.trimmingCharacters(in: .whitespaces).isEmpty
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
                    let commitMessage = "AI-generated changes (\(group.count) files)"
                    if commitChanges(group, branch: branchName, message: commitMessage, in: directory) {
                        let pr = StackedPR(
                            branch: branchName,
                            baseBranch: previousBranch,
                            changes: group,
                            prNumber: index + 1,
                            totalPRs: prGroups.count,
                            layerName: "layer-\(index + 1)",
                            description: commitMessage
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
    
    /// AI-powered: Split large diff into logical layers (Infrastructure, Logic, UI)
    func createStackingPlan(
        changes: [CodeChange],
        completion: @escaping (Result<StackingPlan, Error>) -> Void
    ) {
        // Build diff summary for AI
        let diffSummary = buildDiffSummary(changes)
        
        let prompt = """
        Analyze this large code diff and split it into logical layers for stacked PRs.
        
        Diff Summary:
        \(diffSummary)
        
        Split the changes into layers such as:
        - Infrastructure (database, config, core services)
        - Logic (business logic, services, utilities)
        - UI (views, components, styling)
        - Tests (test files)
        
        Return a JSON array of layers, each with:
        - name: Layer name (e.g., "infra", "logic", "ui")
        - description: Brief description
        - files: Array of file paths that belong to this layer
        
        Format:
        [
          {
            "name": "infra",
            "description": "Infrastructure changes",
            "files": ["path/to/file1.swift", "path/to/file2.swift"]
          },
          {
            "name": "logic",
            "description": "Business logic changes",
            "files": ["path/to/file3.swift"]
          }
        ]
        """
        
        // Use ModernAIService to generate stacking plan
        Task {
            do {
                let aiService: AIProviderProtocol = ServiceContainer.shared.ai
                let response = try await aiService.sendMessage(prompt, context: nil, images: [])
                
                // Parse AI response to extract stacking plan
                if let plan = self.parseStackingPlan(from: response, changes: changes) {
                    completion(.success(plan))
                } else {
                    // Fallback to size-based grouping
                    let fallbackPlan = self.createFallbackPlan(changes: changes)
                    completion(.success(fallbackPlan))
                }
            } catch {
                // Fallback to size-based grouping on AI error
                let fallbackPlan = self.createFallbackPlan(changes: changes)
                completion(.success(fallbackPlan))
            }
        }
    }
    
    /// Create a stack from a stacking plan using Graphite CLI
    func createStack(
        from plan: StackingPlan,
        baseBranch: String = "main",
        in workspaceURL: URL,
        completion: @escaping (Result<[StackedPR], Error>) -> Void
    ) {
        guard isGraphiteInstalled() else {
            completion(.failure(NSError(domain: "GraphiteService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Graphite CLI not installed. Install from https://graphite.dev"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var stackedPRs: [StackedPR] = []
            var previousBranch = baseBranch
            
            for (index, layer) in plan.layers.enumerated() {
                // Get changes for this layer
                let layerChanges = plan.getChangesForLayer(layer, from: plan.allChanges)
                
                guard !layerChanges.isEmpty else { continue }
                
                // Create branch name from layer name
                let branchName = "\(layer.name)-\(index + 1)"
                
                // Use Graphite CLI: gt create <branch> --insert
                let createCommand = index == 0 
                    ? "gt create \(branchName) -m \"\(layer.description)\""
                    : "gt create \(branchName) --insert -m \"\(layer.description)\""
                
                let createResult = TerminalExecutionService.shared.executeSync(
                    createCommand,
                    workingDirectory: workspaceURL
                )
                
                guard createResult.exitCode == 0 else {
                    completion(.failure(NSError(domain: "GraphiteService", code: Int(createResult.exitCode), userInfo: [NSLocalizedDescriptionKey: "Failed to create branch: \(createResult.output)"])))
                    return
                }
                
                // Apply changes for this layer
                if self.applyChangesToBranch(layerChanges, in: workspaceURL) {
                    // Commit changes
                    if self.commitChanges(layerChanges, branch: branchName, message: layer.description, in: workspaceURL) {
                        let pr = StackedPR(
                            branch: branchName,
                            baseBranch: previousBranch,
                            changes: layerChanges,
                            prNumber: index + 1,
                            totalPRs: plan.layers.count,
                            layerName: layer.name,
                            description: layer.description
                        )
                        stackedPRs.append(pr)
                        previousBranch = branchName
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(.success(stackedPRs))
            }
        }
    }
    
    /// Submit the entire stack to GitHub
    func submitStack(in workspaceURL: URL, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard isGraphiteInstalled() else {
            completion(.failure(NSError(domain: "GraphiteService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Graphite CLI not installed"])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TerminalExecutionService.shared.executeSync(
                "gt submit --no-interactive",
                workingDirectory: workspaceURL
            )
            
            DispatchQueue.main.async {
                if result.exitCode == 0 {
                    completion(.success(true))
                } else {
                    completion(.failure(NSError(domain: "GraphiteService", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: result.output])))
                }
            }
        }
    }
    
    /// Checkout a specific branch in the stack
    func checkoutBranch(_ branchName: String, in workspaceURL: URL, completion: @escaping (Result<Bool, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TerminalExecutionService.shared.executeSync(
                "gt checkout \(branchName)",
                workingDirectory: workspaceURL
            )
            
            DispatchQueue.main.async {
                if result.exitCode == 0 {
                    completion(.success(true))
                } else {
                    completion(.failure(NSError(domain: "GraphiteService", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: result.output])))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func buildDiffSummary(_ changes: [CodeChange]) -> String {
        var summary = "Total: \(changes.count) files changed\n\n"
        
        for change in changes {
            let lines = change.addedLines + change.removedLines
            summary += "\(change.filePath): \(lines) lines (\(change.operationType.rawValue))\n"
        }
        
        return summary
    }
    
    private func parseStackingPlan(from response: String, changes: [CodeChange]) -> StackingPlan? {
        // Try to extract JSON from response
        let jsonPattern = #"```json\s*(\[[\s\S]*?\])\s*```"#
        guard let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..<response.endIndex, in: response)),
              let jsonRange = Range(match.range(at: 1), in: response) else {
            return nil
        }
        
        let jsonString = String(response[jsonRange])
        guard let jsonData = jsonString.data(using: .utf8),
              let layers = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return nil
        }
        
        var stackingLayers: [StackingLayer] = []
        for layerDict in layers {
            guard let name = layerDict["name"] as? String,
                  let description = layerDict["description"] as? String,
                  let files = layerDict["files"] as? [String] else {
                continue
            }
            stackingLayers.append(StackingLayer(
                name: name,
                description: description,
                filePaths: files
            ))
        }
        
        guard !stackingLayers.isEmpty else { return nil }
        
        return StackingPlan(layers: stackingLayers, allChanges: changes)
    }
    
    func createFallbackPlan(changes: [CodeChange]) -> StackingPlan {
        // Fallback: Group by size (max 5 files or 300 lines per layer)
        var layers: [StackingLayer] = []
        var currentLayerFiles: [String] = []
        var currentLayerLines = 0
        var layerIndex = 1
        
        for change in changes {
            let changeLines = change.addedLines + change.removedLines
            
            if currentLayerFiles.count >= 5 || (currentLayerLines + changeLines) > 300 {
                // Start new layer
                if !currentLayerFiles.isEmpty {
                    layers.append(StackingLayer(
                        name: "layer-\(layerIndex)",
                        description: "Changes \(layerIndex) (\(currentLayerFiles.count) files)",
                        filePaths: currentLayerFiles
                    ))
                    layerIndex += 1
                    currentLayerFiles = []
                    currentLayerLines = 0
                }
            }
            
            currentLayerFiles.append(change.filePath)
            currentLayerLines += changeLines
        }
        
        // Add final layer
        if !currentLayerFiles.isEmpty {
            layers.append(StackingLayer(
                name: "layer-\(layerIndex)",
                description: "Changes \(layerIndex) (\(currentLayerFiles.count) files)",
                filePaths: currentLayerFiles
            ))
        }
        
        return StackingPlan(layers: layers, allChanges: changes)
    }
    
    /// Group changes into logical PRs based on size and dependencies (legacy method)
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
    private func commitChanges(_ changes: [CodeChange], branch: String, message: String, in directory: URL) -> Bool {
        // Stage all changes
        for change in changes {
            let addResult = TerminalExecutionService.shared.executeSync(
                "git add \(change.filePath)",
                workingDirectory: directory
            )
            guard addResult.exitCode == 0 else { return false }
        }
        
        // Create commit message
        let fileCount = changes.count
        let totalLines = changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
        let commitMessage = """
        \(message)
        
        \(fileCount) files, \(totalLines) lines changed
        Files:
        \(changes.map { "- \($0.fileName)" }.joined(separator: "\n"))
        """
        
        let commitResult = TerminalExecutionService.shared.executeSync(
            "git commit -m \(commitMessage.shellEscaped())",
            workingDirectory: directory
        )
        
        return commitResult.exitCode == 0
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
    let layerName: String
    let description: String
    
    var displayDescription: String {
        let lines = totalLines
        return "PR \(prNumber)/\(totalPRs): \(layerName) - \(changes.count) files, \(lines) lines"
    }
    
    var totalLines: Int {
        changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
    }
}

struct StackingPlan {
    let layers: [StackingLayer]
    let allChanges: [CodeChange]
    
    func getChangesForLayer(_ layer: StackingLayer, from changes: [CodeChange]) -> [CodeChange] {
        let layerFilePaths = Set(layer.filePaths)
        return changes.filter { layerFilePaths.contains($0.filePath) }
    }
}

struct StackingLayer {
    let name: String
    let description: String
    let filePaths: [String]
}

struct StackStatus {
    let branches: [String]
    let totalPRs: Int
}

// MARK: - Extensions

extension String {
    func shellEscaped() -> String {
        return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
