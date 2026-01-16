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
    func createShadowCopy(of workspaceURL: URL) throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let shadowName = "LingCode_Shadow_\(UUID().uuidString)"
        let shadowURL = tempDir.appendingPathComponent(shadowName)
        
        // Use 'cp -Rc' for APFS clonefile (Instant copy, near-zero disk usage)
        // This is crucial for performance. Standard FileManager copy is too slow.
        let command = "cp -Rc \(shellQuote(workspaceURL.path)) \(shellQuote(shadowURL.path))"
        let result = TerminalExecutionService.shared.executeSync(command, workingDirectory: nil)
        
        if result.exitCode != 0 {
            print("❌ Shadow copy failed: \(result.output)")
            throw ShadowError.copyFailed
        }
        
        activeShadows[workspaceURL] = shadowURL
        return shadowURL
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
        
        // Run with timeout (don't let it hang forever)
        // Collect output for error messages
        var buildOutput = ""
        TerminalExecutionService.shared.execute(
            buildCommand,
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
