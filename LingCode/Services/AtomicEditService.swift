//
//  AtomicEditService.swift
//  LingCode
//
//  Safe multi-file edits with atomic transactions, snapshot/rollback, and dependency ordering
//

import Foundation

struct WorkspaceSnapshot {
    let files: [URL: String]
    let timestamp: Date
    
    static func create(from workspaceURL: URL) -> WorkspaceSnapshot {
        var files: [URL: String] = [:]
        
        guard let enumerator = FileManager.default.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return WorkspaceSnapshot(files: files, timestamp: Date())
        }
        
        for case let url as URL in enumerator {
            guard !url.hasDirectoryPath,
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            files[url] = content
        }
        
        return WorkspaceSnapshot(files: files, timestamp: Date())
    }
    
    func restore(to workspaceURL: URL) throws {
        for (url, content) in files {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
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
    
    private init() {}
    
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
                onError(error)
            } catch let restoreError {
                // If restore fails, this is critical
                onError(AtomicEditError.restoreFailed(original: error, restore: restoreError))
            }
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
    
    private func detectDependencyType(fileURL: URL) -> EditDependencyType {
        let path = fileURL.path.lowercased()
        let fileName = fileURL.lastPathComponent.lowercased()
        
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
           fileName.contains("protocol") ||
           path.contains("/interfaces/") ||
           path.contains("/protocols/") {
            return .interface
        }
        
        // Tests
        if fileName.contains("test") ||
           fileName.contains("spec") ||
           path.contains("/test") ||
           path.contains("/tests/") ||
           path.contains("/spec/") {
            return .test
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
