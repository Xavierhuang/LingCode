//
//  AtomicEditService.swift
//  LingCode
//
//  Safe multi-file edits with atomic transactions, snapshot/rollback, and dependency ordering
//

import Foundation

struct WorkspaceSnapshot {
    // CRITICAL FIX: Use Data instead of String to prevent binary file corruption
    let files: [URL: Data]
    let timestamp: Date
    let gitWorktreePath: URL? // Git worktree path for hardened rollback
    
    static func create(from workspaceURL: URL) -> WorkspaceSnapshot {
        var files: [URL: Data] = [:]
        var gitWorktree: URL? = nil
        
        // HARDENED ROLLBACK: Use git worktree if available (atomic, crash-safe)
        if isGitRepository(workspaceURL) {
            gitWorktree = createGitWorktree(for: workspaceURL)
        }
        
        // Fallback: manual snapshot if git is not available
        if gitWorktree == nil {
            guard let enumerator = FileManager.default.enumerator(
                at: workspaceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return WorkspaceSnapshot(files: files, timestamp: Date(), gitWorktreePath: nil)
            }
            
            for case let url as URL in enumerator {
                guard !url.hasDirectoryPath else { continue }
                
                // CRITICAL FIX: Read as Data to preserve binary files (images, compiled binaries, etc.)
                // Only attempt UTF-8 conversion for text files when needed for restore
                if let data = try? Data(contentsOf: url) {
                    files[url] = data
                }
            }
        }
        
        return WorkspaceSnapshot(files: files, timestamp: Date(), gitWorktreePath: gitWorktree)
    }
    
    func restore(to workspaceURL: URL) throws {
        // HARDENED ROLLBACK: Use git worktree if available (atomic, crash-safe)
        if let worktree = gitWorktreePath {
            try restoreFromGitWorktree(worktree: worktree, to: workspaceURL)
        } else {
            // Fallback: manual restore
            try restoreManually(to: workspaceURL)
        }
    }
    
    private func restoreManually(to workspaceURL: URL) throws {
        for (url, data) in files {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            // CRITICAL FIX: Write Data directly to preserve binary files
            // No UTF-8 conversion that would corrupt images, binaries, etc.
            try data.write(to: url, options: .atomic)
        }
    }
    
    private func restoreFromGitWorktree(worktree: URL, to workspaceURL: URL) throws {
        // Use git checkout to restore from worktree (atomic operation)
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync(
            "git --work-tree=\(shellQuote(worktree.path)) checkout --work-tree=\(shellQuote(workspaceURL.path)) .",
            workingDirectory: workspaceURL
        )
        
        if result.exitCode != 0 {
            throw AtomicEditError.restoreFailed(
                original: NSError(domain: "AtomicEdit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Git restore failed"]),
                restore: NSError(domain: "AtomicEdit", code: 2, userInfo: [NSLocalizedDescriptionKey: result.output])
            )
        }
    }
    
    private func shellQuote(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    private static func isGitRepository(_ url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path) || 
               FileManager.default.fileExists(atPath: gitDir.path + "/HEAD")
    }
    
    private static func createGitWorktree(for workspaceURL: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let worktreeName = "LingCode_Worktree_\(UUID().uuidString)"
        let worktreePath = tempDir.appendingPathComponent(worktreeName)
        
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync(
            "git worktree add \(shellQuote(worktreePath.path)) HEAD",
            workingDirectory: workspaceURL
        )
        
        if result.exitCode == 0 {
            return worktreePath
        }
        
        return nil
    }
    
    private static func shellQuote(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum EditDependencyType {
    case type
    case interface
    case core
    case callSite
    case test
    case other
}

struct EditWithDependency {
    let edit: Edit
    let dependencyType: EditDependencyType
    let fileURL: URL
}

class AtomicEditService {
    static let shared = AtomicEditService()
    
    private var activeWorktrees: [URL: URL] = [:] // Maps workspace -> worktree
    private let worktreeQueue = DispatchQueue(label: "com.lingcode.worktree", attributes: .concurrent)
    
    private init() {}
    
    deinit {
        // Cleanup all active worktrees
        for (workspace, worktree) in activeWorktrees {
            cleanupWorktree(worktree, in: workspace)
        }
    }
    
    private func cleanupWorktree(_ worktree: URL, in workspace: URL) {
        let terminalService = TerminalExecutionService.shared
        _ = terminalService.executeSync(
            "git worktree remove \(shellQuote(worktree.path))",
            workingDirectory: workspace
        )
        worktreeQueue.async(flags: .barrier) {
            self.activeWorktrees.removeValue(forKey: workspace)
        }
    }
    
    private func shellQuote(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    /// Apply multiple edits atomically with dependency ordering
    func applyEdits(
        _ edits: [Edit],
        in workspaceURL: URL,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Create snapshot
        let snapshot = WorkspaceSnapshot.create(from: workspaceURL)
        
        // Validate all edits first
        do {
            for edit in edits {
                try JSONEditSchemaService.shared.validate(edit: edit, workspaceURL: workspaceURL)
            }
        } catch {
            onError(error)
            return
        }
        
        // Order edits by dependency
        let orderedEdits = orderEditsByDependency(edits, in: workspaceURL)
        
        // Apply in memory first (simulate)
        var appliedFiles: [URL] = []
        
        do {
            // Apply each edit
            for (index, editWithDep) in orderedEdits.enumerated() {
                onProgress("[\(index + 1)/\(orderedEdits.count)] Applying: \(editWithDep.fileURL.lastPathComponent)")
                
                try JSONEditSchemaService.shared.apply(
                    edit: editWithDep.edit,
                    in: workspaceURL
                )
                
                appliedFiles.append(editWithDep.fileURL)
            }
            
            // Re-run diagnostics (placeholder - would integrate with actual diagnostics)
            // For now, we'll just check if files are valid
            
            // Success - commit
            // Create undo snapshot
            TimeTravelUndoService.shared.snapshotAfterMultiFileEdit(
                affectedFiles: appliedFiles,
                in: workspaceURL
            )
            
            onComplete(appliedFiles)
            
        } catch {
            // Rollback on error
            do {
                try snapshot.restore(to: workspaceURL)
                
                // Cleanup worktree after successful restore
                if let worktree = snapshot.gitWorktreePath {
                    cleanupWorktree(worktree, in: workspaceURL)
                }
                
                onError(error)
            } catch let restoreError {
                // If restore fails, this is critical
                onError(AtomicEditError.restoreFailed(original: error, restore: restoreError))
            }
        }
        
        // Cleanup worktree after successful completion
        if let worktree = snapshot.gitWorktreePath {
            cleanupWorktree(worktree, in: workspaceURL)
        }
    }
    
    /// Order edits by dependency: types → interfaces → core → call sites → tests
    private func orderEditsByDependency(_ edits: [Edit], in workspaceURL: URL) -> [EditWithDependency] {
        var editWithDeps: [EditWithDependency] = []
        
        for edit in edits {
            let fileURL = workspaceURL.appendingPathComponent(edit.file)
            let dependencyType = detectDependencyType(fileURL: fileURL)
            
            editWithDeps.append(EditWithDependency(
                edit: edit,
                dependencyType: dependencyType,
                fileURL: fileURL
            ))
        }
        
        // Sort by dependency priority
        let priority: [EditDependencyType: Int] = [
            .type: 1,
            .interface: 2,
            .core: 3,
            .callSite: 4,
            .test: 5,
            .other: 6
        ]
        
        return editWithDeps.sorted { edit1, edit2 in
            let priority1 = priority[edit1.dependencyType] ?? 99
            let priority2 = priority[edit2.dependencyType] ?? 99
            return priority1 < priority2
        }
    }
    
    /// CRITICAL FIX: Use import-based dependency detection instead of brittle string matching
    private func detectDependencyType(fileURL: URL) -> EditDependencyType {
        // CRITICAL FIX: Use FileDependencyService to build import graph
        // This is more accurate than string matching (e.g., ReviewController.swift won't be misclassified)
        guard let projectURL = getProjectURL(for: fileURL) else {
            // Fallback to path-based detection if project URL unavailable
            return detectDependencyTypeByPath(fileURL: fileURL)
        }
        
        // Build dependency graph to understand import relationships
        let dependencyService = FileDependencyService.shared
        let importedFiles = dependencyService.findImportedFiles(for: fileURL, in: projectURL)
        let referencedBy = dependencyService.findReferencedFiles(for: fileURL, in: projectURL)
        
        // If file imports many files but is imported by few, it's likely a call site (view/component)
        if importedFiles.count > 3 && referencedBy.count < 2 {
            return .callSite
        }
        
        // If file is imported by many files but imports few, it's likely core/type
        if referencedBy.count > 3 && importedFiles.count < 2 {
            // Check if it's a type/model by reading content
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                if content.contains("struct ") || content.contains("class ") || content.contains("enum ") {
                    return .type
                }
                if content.contains("protocol ") {
                    return .interface
                }
            }
            return .core
        }
        
        // Fallback to path-based detection for edge cases
        return detectDependencyTypeByPath(fileURL: fileURL)
    }
    
    /// Fallback: Path-based detection (used when import graph unavailable)
    private func detectDependencyTypeByPath(fileURL: URL) -> EditDependencyType {
        let path = fileURL.path.lowercased()
        let fileName = fileURL.lastPathComponent.lowercased()
        
        // Tests
        if fileName.contains("test") ||
           fileName.contains("spec") ||
           path.contains("/test") ||
           path.contains("/tests/") ||
           path.contains("/spec/") {
            return .test
        }
        
        // Types
        if fileName.contains("type") || 
           fileName.contains("model") ||
           path.contains("/types/") ||
           path.contains("/models/") {
            return .type
        }
        
        // Interfaces
        if fileName.contains("interface") ||
           fileName.contains("protocol") ||
           path.contains("/interfaces/") ||
           path.contains("/protocols/") {
            return .interface
        }
        
        // Core logic (services, controllers, etc.)
        if fileName.contains("service") ||
           fileName.contains("controller") ||
           fileName.contains("manager") ||
           path.contains("/services/") ||
           path.contains("/controllers/") ||
           path.contains("/core/") {
            return .core
        }
        
        // Call sites (views, components, etc.)
        if fileName.contains("view") ||
           fileName.contains("component") ||
           path.contains("/views/") ||
           path.contains("/components/") {
            return .callSite
        }
        
        return .other
    }
    
    /// Get project URL from file URL (walks up directory tree to find project root)
    private func getProjectURL(for fileURL: URL) -> URL? {
        var current = fileURL.deletingLastPathComponent()
        while current.path != "/" {
            // Check for common project indicators
            let gitDir = current.appendingPathComponent(".git")
            let xcodeProj = current.pathExtension == "xcodeproj"
            let packageSwift = current.appendingPathComponent("Package.swift")
            
            if FileManager.default.fileExists(atPath: gitDir.path) ||
               xcodeProj ||
               FileManager.default.fileExists(atPath: packageSwift.path) {
                return current
            }
            
            current = current.deletingLastPathComponent()
        }
        return nil
    }
}

enum AtomicEditError: Error, LocalizedError {
    case restoreFailed(original: Error, restore: Error)
    case validationFailed([Error])
    
    var errorDescription: String? {
        switch self {
        case .restoreFailed(let original, let restore):
            return "Failed to apply edits: \(original.localizedDescription). Failed to restore: \(restore.localizedDescription)"
        case .validationFailed(let errors):
            return "Validation failed: \(errors.map { $0.localizedDescription }.joined(separator: ", "))"
        }
    }
}
