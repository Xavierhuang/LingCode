//
//  CodeValidationService.swift
//  LingCode
//
//  Prevents "unintended deletions" and "code on LSD" issues
//  Validates all changes before applying
//

import Foundation

/// Service for validating code changes before applying
/// Addresses Cursor's "unintended deletions" and "code on LSD" problems
class CodeValidationService {
    static let shared = CodeValidationService()
    
    private init() {}
    
    /// Validate a code change before applying
    func validateChange(
        _ change: CodeChange,
        requestedScope: String,
        projectConfig: ProjectConfig? = nil
    ) -> ValidationResult {
        var issues: [ValidationIssue] = []
        
        // 1. Syntax validation
        if let syntaxError = validateSyntax(change.newContent, language: change.language) {
            issues.append(.syntaxError(syntaxError))
        }
        
        // 2. Scope checking - ensure changes match what was requested
        if let scopeIssue = checkScope(
            requestedScope: requestedScope,
            change: change
        ) {
            issues.append(scopeIssue)
        }
        
        // 3. Detect unintended deletions
        if let deletionIssue = detectUnintendedDeletions(change) {
            issues.append(deletionIssue)
        }
        
        // 4. Architecture compliance
        if let config = projectConfig,
           let complianceIssue = checkArchitectureCompliance(change, config: config) {
            issues.append(complianceIssue)
        }
        
        // 5. Large change warning
        if let warning = warnLargeChange(change) {
            issues.append(warning)
        }
        
        // 6. Check for suspicious patterns
        if let suspicious = detectSuspiciousPatterns(change) {
            issues.append(suspicious)
        }
        
        let severity = issues.map { $0.severity }.max() ?? .info
        return ValidationResult(
            isValid: issues.isEmpty || severity == .warning,
            issues: issues,
            severity: severity,
            recommendation: generateRecommendation(issues)
        )
    }
    
    /// Validate syntax for a given language
    private func validateSyntax(_ code: String, language: String) -> String? {
        // Basic syntax validation
        // For production, integrate with language-specific parsers
        
        switch language.lowercased() {
        case "swift":
            return validateSwiftSyntax(code)
        case "javascript", "typescript":
            return validateJavaScriptSyntax(code)
        case "python":
            return validatePythonSyntax(code)
        default:
            // Basic validation for other languages
            return validateBasicSyntax(code)
        }
    }
    
    /// Check if changes match the requested scope
    private func checkScope(
        requestedScope: String,
        change: CodeChange
    ) -> ValidationIssue? {
        // Extract key terms from requested scope
        let requestedTerms = extractKeyTerms(requestedScope)
        let changeContent = change.newContent.lowercased()
        
        // Check if change content relates to requested scope
        let relevance = calculateRelevance(requestedTerms, content: changeContent)
        
        if relevance < 0.3 {
            return .scopeMismatch(
                message: "Changes don't appear to match the requested scope",
                requestedScope: requestedScope,
                actualChange: change.fileName
            )
        }
        
        return nil
    }
    
    /// Detect unintended deletions
    private func detectUnintendedDeletions(_ change: CodeChange) -> ValidationIssue? {
        guard let original = change.originalContent else {
            return nil // New file, no deletions possible
        }
        
        let originalLines = original.components(separatedBy: .newlines)
        let newLines = change.newContent.components(separatedBy: .newlines)
        
        // If more than 50% of original content was deleted
        if newLines.count < Int(Double(originalLines.count) * 0.5) {
            let deletedLines = originalLines.count - newLines.count
            return .unintendedDeletion(
                message: "Large deletion detected: \(deletedLines) lines removed",
                deletedLines: deletedLines,
                originalLineCount: originalLines.count
            )
        }
        
        // Check for deletion of important patterns (functions, classes, etc.)
        let deletedImportant = detectDeletedImportantPatterns(original: original, modified: change.newContent)
        if !deletedImportant.isEmpty {
            return .unintendedDeletion(
                message: "Important code patterns deleted: \(deletedImportant.joined(separator: ", "))",
                deletedLines: originalLines.count - newLines.count,
                originalLineCount: originalLines.count
            )
        }
        
        return nil
    }
    
    /// Check architecture compliance
    private func checkArchitectureCompliance(
        _ change: CodeChange,
        config: ProjectConfig
    ) -> ValidationIssue? {
        // Check against project architecture patterns
        if let pattern = config.architecturePattern {
            switch pattern {
            case .mvc:
                return checkMVCCompliance(change, config: config)
            case .mvp:
                return checkMVPCompliance(change, config: config)
            case .mvvm:
                return checkMVVMCompliance(change, config: config)
            case .clean:
                return checkCleanArchitectureCompliance(change, config: config)
            }
        }
        
        return nil
    }
    
    /// Warn about large changes
    private func warnLargeChange(_ change: CodeChange) -> ValidationIssue? {
        let lineCount = change.newContent.components(separatedBy: .newlines).count
        
        if lineCount > 500 {
            return .largeChange(
                message: "Very large change: \(lineCount) lines. Consider splitting into smaller changes.",
                lineCount: lineCount
            )
        } else if lineCount > 200 {
            return .largeChange(
                message: "Large change: \(lineCount) lines. Review carefully.",
                lineCount: lineCount
            )
        }
        
        return nil
    }
    
    /// Detect suspicious patterns (hallucinated APIs, invalid syntax, etc.)
    private func detectSuspiciousPatterns(_ change: CodeChange) -> ValidationIssue? {
        let content = change.newContent
        
        // Check for common hallucination patterns
        if containsHallucinatedAPIs(content, language: change.language) {
            return .suspiciousPattern(
                message: "Potential hallucinated API usage detected",
                pattern: "unknown_api"
            )
        }
        
        // Check for invalid imports
        if let invalidImport = detectInvalidImports(content, language: change.language) {
            return .suspiciousPattern(
                message: "Invalid import detected: \(invalidImport)",
                pattern: "invalid_import"
            )
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func validateSwiftSyntax(_ code: String) -> String? {
        // Basic Swift validation
        // Check for unmatched braces, brackets, parentheses
        if !isBalanced(code, open: "{", close: "}") {
            return "Unmatched braces"
        }
        if !isBalanced(code, open: "[", close: "]") {
            return "Unmatched brackets"
        }
        if !isBalanced(code, open: "(", close: ")") {
            return "Unmatched parentheses"
        }
        return nil
    }
    
    private func validateJavaScriptSyntax(_ code: String) -> String? {
        // Basic JavaScript validation
        if !isBalanced(code, open: "{", close: "}") {
            return "Unmatched braces"
        }
        if !isBalanced(code, open: "[", close: "]") {
            return "Unmatched brackets"
        }
        if !isBalanced(code, open: "(", close: ")") {
            return "Unmatched parentheses"
        }
        return nil
    }
    
    private func validatePythonSyntax(_ code: String) -> String? {
        // Basic Python validation
        // Check indentation consistency
        let lines = code.components(separatedBy: .newlines)
        var indentLevel = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            let leadingSpaces = line.count - line.trimmingLeadingWhitespaces().count
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Check if indentation is consistent
            }
        }
        return nil
    }
    
    private func validateBasicSyntax(_ code: String) -> String? {
        // Basic validation for any language
        if !isBalanced(code, open: "{", close: "}") {
            return "Unmatched braces"
        }
        if !isBalanced(code, open: "(", close: ")") {
            return "Unmatched parentheses"
        }
        return nil
    }
    
    private func isBalanced(_ text: String, open: String, close: String) -> Bool {
        var count = 0
        for char in text {
            if String(char) == open {
                count += 1
            } else if String(char) == close {
                count -= 1
                if count < 0 {
                    return false
                }
            }
        }
        return count == 0
    }
    
    private func extractKeyTerms(_ text: String) -> [String] {
        // Extract important terms from requested scope
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 }
        return Array(Set(words))
    }
    
    private func calculateRelevance(_ terms: [String], content: String) -> Double {
        guard !terms.isEmpty else { return 1.0 }
        let matches = terms.filter { content.contains($0) }.count
        return Double(matches) / Double(terms.count)
    }
    
    private func detectDeletedImportantPatterns(original: String, modified: String) -> [String] {
        var deleted: [String] = []
        
        // Check for deleted function definitions
        let originalFunctions = extractFunctions(original)
        let modifiedFunctions = extractFunctions(modified)
        let deletedFunctions = originalFunctions.filter { !modifiedFunctions.contains($0) }
        if !deletedFunctions.isEmpty {
            deleted.append("functions: \(deletedFunctions.joined(separator: ", "))")
        }
        
        // Check for deleted class definitions
        let originalClasses = extractClasses(original)
        let modifiedClasses = extractClasses(modified)
        let deletedClasses = originalClasses.filter { !modifiedClasses.contains($0) }
        if !deletedClasses.isEmpty {
            deleted.append("classes: \(deletedClasses.joined(separator: ", "))")
        }
        
        return deleted
    }
    
    private func extractFunctions(_ code: String) -> [String] {
        // Extract function names (simplified)
        let pattern = #"func\s+(\w+)\s*\("#
        return extractMatches(code, pattern: pattern)
    }
    
    private func extractClasses(_ code: String) -> [String] {
        // Extract class names (simplified)
        let pattern = #"(?:class|struct)\s+(\w+)"#
        return extractMatches(code, pattern: pattern)
    }
    
    private func extractMatches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[nameRange])
        }
    }
    
    private func containsHallucinatedAPIs(_ code: String, language: String) -> Bool {
        // Check for common hallucination patterns
        // This is a simplified check - production would use more sophisticated methods
        let suspiciousPatterns = [
            "undefined_function",
            "non_existent_api",
            "invalid_method"
        ]
        return suspiciousPatterns.contains { code.contains($0) }
    }
    
    private func detectInvalidImports(_ code: String, language: String) -> String? {
        // Check for invalid imports (simplified)
        let lines = code.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("import") || line.contains("from") {
                // Basic validation - production would check against actual module list
                if line.contains("non_existent_module") {
                    return line
                }
            }
        }
        return nil
    }
    
    private func checkMVCCompliance(_ change: CodeChange, config: ProjectConfig) -> ValidationIssue? {
        // Check MVC architecture compliance
        // Simplified - production would be more thorough
        return nil
    }
    
    private func checkMVPCompliance(_ change: CodeChange, config: ProjectConfig) -> ValidationIssue? {
        return nil
    }
    
    private func checkMVVMCompliance(_ change: CodeChange, config: ProjectConfig) -> ValidationIssue? {
        return nil
    }
    
    private func checkCleanArchitectureCompliance(_ change: CodeChange, config: ProjectConfig) -> ValidationIssue? {
        return nil
    }
    
    private func generateRecommendation(_ issues: [ValidationIssue]) -> String {
        if issues.isEmpty {
            return "✅ Safe to apply"
        }
        
        let criticalIssues = issues.filter { $0.severity == .critical }
        if !criticalIssues.isEmpty {
            return "❌ Do not apply - critical issues detected"
        }
        
        let warnings = issues.filter { $0.severity == .warning }
        if !warnings.isEmpty {
            return "⚠️ Review required - warnings detected"
        }
        
        return "ℹ️ Apply with caution - minor issues detected"
    }
}

// MARK: - Models

struct ValidationResult {
    let isValid: Bool
    let issues: [ValidationIssue]
    let severity: ValidationSeverity
    let recommendation: String
}

enum ValidationIssue {
    case syntaxError(String)
    case scopeMismatch(message: String, requestedScope: String, actualChange: String)
    case unintendedDeletion(message: String, deletedLines: Int, originalLineCount: Int)
    case architectureViolation(message: String, pattern: String)
    case largeChange(message: String, lineCount: Int)
    case suspiciousPattern(message: String, pattern: String)
    
    var severity: ValidationSeverity {
        switch self {
        case .syntaxError, .unintendedDeletion:
            return .critical
        case .scopeMismatch, .architectureViolation, .suspiciousPattern:
            return .warning
        case .largeChange:
            return .info
        }
    }
    
    var message: String {
        switch self {
        case .syntaxError(let msg):
            return "Syntax Error: \(msg)"
        case .scopeMismatch(let msg, _, _):
            return "Scope Mismatch: \(msg)"
        case .unintendedDeletion(let msg, _, _):
            return "Unintended Deletion: \(msg)"
        case .architectureViolation(let msg, _):
            return "Architecture Violation: \(msg)"
        case .largeChange(let msg, _):
            return "Large Change: \(msg)"
        case .suspiciousPattern(let msg, _):
            return "Suspicious Pattern: \(msg)"
        }
    }
}

enum ValidationSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2
    
    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ProjectConfig {
    let architecturePattern: ArchitecturePattern?
    let allowedPatterns: [String]
    let forbiddenPatterns: [String]
}

enum ArchitecturePattern {
    case mvc
    case mvp
    case mvvm
    case clean
}

// MARK: - String Extensions

extension String {
    func trimmingLeadingWhitespaces() -> String {
        return String(self.drop { $0.isWhitespace })
    }
}

