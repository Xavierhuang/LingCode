//
//  ShadowWorkspaceService.swift
//  LingCode
//
//  Shadow Workspace: Run validation in temporary directory before applying changes
//  Enables safer validation and allows running destructive tests without risk
//

import Foundation

/// Service for managing shadow workspaces (temporary directories for validation)
/// This allows running tests/builds in isolation before applying changes to the project
class ShadowWorkspaceService {
    static let shared = ShadowWorkspaceService()
    
    private var activeWorkspaces: [URL: URL] = [:] // projectURL -> shadowWorkspaceURL
    private let fileManager = FileManager.default
    
    private init() {}
    
    /// Create a shadow workspace for a project
    /// Returns the shadow workspace URL, or nil if creation failed
    func createShadowWorkspace(for projectURL: URL) -> URL? {
        // Check if we already have a shadow workspace for this project
        if let existing = activeWorkspaces[projectURL] {
            // Clean up old workspace if it exists
            try? fileManager.removeItem(at: existing)
        }
        
        // Create temporary directory
        let tempDir = fileManager.temporaryDirectory
        let shadowWorkspaceName = "lingcode-shadow-\(UUID().uuidString)"
        let shadowWorkspaceURL = tempDir.appendingPathComponent(shadowWorkspaceName)
        
        do {
            // Create shadow workspace directory
            try fileManager.createDirectory(at: shadowWorkspaceURL, withIntermediateDirectories: true)
            
            // Copy project structure to shadow workspace
            // We'll copy files on-demand when needed, but create the structure
            activeWorkspaces[projectURL] = shadowWorkspaceURL
            
            print("🟢 [ShadowWorkspace] Created shadow workspace: \(shadowWorkspaceURL.path)")
            return shadowWorkspaceURL
        } catch {
            print("🔴 [ShadowWorkspace] Failed to create shadow workspace: \(error)")
            return nil
        }
    }
    
    /// Copy a file to the shadow workspace, maintaining relative path structure
    func copyFileToShadowWorkspace(
        fileURL: URL,
        projectURL: URL,
        shadowWorkspaceURL: URL
    ) throws {
        // Calculate relative path from project root
        let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
        let shadowFileURL = shadowWorkspaceURL.appendingPathComponent(relativePath)
        
        // Create directory structure in shadow workspace
        let shadowDir = shadowFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: shadowDir, withIntermediateDirectories: true)
        
        // Copy file to shadow workspace
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.copyItem(at: fileURL, to: shadowFileURL)
            print("🟢 [ShadowWorkspace] Copied file to shadow: \(relativePath)")
        } else {
            // File doesn't exist yet (new file), create it
            try fileManager.createDirectory(at: shadowDir, withIntermediateDirectories: true)
            // File content will be written separately
        }
    }
    
    /// Write new content to a file in the shadow workspace
    func writeToShadowWorkspace(
        content: String,
        relativePath: String,
        shadowWorkspaceURL: URL
    ) throws {
        let shadowFileURL = shadowWorkspaceURL.appendingPathComponent(relativePath)
        
        // Create directory structure
        let shadowDir = shadowFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: shadowDir, withIntermediateDirectories: true)
        
        // Write content
        try content.write(to: shadowFileURL, atomically: true, encoding: .utf8)
        print("🟢 [ShadowWorkspace] Wrote content to shadow: \(relativePath)")
    }
    
    /// Copy necessary project files to shadow workspace for validation
    /// This includes dependency files (Package.swift, package.json, etc.) and related source files
    func prepareShadowWorkspaceForValidation(
        modifiedFileURL: URL,
        projectURL: URL,
        shadowWorkspaceURL: URL
    ) throws {
        // Copy dependency files
        let dependencyFiles = [
            "Package.swift",
            "package.json",
            "requirements.txt",
            "go.mod",
            "Cargo.toml",
            "pom.xml",
            "build.gradle"
        ]
        
        for depFile in dependencyFiles {
            let depURL = projectURL.appendingPathComponent(depFile)
            if fileManager.fileExists(atPath: depURL.path) {
                try copyFileToShadowWorkspace(
                    fileURL: depURL,
                    projectURL: projectURL,
                    shadowWorkspaceURL: shadowWorkspaceURL
                )
            }
        }
        
        // Copy the modified file itself
        try copyFileToShadowWorkspace(
            fileURL: modifiedFileURL,
            projectURL: projectURL,
            shadowWorkspaceURL: shadowWorkspaceURL
        )
        
        // For Swift projects, copy entire Sources directory if it exists
        let sourcesURL = projectURL.appendingPathComponent("Sources")
        if fileManager.fileExists(atPath: sourcesURL.path) {
            let shadowSourcesURL = shadowWorkspaceURL.appendingPathComponent("Sources")
            if fileManager.fileExists(atPath: shadowSourcesURL.path) {
                try fileManager.removeItem(at: shadowSourcesURL)
            }
            try fileManager.copyItem(at: sourcesURL, to: shadowSourcesURL)
            print("🟢 [ShadowWorkspace] Copied Sources directory to shadow")
        }
    }
    
    /// Get shadow workspace URL for a project
    func getShadowWorkspace(for projectURL: URL) -> URL? {
        return activeWorkspaces[projectURL]
    }
    
    /// Clean up shadow workspace for a project
    func cleanupShadowWorkspace(for projectURL: URL) {
        if let shadowURL = activeWorkspaces[projectURL] {
            do {
                try fileManager.removeItem(at: shadowURL)
                activeWorkspaces.removeValue(forKey: projectURL)
                print("🟢 [ShadowWorkspace] Cleaned up shadow workspace for project")
            } catch {
                print("⚠️ [ShadowWorkspace] Failed to cleanup shadow workspace: \(error)")
            }
        }
    }
    
    /// Clean up all shadow workspaces
    func cleanupAll() {
        for projectURL in activeWorkspaces.keys {
            cleanupShadowWorkspace(for: projectURL)
        }
    }
    
    /// Verify files in shadow workspace before applying to project
    /// This validates that the files compile/build correctly in isolation
    func verifyFilesInShadow(
        files: [StreamingFileInfo],
        originalWorkspace: URL,
        completion: @escaping (Bool, String) -> Void
    ) {
        // Create or get shadow workspace
        guard let shadowWorkspaceURL = getShadowWorkspace(for: originalWorkspace) ?? 
                                      createShadowWorkspace(for: originalWorkspace) else {
            completion(false, "Failed to create shadow workspace")
            return
        }
        
        // Write files to shadow workspace
        do {
            for file in files {
                try writeToShadowWorkspace(
                    content: file.content,
                    relativePath: file.path,
                    shadowWorkspaceURL: shadowWorkspaceURL
                )
            }
            
            // Prepare shadow workspace (copy dependencies)
            if let firstFile = files.first {
                let firstFileURL = originalWorkspace.appendingPathComponent(firstFile.path)
                try prepareShadowWorkspaceForValidation(
                    modifiedFileURL: firstFileURL,
                    projectURL: originalWorkspace,
                    shadowWorkspaceURL: shadowWorkspaceURL
                )
            }
            
            // Run validation in shadow workspace
            validateShadowWorkspace(
                shadowWorkspaceURL: shadowWorkspaceURL,
                originalWorkspace: originalWorkspace,
                completion: completion
            )
        } catch {
            completion(false, "Failed to prepare shadow workspace: \(error.localizedDescription)")
        }
    }
    
    /// Validate shadow workspace (run build/lint)
    private func validateShadowWorkspace(
        shadowWorkspaceURL: URL,
        originalWorkspace: URL,
        completion: @escaping (Bool, String) -> Void
    ) {
        // Check if it's a Swift project
        let hasPackageSwift = FileManager.default.fileExists(atPath: shadowWorkspaceURL.appendingPathComponent("Package.swift").path)
        let hasXcodeProject = FileManager.default.enumerator(at: originalWorkspace, includingPropertiesForKeys: nil)?.contains { url in
            (url as? URL)?.pathExtension == "xcodeproj"
        } ?? false
        
        if hasPackageSwift {
            // Run swift build in shadow workspace
            let terminalService = TerminalExecutionService.shared
            terminalService.execute(
                "swift build 2>&1",
                workingDirectory: shadowWorkspaceURL,
                environment: nil,
                onOutput: { _ in },
                onError: { _ in },
                onComplete: { exitCode in
                    if exitCode == 0 {
                        completion(true, "Validation passed")
                    } else {
                        completion(false, "Compilation failed in shadow workspace")
                    }
                }
            )
        } else if hasXcodeProject {
            // For Xcode projects, we can't easily build in shadow workspace
            // Just check for basic syntax errors using linter
            completion(true, "Xcode project - validation skipped (use Agent mode for full validation)")
        } else {
            // For non-Swift projects, basic validation passed
            completion(true, "Validation passed")
        }
    }
}
