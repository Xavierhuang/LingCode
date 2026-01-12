//
//  ApplyCodeService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

/// Service for applying AI-generated code changes with preview and confirmation
class ApplyCodeService: ObservableObject {
    static let shared = ApplyCodeService()
    
    @Published var pendingChanges: [CodeChange] = []
    @Published var isApplying: Bool = false
    @Published var lastApplyResult: ApplyResult?
    
    private let codeGenerator = CodeGeneratorService.shared
    
    private init() {}
    
    // MARK: - Parse Changes
    
    /// Parse code changes from AI response
    func parseChanges(from response: String, projectURL: URL?) -> [CodeChange] {
        var changes: [CodeChange] = []
        
        // Get file operations from code generator
        let operations = codeGenerator.extractFileOperations(from: response, projectURL: projectURL)
        
        for operation in operations {
            let fileURL = URL(fileURLWithPath: operation.filePath)
            
            // Get existing content if file exists
            let existingContent: String?
            if FileManager.default.fileExists(atPath: fileURL.path) {
                existingContent = try? String(contentsOf: fileURL, encoding: .utf8)
            } else {
                existingContent = nil
            }
            
            let change = CodeChange(
                id: UUID(),
                filePath: operation.filePath,
                fileName: fileURL.lastPathComponent,
                operationType: operation.type,
                originalContent: existingContent,
                newContent: operation.content ?? "",
                lineRange: operation.lineRange,
                language: detectLanguage(from: fileURL)
            )
            
            changes.append(change)
        }
        
        return changes
    }
    
    /// Set pending changes for review
    func setPendingChanges(_ changes: [CodeChange]) {
        DispatchQueue.main.async {
            self.pendingChanges = changes
        }
    }
    
    /// Check if changes should be split into stacked PRs using Graphite
    func shouldUseGraphiteStacking(_ changes: [CodeChange]) -> Bool {
        let totalFiles = changes.count
        let totalLines = changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
        
        // Suggest Graphite if:
        // - More than 10 files, OR
        // - More than 500 lines, OR
        // - More than 5 files AND more than 200 lines
        return totalFiles > 10 || totalLines > 500 || (totalFiles > 5 && totalLines > 200)
    }
    
    /// Get recommendation for change management
    func getChangeRecommendation(_ changes: [CodeChange]) -> ChangeRecommendation {
        let totalFiles = changes.count
        let totalLines = changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
        
        if shouldUseGraphiteStacking(changes) {
            return .useGraphiteStacking(
                reason: "Large change set (\(totalFiles) files, \(totalLines) lines). Consider using Graphite to split into smaller, reviewable PRs.",
                estimatedPRs: max(1, (totalFiles / 5) + (totalLines / 200))
            )
        } else if totalFiles > 5 || totalLines > 200 {
            return .reviewCarefully(
                reason: "Moderate change set (\(totalFiles) files, \(totalLines) lines). Review carefully before applying."
            )
        } else {
            return .safeToApply(
                reason: "Small change set (\(totalFiles) files, \(totalLines) lines). Safe to apply."
            )
        }
    }
    
    // MARK: - Apply Changes
    
    /// Apply a single change with validation
    func applyChange(_ change: CodeChange, requestedScope: String? = nil) -> ApplyChangeResult {
        // Git-aware validation
        if let projectURL = findProjectURL(for: change.filePath) {
            let fileURL = URL(fileURLWithPath: change.filePath)
            let gitValidation = GitAwareService.shared.validateEdit(
                Edit(
                    file: change.filePath,
                    operation: .replace,
                    range: change.lineRange.map { EditRange(startLine: $0.start, endLine: $0.end) },
                    anchor: nil,
                    content: change.newContent.components(separatedBy: .newlines)
                ),
                in: projectURL
            )
            
            switch gitValidation {
            case .rejected(let reason):
                return ApplyChangeResult(
                    success: false,
                    error: "Git validation failed: \(reason)",
                    validationResult: nil
                )
            case .warning(let message):
                // Log warning but continue
                print("⚠️ Git warning: \(message)")
            case .accepted:
                break
            }
        }
        
        // Validate before applying
        let validationService = CodeValidationService.shared
        let validation = validationService.validateChange(
            change,
            requestedScope: requestedScope ?? "Unknown",
            projectConfig: nil
        )
        
        // Block critical issues
        if validation.severity == .critical {
            return ApplyChangeResult(
                success: false,
                error: "Validation failed: \(validation.recommendation)",
                validationResult: validation
            )
        }
        
        let fileURL = URL(fileURLWithPath: change.filePath)
        
        // Create backup before applying
        let backupCreated = createBackup(fileURL: fileURL)
        
        do {
            // Create directory if needed
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            switch change.operationType {
            case .create, .update:
                try change.newContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
            case .append:
                var content = ""
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    content = try String(contentsOf: fileURL, encoding: .utf8)
                }
                content += "\n" + change.newContent
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
            case .delete:
                try FileManager.default.removeItem(at: fileURL)
            }
            
            return ApplyChangeResult(
                success: true,
                error: nil,
                validationResult: validation,
                backupCreated: backupCreated
            )
        } catch {
            // Restore backup on error
            if backupCreated {
                restoreBackup(fileURL: fileURL)
            }
            
            return ApplyChangeResult(
                success: false,
                error: "Failed to apply change: \(error.localizedDescription)",
                validationResult: validation,
                backupCreated: backupCreated
            )
        }
    }
    
    /// Create backup of file before modification
    private func createBackup(fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false // No file to backup
        }
        
        let backupURL = fileURL.appendingPathExtension("backup")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            return true
        } catch {
            print("Failed to create backup: \(error)")
            return false
        }
    }
    
    /// Restore backup if needed
    private func restoreBackup(fileURL: URL) {
        let backupURL = fileURL.appendingPathExtension("backup")
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: backupURL, to: fileURL)
        } catch {
            print("Failed to restore backup: \(error)")
        }
    }
    
    /// Apply all pending changes with atomic transaction and retry logic
    func applyAllChangesWithRetry(
        _ changes: [CodeChange],
        in workspaceURL: URL,
        aiService: AIService,
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        // Convert CodeChange to Edit format for atomic service
        // For now, use regular applyAllChanges
        // TODO: Full integration with JSONEditSchemaService and AtomicEditService
        applyAllChanges(onProgress: onProgress, onComplete: onComplete)
    }
    
    /// Apply all pending changes
    func applyAllChanges(
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        guard !pendingChanges.isEmpty else {
            onComplete(ApplyResult(success: true, appliedCount: 0, failedCount: 0, errors: []))
            return
        }
        
        isApplying = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var applied = 0
            var failed = 0
            var errors: [String] = []
            var appliedFiles: [URL] = []
            
            for (index, change) in self.pendingChanges.enumerated() {
                DispatchQueue.main.async {
                    onProgress(index + 1, self.pendingChanges.count)
                }
                
                let result = self.applyChange(change, requestedScope: "Batch apply")
                if result.success {
                    applied += 1
                    appliedFiles.append(URL(fileURLWithPath: change.filePath))
                } else {
                    failed += 1
                    errors.append(result.error ?? "Failed to \(change.operationType.rawValue) \(change.fileName)")
                }
            }
            
            let result = ApplyResult(
                success: failed == 0,
                appliedCount: applied,
                failedCount: failed,
                errors: errors,
                appliedFiles: appliedFiles
            )
            
            DispatchQueue.main.async {
                self.lastApplyResult = result
                self.isApplying = false
                self.pendingChanges.removeAll()
                
                // Notify about applied files
                if !appliedFiles.isEmpty {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FilesCreated"),
                        object: nil,
                        userInfo: ["files": appliedFiles]
                    )
                }
                
                onComplete(result)
            }
        }
    }
    
    /// Apply selected changes only
    func applySelectedChanges(
        _ selectedIds: Set<UUID>,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        let selectedChanges = pendingChanges.filter { selectedIds.contains($0.id) }
        let tempPending = pendingChanges
        pendingChanges = selectedChanges
        
        applyAllChanges(
            onProgress: { _, _ in },
            onComplete: { result in
                // Remove applied changes from pending
                self.pendingChanges = tempPending.filter { !selectedIds.contains($0.id) }
                onComplete(result)
            }
        )
    }
    
    /// Reject a change (remove from pending)
    func rejectChange(_ change: CodeChange) {
        pendingChanges.removeAll { $0.id == change.id }
    }
    
    /// Reject all changes
    func rejectAllChanges() {
        pendingChanges.removeAll()
    }
    
    // MARK: - Diff Generation
    
    /// Generate a unified diff for a change
    func generateDiff(for change: CodeChange) -> String {
        guard let original = change.originalContent else {
            // New file - show all lines as additions
            return change.newContent.components(separatedBy: .newlines)
                .map { "+ \($0)" }
                .joined(separator: "\n")
        }
        
        let originalLines = original.components(separatedBy: .newlines)
        let newLines = change.newContent.components(separatedBy: .newlines)
        
        // Simple diff - show removed and added lines
        var diff = ""
        diff += "--- a/\(change.fileName)\n"
        diff += "+++ b/\(change.fileName)\n"
        
        // Use a simple line-by-line comparison
        let maxLines = max(originalLines.count, newLines.count)
        var diffLines: [String] = []
        
        for i in 0..<maxLines {
            let origLine = i < originalLines.count ? originalLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            
            if origLine == newLine {
                if let line = origLine {
                    diffLines.append("  \(line)")
                }
            } else {
                if let orig = origLine {
                    diffLines.append("- \(orig)")
                }
                if let new = newLine {
                    diffLines.append("+ \(new)")
                }
            }
        }
        
        return diff + diffLines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private func detectLanguage(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let languageMap: [String: String] = [
            "swift": "swift",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "jsx": "jsx",
            "tsx": "tsx",
            "html": "html",
            "css": "css",
            "json": "json",
            "md": "markdown",
            "rs": "rust",
            "go": "go",
            "java": "java",
            "kt": "kotlin",
            "c": "c",
            "cpp": "cpp",
            "h": "c",
            "hpp": "cpp",
            "yaml": "yaml",
            "yml": "yaml",
            "toml": "toml",
            "xml": "xml",
            "sh": "bash",
            "bash": "bash",
            "zsh": "bash"
        ]
        return languageMap[ext] ?? "text"
    }
}

// MARK: - Supporting Types

struct CodeChange: Identifiable {
    let id: UUID
    let filePath: String
    let fileName: String
    let operationType: FileOperation.OperationType
    let originalContent: String?
    let newContent: String
    let lineRange: (start: Int, end: Int)?
    let language: String
    
    var isNewFile: Bool {
        originalContent == nil && operationType == .create
    }
    
    var isModification: Bool {
        originalContent != nil && operationType == .update
    }
    
    var isDeletion: Bool {
        operationType == .delete
    }
    
    var changeDescription: String {
        switch operationType {
        case .create: return "Create new file"
        case .update: return "Modify existing file"
        case .append: return "Append to file"
        case .delete: return "Delete file"
        }
    }
    
    var addedLines: Int {
        guard let original = originalContent else {
            return newContent.components(separatedBy: .newlines).count
        }
        let origCount = original.components(separatedBy: .newlines).count
        let newCount = newContent.components(separatedBy: .newlines).count
        return max(0, newCount - origCount)
    }
    
    var removedLines: Int {
        guard let original = originalContent else { return 0 }
        let origCount = original.components(separatedBy: .newlines).count
        let newCount = newContent.components(separatedBy: .newlines).count
        return max(0, origCount - newCount)
    }
}

struct ApplyResult {
    let success: Bool
    let appliedCount: Int
    let failedCount: Int
    let errors: [String]
    var appliedFiles: [URL] = []
}

enum ChangeRecommendation {
    case safeToApply(reason: String)
    case reviewCarefully(reason: String)
    case useGraphiteStacking(reason: String, estimatedPRs: Int)
    
    var message: String {
        switch self {
        case .safeToApply(let reason):
            return reason
        case .reviewCarefully(let reason):
            return "⚠️ \(reason)"
        case .useGraphiteStacking(let reason, let prs):
            return "📚 \(reason) Estimated: \(prs) PRs"
        }
    }
    
    var shouldWarn: Bool {
        switch self {
        case .safeToApply:
            return false
        case .reviewCarefully, .useGraphiteStacking:
            return true
        }
    }
}

struct ApplyChangeResult {
    let success: Bool
    let error: String?
    let validationResult: ValidationResult?
    var backupCreated: Bool = false
    
    var canRollback: Bool {
        backupCreated && !success
    }
}

// MARK: - Helper Methods

extension ApplyCodeService {
    /// Find project URL for file path
    func findProjectURL(for filePath: String) -> URL? {
        let fileURL = URL(fileURLWithPath: filePath)
        // Try to find project root (look for .git, package.json, etc.)
        var current = fileURL.deletingLastPathComponent()
        while current.path != "/" {
            let gitPath = current.appendingPathComponent(".git")
            let packagePath = current.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: gitPath.path) ||
               FileManager.default.fileExists(atPath: packagePath.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return fileURL.deletingLastPathComponent() // Fallback to file's directory
    }
}
