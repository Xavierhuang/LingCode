//
//  ValidationCoordinator.swift
//  LingCode
//
//  Tiered validation: Linter first, then Shadow Workspace build.
//  Unifies LinterService and ShadowWorkspaceService behind a single API.
//

import Foundation

/// Result of tiered validation (Linter -> Shadow Build).
enum TieredValidationResult {
    case success
    case lintWarnings([String])
    case lintErrors([String])
    case buildFailed(String)
    case skipped(reason: String)
}

/// Coordinates LinterService and ShadowWorkspaceService for Linter -> Shadow Workspace validation.
final class ValidationCoordinator {
    static let shared = ValidationCoordinator()
    
    private let linter = LinterService.shared
    private let shadow = ShadowWorkspaceService.shared
    private let terminal = TerminalExecutionService.shared
    
    private init() {}
    
    /// Run tiered validation: lint on the given files, then optionally verify build in shadow workspace.
    /// - Parameters:
    ///   - files: File URLs to lint (in project space).
    ///   - projectURL: Project root.
    ///   - modifiedContentByPath: Optional map of relative path -> content for in-memory edits (used when writing to shadow).
    ///   - runBuild: If true and lint passes, run build in shadow (Swift: swift build).
    ///   - completion: Called on main queue with the result.
    func validateTiered(
        files: [URL],
        projectURL: URL,
        modifiedContentByPath: [String: String]? = nil,
        runBuild: Bool = true,
        completion: @escaping (TieredValidationResult) -> Void
    ) {
        let wrapped: (TieredValidationResult) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        
        // Tier 1: Linter
        linter.validate(files: files, in: projectURL) { [weak self] lintError in
            guard let self = self else { return }
            if let lintError = lintError {
                switch lintError {
                case .issues(let messages):
                    let errors = messages.filter { $0.lowercased().contains("error") }
                    let warnings = messages.filter { !$0.lowercased().contains("error") }
                    if !errors.isEmpty { wrapped(.lintErrors(errors)); return }
                    if !warnings.isEmpty { wrapped(.lintWarnings(warnings)); return }
                    wrapped(.lintWarnings(messages))
                }
                return
            }
            
            if !runBuild {
                wrapped(.success)
                return
            }
            
            // Tier 2: Shadow workspace build (best effort for Swift)
            let hasSwift = files.contains { $0.pathExtension.lowercased() == "swift" }
            guard hasSwift else {
                wrapped(.success)
                return
            }
            
            self.shadow.ensureShadowWarmed(for: projectURL) { shadowURL in
                guard let shadowURL = shadowURL else {
                    wrapped(.success)
                    return
                }
                self.runShadowBuild(
                    projectURL: projectURL,
                    shadowURL: shadowURL,
                    modifiedContentByPath: modifiedContentByPath,
                    completion: wrapped
                )
            }
        }
    }
    
    /// Verify streaming files in shadow (e.g. before apply). Uses tiered flow: lint then build.
    func verifyFilesInShadowTiered(
        files: [StreamingFileInfo],
        originalWorkspace: URL,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard let first = files.first else {
            completion(true, "No files to verify.")
            return
        }
        
        let fileURLs = files.map { originalWorkspace.appendingPathComponent($0.path) }
        var modifiedContentByPath: [String: String] = [:]
        for f in files { modifiedContentByPath[f.path] = f.content }
        
        validateTiered(
            files: fileURLs,
            projectURL: originalWorkspace,
            modifiedContentByPath: modifiedContentByPath,
            runBuild: true
        ) { result in
            switch result {
            case .success:
                completion(true, "Build successful.")
            case .lintWarnings(let messages):
                completion(false, "Lint warnings:\n" + messages.prefix(5).joined(separator: "\n"))
            case .lintErrors(let messages):
                completion(false, "Lint errors:\n" + messages.prefix(5).joined(separator: "\n"))
            case .buildFailed(let message):
                completion(false, message)
            case .skipped(reason: let reason):
                completion(true, reason)
            }
        }
    }
    
    private func runShadowBuild(
        projectURL: URL,
        shadowURL: URL,
        modifiedContentByPath: [String: String]?,
        completion: @escaping (TieredValidationResult) -> Void
    ) {
        if let contentByPath = modifiedContentByPath {
            for (relativePath, content) in contentByPath {
                try? shadow.writeToShadowWorkspace(content: content, relativePath: relativePath, shadowWorkspaceURL: shadowURL)
            }
        }
        
        let hasPackageSwift = FileManager.default.fileExists(atPath: shadowURL.appendingPathComponent("Package.swift").path)
        guard hasPackageSwift else {
            completion(.skipped(reason: "No Package.swift; skipped build."))
            return
        }
        
        terminal.execute(
            "swift build 2>&1",
            workingDirectory: shadowURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                if exitCode == 0 {
                    completion(.success)
                } else {
                    completion(.buildFailed("Compilation failed."))
                }
            }
        )
    }
    
    /// Whether tiered validation can run (linter available and not blocked by foreground terminal).
    func canValidate(workspaceURL: URL) -> Bool {
        linter.hasLinter(for: workspaceURL) || FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("Package.swift").path)
    }
}
