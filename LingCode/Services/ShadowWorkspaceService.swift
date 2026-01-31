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
    private var warmedProjects: Set<URL> = []
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.lingcode.shadowworkspace", qos: .utility)
    
    private init() {}
    
    // MARK: - Workspace Management
    
    func getShadowWorkspace(for projectURL: URL) -> URL? {
        queue.sync { activeWorkspaces[projectURL] }
    }
    
    func createShadowWorkspace(for projectURL: URL) -> URL? {
        cleanup(for: projectURL)
        let shadowURL = fileManager.temporaryDirectory.appendingPathComponent("lingcode-shadow-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: shadowURL, withIntermediateDirectories: true)
            queue.sync { activeWorkspaces[projectURL] = shadowURL }
            return shadowURL
        } catch {
            return nil
        }
    }
    
    /// Pre-warm shadow workspace: create if needed, initial sync, then keep in sync via file watcher.
    /// Reduces validation latency from seconds to milliseconds by avoiding copy-on-demand.
    func ensureShadowWarmed(for projectURL: URL, completion: @escaping (URL?) -> Void) {
        let normalized = projectURL.standardizedFileURL
        queue.async { [weak self] in
            guard let self = self else { return }
            if let existing = self.activeWorkspaces[normalized] {
                if self.warmedProjects.contains(normalized) {
                    DispatchQueue.main.async { completion(existing) }
                    return
                }
            }
            guard let shadowURL = self.getShadowWorkspace(for: normalized) ?? self.createShadowWorkspace(for: normalized) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.initialSync(projectURL: normalized, shadowURL: shadowURL) {
                self.queue.async {
                    self.warmedProjects.insert(normalized)
                    self.startWatchingForSync(projectURL: normalized, shadowURL: shadowURL)
                }
                DispatchQueue.main.async { completion(shadowURL) }
            }
        }
    }
    
    private func startWatchingForSync(projectURL: URL, shadowURL: URL) {
        FileWatcherService.shared.startWatching(projectURL) { [weak self] changedFileURL in
            self?.syncFileFromProjectToShadow(projectURL: projectURL, fileURL: changedFileURL)
        }
    }
    
    private func syncFileFromProjectToShadow(projectURL: URL, fileURL: URL) {
        let projectPath = projectURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(projectPath) else { return }
        var relative = String(filePath.dropFirst(projectPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { return }
        
        guard let shadowURL = getShadowWorkspace(for: projectURL) else { return }
        let dest = shadowURL.appendingPathComponent(relative)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: filePath, isDirectory: &isDir), !isDir.boolValue else { return }
        do {
            try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
            try fileManager.copyItem(at: fileURL, to: dest)
        } catch {}
    }
    
    private func initialSync(projectURL: URL, shadowURL: URL, completion: @escaping () -> Void) {
        let manifestFiles = ["Package.swift", "package.json", "requirements.txt", "Cargo.toml"]
        for fileName in manifestFiles {
            let src = projectURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: src.path) {
                let dest = shadowURL.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: dest)
                try? fileManager.copyItem(at: src, to: dest)
            }
        }
        let sourcesDir = projectURL.appendingPathComponent("Sources")
        let testsDir = projectURL.appendingPathComponent("Tests")
        if fileManager.fileExists(atPath: sourcesDir.path) {
            copyDirectory(from: sourcesDir, to: shadowURL.appendingPathComponent("Sources"))
        }
        if fileManager.fileExists(atPath: testsDir.path) {
            copyDirectory(from: testsDir, to: shadowURL.appendingPathComponent("Tests"))
        }
        completion()
    }
    
    private func copyDirectory(from src: URL, to dest: URL) {
        try? fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for case let item as URL in enumerator {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            let rel = item.path.replacingOccurrences(of: src.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = dest.appendingPathComponent(rel)
            if isDir.boolValue {
                try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
                try? fileManager.copyItem(at: item, to: target)
            }
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
        let url = queue.sync { activeWorkspaces.removeValue(forKey: projectURL.standardizedFileURL) }
        if let url = url {
            try? fileManager.removeItem(at: url)
            queue.sync { warmedProjects.remove(projectURL.standardizedFileURL) }
        }
    }

    // MARK: - CursorStreamingView verification

    /// Verifies that the given files compile in a shadow workspace before applying.
    /// Uses pre-warmed shadow when available for minimal latency.
    /// Completion: success, message, and optional verification duration in seconds (nil if no build was run).
    func verifyFilesInShadow(files: [StreamingFileInfo], originalWorkspace: URL, completion: @escaping (Bool, String, TimeInterval?) -> Void) {
        let projectURL = originalWorkspace.standardizedFileURL
        ensureShadowWarmed(for: projectURL) { [weak self] shadowURL in
            guard let self = self, let shadowURL = shadowURL else {
                completion(false, "Could not create shadow workspace.", nil)
                return
            }
            guard let first = files.first else {
                completion(true, "No files to verify.", nil)
                return
            }
            do {
                let isWarmed = self.queue.sync { self.warmedProjects.contains(projectURL) }
                if !isWarmed {
                    try self.prepareShadowWorkspaceForValidation(modifiedFileURL: projectURL.appendingPathComponent(first.path), projectURL: projectURL, shadowWorkspaceURL: shadowURL)
                }
                for file in files {
                    try self.writeToShadowWorkspace(content: file.content, relativePath: file.path, shadowWorkspaceURL: shadowURL)
                }
                let hasPackageSwift = self.fileManager.fileExists(atPath: shadowURL.appendingPathComponent("Package.swift").path)
                guard hasPackageSwift else {
                    completion(true, "No Package.swift; skipped build.", nil)
                    return
                }
                let startTime = Date()
                TerminalExecutionService.shared.execute(
                    "swift build 2>&1",
                    workingDirectory: shadowURL,
                    environment: nil,
                    onOutput: { _ in },
                    onError: { _ in },
                    onComplete: { exitCode in
                        let duration = Date().timeIntervalSince(startTime)
                        completion(exitCode == 0, exitCode == 0 ? "Build successful." : "Compilation failed.", duration)
                    }
                )
            } catch {
                completion(false, "Shadow setup failed: \(error.localizedDescription)", nil)
            }
        }
    }
}
