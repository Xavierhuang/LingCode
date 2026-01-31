//
//  AgentValidationService.swift
//  LingCode
//
//  Standalone validation after agent file writes (lint, Swift compilation).
//

import Foundation

enum AgentValidationResult {
    case success
    case warnings([String])
    case errors([String])
    case skipped
}

@MainActor
final class AgentValidationService {
    static let shared = AgentValidationService()
    
    private let shadowService = ShadowWorkspaceService.shared
    private let linterService = LinterService.shared
    private let terminalService = TerminalExecutionService.shared
    
    private init() {}
    
    func validateCodeAfterWrite(fileURL: URL, projectURL: URL, completion: @escaping (AgentValidationResult) -> Void) {
        guard let shadowWorkspaceURL = shadowService.getShadowWorkspace(for: projectURL) ?? shadowService.createShadowWorkspace(for: projectURL) else {
            validateCodeDirectly(fileURL: fileURL, projectURL: projectURL, completion: completion)
            return
        }
        
        guard let modifiedContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            completion(.errors(["Failed to read modified file content"]))
            return
        }
        
        let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
        
        do {
            try shadowService.prepareShadowWorkspaceForValidation(modifiedFileURL: fileURL, projectURL: projectURL, shadowWorkspaceURL: shadowWorkspaceURL)
            try shadowService.writeToShadowWorkspace(content: modifiedContent, relativePath: relativePath, shadowWorkspaceURL: shadowWorkspaceURL)
            let shadowFileURL = shadowWorkspaceURL.appendingPathComponent(relativePath)
            validateCodeInShadowWorkspace(fileURL: shadowFileURL, shadowWorkspaceURL: shadowWorkspaceURL, originalProjectURL: projectURL, completion: completion)
        } catch {
            validateCodeDirectly(fileURL: fileURL, projectURL: projectURL, completion: completion)
        }
    }
    
    private func validateCodeDirectly(fileURL: URL, projectURL: URL, completion: @escaping (AgentValidationResult) -> Void) {
        linterService.validate(files: [fileURL], in: projectURL) { lintError in
            if let lintError = lintError {
                switch lintError {
                case .issues(let messages):
                    let errors = messages.filter { $0.lowercased().contains("error") }
                    let warnings = messages.filter { !$0.lowercased().contains("error") }
                    if !errors.isEmpty { completion(.errors(errors)) }
                    else if !warnings.isEmpty { completion(.warnings(warnings)) }
                    else { completion(.success) }
                }
            } else if fileURL.pathExtension.lowercased() == "swift" {
                self.validateSwiftCompilation(projectURL: projectURL, completion: completion)
            } else {
                completion(.success)
            }
        }
    }
    
    private func validateCodeInShadowWorkspace(fileURL: URL, shadowWorkspaceURL: URL, originalProjectURL: URL, completion: @escaping (AgentValidationResult) -> Void) {
        linterService.validate(files: [fileURL], in: shadowWorkspaceURL) { lintError in
            if let lintError = lintError {
                switch lintError {
                case .issues(let messages):
                    let errors = messages.filter { $0.lowercased().contains("error") }
                    let warnings = messages.filter { !$0.lowercased().contains("error") }
                    if !errors.isEmpty { completion(.errors(errors)) }
                    else if !warnings.isEmpty { completion(.warnings(warnings)) }
                    else { completion(.success) }
                }
            } else if fileURL.pathExtension.lowercased() == "swift" {
                self.validateSwiftCompilationInShadow(shadowWorkspaceURL: shadowWorkspaceURL, completion: completion)
            } else {
                completion(.success)
            }
        }
    }
    
    private func validateSwiftCompilation(projectURL: URL, completion: @escaping (AgentValidationResult) -> Void) {
        let hasPackageSwift = FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path)
        guard hasPackageSwift else { completion(.skipped); return }
        
        terminalService.execute(
            "swift build 2>&1",
            workingDirectory: projectURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                completion(exitCode == 0 ? .success : .errors(["Compilation failed."]))
            }
        )
    }
    
    private func validateSwiftCompilationInShadow(shadowWorkspaceURL: URL, completion: @escaping (AgentValidationResult) -> Void) {
        let hasPackageSwift = FileManager.default.fileExists(atPath: shadowWorkspaceURL.appendingPathComponent("Package.swift").path)
        guard hasPackageSwift else { completion(.skipped); return }
        
        terminalService.execute(
            "swift build 2>&1",
            workingDirectory: shadowWorkspaceURL,
            environment: nil,
            onOutput: { _ in },
            onError: { _ in },
            onComplete: { exitCode in
                completion(exitCode == 0 ? .success : .errors(["Compilation failed in shadow workspace."]))
            }
        )
    }
}
