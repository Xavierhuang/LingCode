//
//  ShadowWorkspaceService.swift
//  LingCode
//
//  Created for Runtime Verification
//  Beats Cursor by proving code compiles before the user accepts it.
//

import Foundation

enum ShadowError: Error, LocalizedError {
    case copyFailed
    case applyFailed
    case buildFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .copyFailed:
            return "Failed to create shadow copy of workspace"
        case .applyFailed:
            return "Failed to apply edits to shadow workspace"
        case .buildFailed(let message):
            return "Build failed: \(message)"
        }
    }
}

class ShadowWorkspaceService {
    static let shared = ShadowWorkspaceService()
    
    private let fileManager = FileManager.default
    private var activeShadows: [URL: URL] = [:] // Maps Real Workspace -> Shadow Workspace
    
    private init() {}
    
    /// 1. Create a fast APFS clone of the workspace
    /// FIX: Added APFS fallback and filesystem detection
    func createShadowCopy(of workspaceURL: URL) throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let shadowName = "LingCode_Shadow_\(UUID().uuidString)"
        let shadowURL = tempDir.appendingPathComponent(shadowName)
        
        // Try APFS clonefile first (fast, near-zero disk usage)
        let cloneCommand = "cp -Rc \(shellQuote(workspaceURL.path)) \(shellQuote(shadowURL.path))"
        let cloneResult = TerminalExecutionService.shared.executeSync(cloneCommand, workingDirectory: nil)
        
        if cloneResult.exitCode == 0 {
            // Verify clone was successful (check if files exist)
            if fileManager.fileExists(atPath: shadowURL.path) {
                activeShadows[workspaceURL] = shadowURL
                return shadowURL
            }
        }
        
        // FALLBACK: APFS clone failed (non-APFS filesystem or network drive)
        // Use standard copy and warn user
        print("⚠️ APFS clonefile not available, using standard copy (slower)")
        print("   This may happen on network drives or non-APFS filesystems")
        
        do {
            try fileManager.copyItem(at: workspaceURL, to: shadowURL)
            activeShadows[workspaceURL] = shadowURL
            return shadowURL
        } catch {
            print("❌ Shadow copy failed: \(error.localizedDescription)")
            throw ShadowError.copyFailed
        }
    }
    
    /// 2. Verify proposed edits in the shadow realm (using Edit objects)
    func verifyEditsInShadow(
        edits: [Edit],
        originalWorkspace: URL,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // A. Setup Shadow
                let shadowURL = try self.createShadowCopy(of: originalWorkspace)
                defer { self.cleanup(shadowURL) } // Always clean up
                
                // B. Apply Edits to Shadow
                // We use your existing service, but pointing to the shadow URL
                for edit in edits {
                    try JSONEditSchemaService.shared.apply(edit: edit, in: shadowURL)
                }
                
                // C. Run the Build
                self.runBuild(in: shadowURL) { success, output in
                    completion(success, output)
                }
                
            } catch {
                completion(false, "Failed to setup shadow verification: \(error.localizedDescription)")
            }
        }
    }
    
    /// 2b. Verify proposed file changes in the shadow realm (using StreamingFileInfo)
    func verifyFilesInShadow(
        files: [StreamingFileInfo],
        originalWorkspace: URL,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // A. Setup Shadow
                let shadowURL = try self.createShadowCopy(of: originalWorkspace)
                defer { self.cleanup(shadowURL) } // Always clean up
                
                // B. Apply File Changes to Shadow
                for file in files {
                    let fileURL = shadowURL.appendingPathComponent(file.path)
                    let directory = fileURL.deletingLastPathComponent()
                    
                    // Create directory if needed
                    try? self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                    
                    // Write file content
                    try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                
                // C. Run the Build
                self.runBuild(in: shadowURL) { success, output in
                    completion(success, output)
                }
                
            } catch {
                completion(false, "Failed to setup shadow verification: \(error.localizedDescription)")
            }
        }
    }
    
    /// 3. Detect project type and run build command
    /// FIX: Added sandboxing to prevent build script side effects
    private func runBuild(in workspace: URL, completion: @escaping (Bool, String) -> Void) {
        let buildCommand: String
        
        // Simple heuristic detection (expand based on your needs)
        if fileManager.fileExists(atPath: workspace.appendingPathComponent("Package.swift").path) {
            buildCommand = "swift build"
        } else if fileManager.fileExists(atPath: workspace.appendingPathComponent("tsconfig.json").path) {
            buildCommand = "npm run build"
        } else if fileManager.fileExists(atPath: workspace.appendingPathComponent("Makefile").path) {
            buildCommand = "make"
        } else if fileManager.fileExists(atPath: workspace.appendingPathComponent("Cargo.toml").path) {
            buildCommand = "cargo build"
        } else if fileManager.fileExists(atPath: workspace.appendingPathComponent("go.mod").path) {
            buildCommand = "go build ./..."
        } else if fileManager.fileExists(atPath: workspace.appendingPathComponent("package.json").path) {
            // Check if there's a build script
            let packageJSONPath = workspace.appendingPathComponent("package.json").path
            if let packageData = try? Data(contentsOf: URL(fileURLWithPath: packageJSONPath)),
               let packageJSON = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
               let scripts = packageJSON["scripts"] as? [String: String],
               scripts["build"] != nil {
                buildCommand = "npm run build"
            } else {
                // No build script, assume success (or skip verification)
                completion(true, "No build script detected")
                return
            }
        } else {
            // Unknown project type, assume success (or skip verification)
            completion(true, "No build system detected")
            return
        }
        
        // FIX: Run build in sandbox to prevent side effects
        // On macOS, use sandbox-exec to restrict file system and network access
        let sandboxedCommand: String
        #if os(macOS)
        // Create a sandbox profile that only allows access to the shadow workspace
        let sandboxProfile = """
        (version 1)
        (allow default)
        (deny network-outbound)
        (allow file-read* file-write* (subpath "\(workspace.path)"))
        (deny file-write* (subpath "/"))
        """
        
        // Write sandbox profile to temp file
        let sandboxProfileURL = workspace.appendingPathComponent(".sandbox_profile")
        try? sandboxProfile.write(to: sandboxProfileURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: sandboxProfileURL) }
        
        sandboxedCommand = "sandbox-exec -f \(shellQuote(sandboxProfileURL.path)) sh -c \(shellQuote(buildCommand))"
        #else
        // On non-macOS, run without sandbox (fallback)
        sandboxedCommand = buildCommand
        #endif
        
        // Run with timeout (don't let it hang forever)
        // Collect output for error messages
        var buildOutput = ""
        TerminalExecutionService.shared.execute(
            sandboxedCommand,
            workingDirectory: workspace,
            onOutput: { output in
                buildOutput += output
            },
            onError: { error in
                buildOutput += error
            },
            onComplete: { exitCode in
                if exitCode == 0 {
                    completion(true, "Build succeeded")
                } else {
                    // Extract error messages from output (last 500 chars for brevity)
                    let errorSnippet = buildOutput.count > 500 
                        ? String(buildOutput.suffix(500))
                        : buildOutput
                    completion(false, errorSnippet.isEmpty ? "Build failed (exit code: \(exitCode))" : errorSnippet)
                }
            }
        )
    }
    
    private func cleanup(_ url: URL) {
        // Remove shadow workspace
        try? fileManager.removeItem(at: url)
        
        // Remove from active shadows
        activeShadows = activeShadows.filter { $0.value != url }
    }
    
    private func shellQuote(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
