import Foundation

// OPTIMIZED VALIDATOR: No @MainActor, no regex loops
final class EditOutputValidator {
    static let shared = EditOutputValidator()
    
    private init() {}
    
    enum ValidationResult {
        case valid
        case recovered(String)
        case invalidFormat(reason: String)
        case noOp
        case silentFailure
    }
    
    func validateEditOutput(_ content: String) -> ValidationResult {
        // 1. Fast empty check
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .silentFailure
        }
        
        // 2. Fast No-Op check
        if isNoOp(content) { return .noOp }
        
        // 3. Check for forbidden content (Fast String Check)
        if hasForbiddenContent(content) {
            let recovered = stripGarbage(from: content)
            if recovered.isEmpty { return .noOp }
            return .recovered(recovered)
        }
        
        // 4. Check for code blocks (Fast Check)
        if !content.contains("```") {
            if content.count < 50 {
                return .invalidFormat(reason: "Response contains no file edits (invalid format)")
            }
            return .invalidFormat(reason: "Response contains no executable file edits")
        }
        
        return .valid
    }
    
    private func isNoOp(_ content: String) -> Bool {
        if content.contains("\"noop\"") || content.contains("'noop'") { return true }
        if content.count < 200 {
            let lower = content.lowercased()
            if lower.contains("no changes needed") || lower.contains("no changes required") { return true }
        }
        return false
    }
    
    private func hasForbiddenContent(_ content: String) -> Bool {
        let lower = content.lowercased()
        let forbiddenPhrases = ["thinking process", "here's what", "i'll update", "i will", "summary:", "explanation:", "reasoning:", "analysis:"]
        
        for phrase in forbiddenPhrases {
            if lower.contains(phrase) {
                if !isInCodeBlock(content: content, phrase: phrase) {
                    return true
                }
            }
        }
        return false
    }
    
    private func stripGarbage(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return false }
            return true
        }.joined(separator: "\n")
    }
    
    private func isInCodeBlock(content: String, phrase: String) -> Bool {
        guard let range = content.range(of: phrase, options: .caseInsensitive) else { return false }
        let prefix = content[..<range.lowerBound]
        let backtickCount = prefix.filter { $0 == "`" }.count
        return backtickCount % 2 != 0
    }
}