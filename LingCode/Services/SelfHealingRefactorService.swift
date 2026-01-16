//
//  SelfHealingRefactorService.swift
//  LingCode
//
//  Self-healing refactors with closed-loop diagnostics and repair
//

import Foundation

// Use shared Diagnostic from LSPDiagnosticsObserver
// Note: Diagnostic is defined in LSPDiagnosticsObserver.swift as a top-level struct

struct RefactorResult {
    let success: Bool
    let appliedEdits: [Edit]
    let diagnostics: [Diagnostic]
    let testResults: TestResults?
    let repairAttempts: Int
    let error: Error?
}

struct TestResults {
    let passed: Int
    let failed: Int
    let errors: [String]
}

class SelfHealingRefactorService {
    static let shared = SelfHealingRefactorService()
    
    private let maxRepairAttempts = 3
    private let atomicEditService = AtomicEditService.shared
    private let localModelService = LocalModelService.shared
    
    private init() {}
    
    /// Apply refactor with self-healing loop
    func applyRefactor(
        edits: [Edit],
        in workspaceURL: URL,
        runTests: Bool = true,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (RefactorResult) -> Void
    ) {
        var repairAttempts = 0
        var currentEdits = edits
        
        func attemptApply() {
            onProgress("Applying refactor...")
            
            // Apply edits atomically
            atomicEditService.applyEdits(
                currentEdits,
                in: workspaceURL,
                onProgress: { message in
                    onProgress(message)
                },
                onComplete: { appliedFiles in
                    // Run diagnostics
                    onProgress("Running diagnostics...")
                    let diagnostics = self.runDiagnostics(in: workspaceURL)
                    
                    // Check for errors
                    let errors = diagnostics.filter { $0.severity == .error }
                    if !errors.isEmpty {
                        // Try to repair
                        if repairAttempts < self.maxRepairAttempts {
                            repairAttempts += 1
                            onProgress("Repairing errors (attempt \(repairAttempts)/\(self.maxRepairAttempts))...")
                            
                            self.repairErrors(
                                errors: errors,
                                originalEdits: currentEdits,
                                in: workspaceURL
                            ) { repairEdits in
                                if let repairEdits = repairEdits, !repairEdits.isEmpty {
                                    currentEdits = repairEdits
                                    attemptApply() // Retry
                                } else {
                                    // Repair failed - rollback
                                    self.rollback(in: workspaceURL)
                                    onComplete(RefactorResult(
                                        success: false,
                                        appliedEdits: [],
                                        diagnostics: diagnostics,
                                        testResults: nil,
                                        repairAttempts: repairAttempts,
                                        error: NSError(domain: "SelfHealing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Repair failed after \(repairAttempts) attempts"])
                                    ))
                                }
                            }
                        } else {
                            // Max attempts reached - rollback
                            self.rollback(in: workspaceURL)
                            onComplete(RefactorResult(
                                success: false,
                                appliedEdits: [],
                                diagnostics: diagnostics,
                                testResults: nil,
                                repairAttempts: repairAttempts,
                                error: NSError(domain: "SelfHealing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Max repair attempts reached"])
                            ))
                        }
                        return
                    }
                    
                    // Run tests if requested
                    var testResults: TestResults? = nil
                    if runTests {
                        onProgress("Running tests...")
                        testResults = self.runTests(in: workspaceURL)
                        
                        if let results = testResults, results.failed > 0 {
                            // Tests failed - try to repair
                            if repairAttempts < self.maxRepairAttempts {
                                repairAttempts += 1
                                onProgress("Repairing test failures (attempt \(repairAttempts)/\(self.maxRepairAttempts))...")
                                
                                self.repairTestFailures(
                                    testResults: results,
                                    originalEdits: currentEdits,
                                    in: workspaceURL
                                ) { repairEdits in
                                    if let repairEdits = repairEdits, !repairEdits.isEmpty {
                                        currentEdits = repairEdits
                                        attemptApply() // Retry
                                    } else {
                                        // Repair failed
                                        onComplete(RefactorResult(
                                            success: false,
                                            appliedEdits: currentEdits,
                                            diagnostics: diagnostics,
                                            testResults: results,
                                            repairAttempts: repairAttempts,
                                            error: NSError(domain: "SelfHealing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Test repair failed"])
                                        ))
                                    }
                                }
                                return
                            }
                        }
                    }
                    
                    // Success!
                    onComplete(RefactorResult(
                        success: true,
                        appliedEdits: currentEdits,
                        diagnostics: diagnostics,
                        testResults: testResults,
                        repairAttempts: repairAttempts,
                        error: nil
                    ))
                },
                onError: { error in
                    // Rollback on error
                    self.rollback(in: workspaceURL)
                    onComplete(RefactorResult(
                        success: false,
                        appliedEdits: [],
                        diagnostics: [],
                        testResults: nil,
                        repairAttempts: repairAttempts,
                        error: error
                    ))
                }
            )
        }
        
        attemptApply()
    }
    
    /// Repair errors using local model
    private func repairErrors(
        errors: [Diagnostic],
        originalEdits: [Edit],
        in workspaceURL: URL,
        completion: @escaping ([Edit]?) -> Void
    ) {
        // Build repair prompt
        let errorMessages = errors.map { "\($0.filePath.lastPathComponent):\($0.line): \($0.message)" }.joined(separator: "\n")
        
        // Build repair prompt (for future use with local model)
        _ = """
        The previous refactor introduced these errors:
        
        \(errorMessages)
        
        Fix ONLY the errors.
        Do not change unrelated code.
        Return structured edits in JSON format.
        
        Previous edits:
        \(formatEditsAsJSON(originalEdits))
        """
        
        // Use local model (Qwen 7B) for repair (for future use)
        _ = localModelService.selectModel(for: .debug, requiresReasoning: false)
        
        // Placeholder - would call local model API
        // For now, return nil (would implement actual repair)
        completion(nil)
    }
    
    /// Repair test failures
    private func repairTestFailures(
        testResults: TestResults,
        originalEdits: [Edit],
        in workspaceURL: URL,
        completion: @escaping ([Edit]?) -> Void
    ) {
        let errorMessages = testResults.errors.joined(separator: "\n")
        
        // Build repair prompt (for future use with local model)
        _ = """
        The previous refactor caused test failures:
        
        \(errorMessages)
        
        Fix ONLY the test failures.
        Do not change unrelated code.
        Return structured edits in JSON format.
        
        Previous edits:
        \(formatEditsAsJSON(originalEdits))
        """
        
        // Use local model for repair (for future use)
        _ = localModelService.selectModel(for: .debug, requiresReasoning: false)
        
        // Placeholder - would call local model API
        completion(nil)
    }
    
    /// Run diagnostics using swift build (SourceKit-LSP integration)
    private func runDiagnostics(in workspaceURL: URL) -> [Diagnostic] {
        // Run swift build and capture stderr
        let terminalService = TerminalExecutionService.shared
        let result = terminalService.executeSync(
            "swift build 2>&1",
            workingDirectory: workspaceURL
        )
        
        // Parse compiler output for errors
        var diagnostics: [Diagnostic] = []
        let lines = result.output.components(separatedBy: .newlines)
        
        for line in lines {
            // Parse Swift compiler error format: "file.swift:line:column: error: message"
            if let diagnostic = parseCompilerError(line, in: workspaceURL) {
                diagnostics.append(diagnostic)
            }
        }
        
        return diagnostics
    }
    
    /// Parse Swift compiler error line
    private func parseCompilerError(_ line: String, in workspaceURL: URL) -> Diagnostic? {
        // Pattern: "file.swift:line:column: error: message"
        let pattern = #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }
        
        guard let fileRange = Range(match.range(at: 1), in: line),
              let lineRange = Range(match.range(at: 2), in: line),
              let columnRange = Range(match.range(at: 3), in: line),
              let severityRange = Range(match.range(at: 4), in: line),
              let messageRange = Range(match.range(at: 5), in: line) else {
            return nil
        }
        
        let filePath = String(line[fileRange])
        let lineNumber = Int(String(line[lineRange])) ?? 0
        let columnNumber = Int(String(line[columnRange])) ?? 0
        let severityString = String(line[severityRange])
        let message = String(line[messageRange])
        
        // Resolve file path
        let fileURL: URL
        if filePath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: filePath)
        } else {
            fileURL = workspaceURL.appendingPathComponent(filePath)
        }
        
        let severity: Diagnostic.DiagnosticSeverity = severityString == "error" ? .error : .warning
        
        return Diagnostic(
            filePath: fileURL,
            line: lineNumber,
            column: columnNumber,
            severity: severity,
            message: message,
            code: nil
        )
    }
    
    /// Run tests
    private func runTests(in workspaceURL: URL) -> TestResults? {
        // Placeholder - would run actual tests
        // For now, return nil
        return nil
    }
    
    /// Rollback changes
    private func rollback(in workspaceURL: URL) {
        // Would restore from snapshot
        // Placeholder
    }
    
    /// Format edits as JSON
    private func formatEditsAsJSON(_ edits: [Edit]) -> String {
        let schema = EditSchema(edits: edits)
        if let jsonData = try? JSONEncoder().encode(schema),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "[]"
    }
}
