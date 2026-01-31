//
//  ShadowWorkspaceService.swift
//  LingCode
//
//  Isolated build environment for background validation and self-healing.
//

import Foundation

class ShadowWorkspaceService {
    static let shared = ShadowWorkspaceService()
    
    private var activeWorkspaces: [URL: URL] = [:]
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Workspace Management
    
    func getShadowWorkspace(for projectURL: URL) -> URL? {
        return activeWorkspaces[projectURL]
    }
    
    func createShadowWorkspace(for projectURL: URL) -> URL? {
        cleanup(for: projectURL)
        let shadowURL = fileManager.temporaryDirectory.appendingPathComponent("lingcode-shadow-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: shadowURL, withIntermediateDirectories: true)
            activeWorkspaces[projectURL] = shadowURL
            return shadowURL
        } catch {
            return nil
        }
    }
    
    // MARK: - File Operations
    
    func prepareShadowWorkspaceForValidation(modifiedFileURL: URL, projectURL: URL, shadowWorkspaceURL: URL) throws {
        let manifestFiles = ["Package.swift", "package.json", "requirements.txt", "Cargo.toml"]
        
        // 1. Sync manifests
        for fileName in manifestFiles {
            let src = projectURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: src.path) {
                let dest = shadowWorkspaceURL.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: dest.path) { try? fileManager.removeItem(at: dest) }
                try fileManager.copyItem(at: src, to: dest)
            }
        }
        
        // 2. Sync siblings to provide context for compilation
        let relativeDir = modifiedFileURL.deletingLastPathComponent().path
            .replacingOccurrences(of: projectURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if !relativeDir.isEmpty {
            let srcDir = projectURL.appendingPathComponent(relativeDir)
            let destDir = shadowWorkspaceURL.appendingPathComponent(relativeDir)
            try? fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
            
            let items = try fileManager.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
            for item in items {
                let target = destDir.appendingPathComponent(item.lastPathComponent)
                if !fileManager.fileExists(atPath: target.path) && item.path != modifiedFileURL.path {
                    try? fileManager.copyItem(at: item, to: target)
                }
            }
        }
    }
    
    func writeToShadowWorkspace(content: String, relativePath: String, shadowWorkspaceURL: URL) throws {
        let shadowFileURL = shadowWorkspaceURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: shadowFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: shadowFileURL, atomically: true, encoding: .utf8)
    }

    func cleanup(for projectURL: URL) {
        if let url = activeWorkspaces[projectURL] {
            try? fileManager.removeItem(at: url)
            activeWorkspaces.removeValue(forKey: projectURL)
        }
    }

    // MARK: - CursorStreamingView verification

    /// Verifies that the given files compile in a shadow workspace before applying.
    func verifyFilesInShadow(files: [StreamingFileInfo], originalWorkspace: URL, completion: @escaping (Bool, String) -> Void) {
        guard let shadowURL = getShadowWorkspace(for: originalWorkspace) ?? createShadowWorkspace(for: originalWorkspace) else {
            completion(false, "Could not create shadow workspace.")
            return
        }
        guard let first = files.first else {
            completion(true, "No files to verify.")
            return
        }
        do {
            try prepareShadowWorkspaceForValidation(modifiedFileURL: originalWorkspace.appendingPathComponent(first.path), projectURL: originalWorkspace, shadowWorkspaceURL: shadowURL)
            for file in files {
                try writeToShadowWorkspace(content: file.content, relativePath: file.path, shadowWorkspaceURL: shadowURL)
            }
            let hasPackageSwift = fileManager.fileExists(atPath: shadowURL.appendingPathComponent("Package.swift").path)
            guard hasPackageSwift else {
                completion(true, "No Package.swift; skipped build.")
                return
            }
            TerminalExecutionService.shared.execute(
                "swift build 2>&1",
                workingDirectory: shadowURL,
                environment: nil,
                onOutput: { _ in },
                onError: { _ in },
                onComplete: { exitCode in
                    completion(exitCode == 0, exitCode == 0 ? "Build successful." : "Compilation failed.")
                }
            )
        } catch {
            completion(false, "Shadow setup failed: \(error.localizedDescription)")
        }
    }
}
