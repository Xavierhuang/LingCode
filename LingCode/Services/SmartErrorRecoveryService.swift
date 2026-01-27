//
//  SmartErrorRecoveryService.swift
//  LingCode
//
//  Smart error recovery with context-aware auto-fixes
//

import Foundation
import Combine

struct ErrorRecoverySuggestion: Identifiable {
    let id = UUID()
    let error: Error
    let suggestion: String
    let confidence: Double
    let autoFixable: Bool
    let fixCode: String?
    let context: String
}

@MainActor
class SmartErrorRecoveryService: ObservableObject {
    static let shared = SmartErrorRecoveryService()
    
    @Published var recoveryHistory: [ErrorRecoverySuggestion] = []
    @Published var learnedPatterns: [String: [String]] = [:] // error pattern -> fixes
    
    private let aiService = AIService.shared
    
    private init() {}
    
    /// Analyze error and suggest recovery
    func analyzeError(
        _ error: Error,
        context: String,
        filePath: String?,
        code: String?,
        completion: @escaping (Result<ErrorRecoverySuggestion, Error>) -> Void
    ) {
        // Check learned patterns first
        let errorPattern = extractErrorPattern(error)
        if let learnedFixes = learnedPatterns[errorPattern], !learnedFixes.isEmpty {
            let suggestion = ErrorRecoverySuggestion(
                error: error,
                suggestion: learnedFixes.first!,
                confidence: 0.8,
                autoFixable: true,
                fixCode: nil,
                context: context
            )
            completion(.success(suggestion))
            return
        }
        
        // Use AI to analyze error
        let prompt = """
        Analyze this error and suggest a fix:
        
        Error: \(error.localizedDescription)
        
        Context: \(context)
        
        \(filePath != nil ? "File: \(filePath!)" : "")
        
        \(code != nil ? "Code:\n```\n\(code!)\n```" : "")
        
        Provide:
        1. A clear explanation of the error
        2. A specific fix suggestion
        3. Whether the fix can be auto-applied
        4. If auto-fixable, provide the fix code
        
        Format:
        EXPLANATION: [explanation]
        SUGGESTION: [suggestion]
        AUTO_FIXABLE: [yes/no]
        FIX_CODE: [code if auto-fixable]
        """
        
        aiService.sendMessage(prompt, context: nil) { [weak self] response in
            DispatchQueue.main.async {
                let suggestion = self?.parseRecoveryResponse(response, error: error, context: context)
                if let suggestion = suggestion {
                    self?.recoveryHistory.append(suggestion)
                    self?.learnPattern(error: error, fix: suggestion.suggestion)
                    completion(.success(suggestion))
                } else {
                    completion(.failure(NSError(domain: "ErrorRecovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse recovery suggestion"])))
                }
            }
        } onError: { error in
            completion(.failure(error))
        }
    }
    
    /// Parse AI recovery response
    private func parseRecoveryResponse(_ response: String, error: Error, context: String) -> ErrorRecoverySuggestion? {
        var explanation = ""
        var suggestion = ""
        var autoFixable = false
        var fixCode: String? = nil
        
        // Parse explanation
        if let range = response.range(of: #"EXPLANATION:\s*(.+?)(?:\n|SUGGESTION:)"#, options: .regularExpression) {
            explanation = String(response[range]).replacingOccurrences(of: "EXPLANATION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse suggestion
        if let range = response.range(of: #"SUGGESTION:\s*(.+?)(?:\n|AUTO_FIXABLE:)"#, options: .regularExpression) {
            suggestion = String(response[range]).replacingOccurrences(of: "SUGGESTION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse auto-fixable
        if let range = response.range(of: #"AUTO_FIXABLE:\s*(yes|no)"#, options: .regularExpression) {
            let value = String(response[range]).replacingOccurrences(of: "AUTO_FIXABLE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            autoFixable = value.lowercased() == "yes"
        }
        
        // Parse fix code
        if autoFixable {
            // Use NSRegularExpression for multiline matching
            let pattern = #"FIX_CODE:\s*```(?:.*?)?\n(.*?)```"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: response) {
                fixCode = String(response[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        if suggestion.isEmpty {
            suggestion = explanation.isEmpty ? "Please review the error and fix manually." : explanation
        }
        
        return ErrorRecoverySuggestion(
            error: error,
            suggestion: suggestion,
            confidence: autoFixable ? 0.7 : 0.5,
            autoFixable: autoFixable,
            fixCode: fixCode,
            context: context
        )
    }
    
    /// Extract error pattern for learning
    private func extractErrorPattern(_ error: Error) -> String {
        let description = error.localizedDescription.lowercased()
        
        // Common patterns
        if description.contains("syntax") { return "syntax_error" }
        if description.contains("undefined") { return "undefined_reference" }
        if description.contains("type") { return "type_mismatch" }
        if description.contains("null") || description.contains("nil") { return "null_reference" }
        if description.contains("permission") { return "permission_denied" }
        if description.contains("not found") { return "not_found" }
        
        return "generic_error"
    }
    
    /// Learn from successful fixes
    private func learnPattern(error: Error, fix: String) {
        let pattern = extractErrorPattern(error)
        if learnedPatterns[pattern] == nil {
            learnedPatterns[pattern] = []
        }
        learnedPatterns[pattern]?.append(fix)
        
        // Keep only last 5 fixes per pattern
        if let fixes = learnedPatterns[pattern], fixes.count > 5 {
            learnedPatterns[pattern] = Array(fixes.suffix(5))
        }
    }
}
