//
//  LinterService.swift
//  LingCode
//
//  Created for Linter-Driven Repair
//

import Foundation

enum LintError: Error, LocalizedError {
    case issues([String])
    
    var errorDescription: String? {
        switch self {
        case .issues(let messages):
            return "Linter found issues:\n" + messages.joined(separator: "\n")
        }
    }
}

final class LinterService {
    static let shared = LinterService()
    
    private init() {}
    
    /// Checks if we have a linter available for this workspace (configured + tool present)
    func hasLinter(for workspaceURL: URL) -> Bool {
        let fileManager = FileManager.default
        
        let swiftlintConfigPaths = [
            workspaceURL.appendingPathComponent(".swiftlint.yml").path,
            workspaceURL.appendingPathComponent(".swiftlint.yaml").path
        ]
        
        var hasSwiftLintConfig = false
        for path in swiftlintConfigPaths {
            if fileManager.fileExists(atPath: path) {
                hasSwiftLintConfig = true
                break
            }
        }
        
        if hasSwiftLintConfig {
            if isSwiftLintAvailable(in: workspaceURL) {
                return true
            }
        }
        
        let eslintConfigPaths = [
            workspaceURL.appendingPathComponent(".eslintrc").path,
            workspaceURL.appendingPathComponent(".eslintrc.json").path,
            workspaceURL.appendingPathComponent(".eslintrc.js").path,
            workspaceURL.appendingPathComponent(".eslintrc.cjs").path,
            workspaceURL.appendingPathComponent(".eslintrc.yml").path,
            workspaceURL.appendingPathComponent(".eslintrc.yaml").path,
            workspaceURL.appendingPathComponent("eslint.config.js").path,
            workspaceURL.appendingPathComponent("eslint.config.mjs").path,
            workspaceURL.appendingPathComponent("eslint.config.cjs").path,
            workspaceURL.appendingPathComponent("package.json").path
        ]
        
        var hasESLintSignal = false
        for path in eslintConfigPaths {
            if fileManager.fileExists(atPath: path) {
                hasESLintSignal = true
                break
            }
        }
        
        if hasESLintSignal {
            if isESLintAvailable(in: workspaceURL) {
                return true
            }
        }
        
        return false
    }
    
    /// Runs the appropriate linters on specific files (best effort). Returns `nil` if no issues.
    func validate(files: [URL], in workspace: URL, completion: @escaping (LintError?) -> Void) {
        if TerminalExecutionService.shared.isExecuting {
            completion(nil)
            return
        }
        
        let uniqueFiles = Array(Set(files.map { $0.standardizedFileURL }))
        
        let swiftFiles = uniqueFiles.filter { $0.pathExtension.lowercased() == "swift" }
        let eslintExts = Set(["js", "jsx", "ts", "tsx", "mjs", "cjs"])
        let eslintFiles = uniqueFiles.filter { eslintExts.contains($0.pathExtension.lowercased()) }
        
        if swiftFiles.isEmpty {
            if eslintFiles.isEmpty {
                completion(nil)
                return
            }
        }
        
        var issues: [String] = []
        
        runSwiftLintIfNeeded(files: swiftFiles, workspace: workspace) { swiftIssues in
            issues.append(contentsOf: swiftIssues)
            
            self.runESLintIfNeeded(files: eslintFiles, workspace: workspace) { eslintIssues in
                issues.append(contentsOf: eslintIssues)
                
                if issues.isEmpty {
                    completion(nil)
                } else {
                    completion(.issues(issues))
                }
            }
        }
    }
    
    // MARK: - SwiftLint
    
    private func isSwiftLintAvailable(in workspace: URL) -> Bool {
        let result = TerminalExecutionService.shared.executeSync("command -v swiftlint", workingDirectory: workspace)
        if result.exitCode == 0 {
            if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }
    
    private func runSwiftLintIfNeeded(files: [URL], workspace: URL, completion: @escaping ([String]) -> Void) {
        if files.isEmpty {
            completion([])
            return
        }
        
        let fileManager = FileManager.default
        let hasConfig = fileManager.fileExists(atPath: workspace.appendingPathComponent(".swiftlint.yml").path) ||
            fileManager.fileExists(atPath: workspace.appendingPathComponent(".swiftlint.yaml").path)
        
        if !hasConfig {
            completion([])
            return
        }
        
        if !isSwiftLintAvailable(in: workspace) {
            completion([])
            return
        }
        
        var collected: [String] = []
        
        func runNext(_ index: Int) {
            if index >= files.count {
                completion(collected)
                return
            }
            
            let fileURL = files[index]
            var cmdOutput = ""
            
            let command = "swiftlint lint --quiet --path \(shellQuote(fileURL.path))"
            
            TerminalExecutionService.shared.execute(
                command,
                workingDirectory: workspace,
                environment: nil,
                onOutput: { chunk in
                    cmdOutput.append(chunk)
                },
                onError: { chunk in
                    cmdOutput.append(chunk)
                },
                onComplete: { exitCode in
                    if exitCode != 0 {
                        let lines = self.nonEmptyLines(from: cmdOutput)
                        collected.append(contentsOf: lines)
                    }
                    runNext(index + 1)
                }
            )
        }
        
        runNext(0)
    }
    
    // MARK: - ESLint
    
    private func isESLintAvailable(in workspace: URL) -> Bool {
        let localESLint = workspace.appendingPathComponent("node_modules/.bin/eslint").path
        if FileManager.default.fileExists(atPath: localESLint) {
            return true
        }
        
        let npxResult = TerminalExecutionService.shared.executeSync("command -v npx", workingDirectory: workspace)
        if npxResult.exitCode == 0 {
            if !npxResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        
        return false
    }
    
    private func runESLintIfNeeded(files: [URL], workspace: URL, completion: @escaping ([String]) -> Void) {
        if files.isEmpty {
            completion([])
            return
        }
        
        if !isESLintAvailable(in: workspace) {
            completion([])
            return
        }
        
        let localESLintPath = workspace.appendingPathComponent("node_modules/.bin/eslint").path
        let hasLocalESLint = FileManager.default.fileExists(atPath: localESLintPath)
        
        let fileArgs = files
            .map { self.relativePathIfPossible($0, workspace: workspace) }
            .map { shellQuote($0) }
            .joined(separator: " ")
        
        let eslintCommand: String
        if hasLocalESLint {
            eslintCommand = "\(shellQuote(localESLintPath)) \(fileArgs) --max-warnings 0"
        } else {
            eslintCommand = "npx --no-install eslint \(fileArgs) --max-warnings 0"
        }
        
        var cmdOutput = ""
        
        TerminalExecutionService.shared.execute(
            eslintCommand,
            workingDirectory: workspace,
            environment: nil,
            onOutput: { chunk in
                cmdOutput.append(chunk)
            },
            onError: { chunk in
                cmdOutput.append(chunk)
            },
            onComplete: { exitCode in
                if exitCode != 0 {
                    completion(self.nonEmptyLines(from: cmdOutput))
                } else {
                    completion([])
                }
            }
        )
    }
    
    // MARK: - Helpers
    
    private func nonEmptyLines(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func relativePathIfPossible(_ fileURL: URL, workspace: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let workspacePath = workspace.standardizedFileURL.path
        
        if filePath.hasPrefix(workspacePath) {
            let start = filePath.index(filePath.startIndex, offsetBy: workspacePath.count)
            var relative = String(filePath[start...])
            if relative.hasPrefix("/") {
                relative.removeFirst()
            }
            if !relative.isEmpty {
                return relative
            }
        }
        
        return filePath
    }
    
    private func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'" + escaped + "'"
    }
}

