//
//  RefactoringService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

enum RefactoringType: String, CaseIterable {
    case extractMethod = "Extract Method"
    case extractVariable = "Extract Variable"
    case inline = "Inline"
    case rename = "Rename"
    case simplify = "Simplify"
    case optimize = "Optimize"
    case addErrorHandling = "Add Error Handling"
    case convertToAsync = "Convert to Async/Await"
    case addDocumentation = "Add Documentation"
    
    var description: String {
        switch self {
        case .extractMethod: return "Extract selected code into a new method"
        case .extractVariable: return "Extract expression into a variable"
        case .inline: return "Inline variable or method"
        case .rename: return "Rename symbol with smart renaming"
        case .simplify: return "Simplify complex code"
        case .optimize: return "Optimize for performance"
        case .addErrorHandling: return "Add proper error handling"
        case .convertToAsync: return "Convert to async/await pattern"
        case .addDocumentation: return "Add documentation comments"
        }
    }
}

struct RefactoringSuggestion: Identifiable {
    let id = UUID()
    let type: RefactoringType
    let description: String
    let originalCode: String
    let refactoredCode: String
    let affectedFiles: [URL]
    let confidence: Double
}

struct RefactoringPreview {
    let originalCode: String
    let refactoredCode: String
    let changes: [RefactoringCodeChange]
    let affectedFiles: [URL]
}

struct RefactoringCodeChange {
    let file: URL
    let line: Int
    let original: String
    let modified: String
}

class RefactoringService {
    static let shared = RefactoringService()
    
    private init() {}
    
    func suggestRefactoring(
        for code: String,
        type: RefactoringType? = nil,
        language: String? = nil
    ) async throws -> [RefactoringSuggestion] {
        let prompt = buildRefactoringPrompt(code: code, type: type, language: language)
        
        // Use AI to suggest refactoring
        return await generateRefactoringSuggestions(prompt: prompt, code: code, type: type)
    }
    
    func previewRefactoring(
        suggestion: RefactoringSuggestion
    ) async throws -> RefactoringPreview {
        // Generate detailed preview with all changes
        return await generatePreview(for: suggestion)
    }
    
    func applyRefactoring(
        preview: RefactoringPreview,
        in files: [URL]
    ) async throws {
        // Apply the refactoring changes
        for change in preview.changes {
            try await applyChange(change, in: change.file)
        }
    }
    
    private func buildRefactoringPrompt(
        code: String,
        type: RefactoringType?,
        language: String?
    ) -> String {
        var prompt = "Analyze this code and suggest refactoring improvements:\n\n"
        prompt += "```\(language ?? "swift")\n\(code)\n```\n\n"
        
        if let type = type {
            prompt += "Specifically, suggest: \(type.rawValue)\n"
            prompt += "Description: \(type.description)\n\n"
        } else {
            prompt += "Suggest the most impactful refactoring improvements.\n\n"
        }
        
        prompt += "For each suggestion, provide:\n"
        prompt += "1. Type of refactoring\n"
        prompt += "2. Refactored code\n"
        prompt += "3. Explanation of the improvement\n"
        prompt += "4. Confidence level (0-1)\n"
        
        return prompt
    }
    
    private func generateRefactoringSuggestions(
        prompt: String,
        code: String,
        type: RefactoringType?
    ) async -> [RefactoringSuggestion] {
        // For now, return heuristic-based suggestions
        // In full implementation, this would call AI service
        
        var suggestions: [RefactoringSuggestion] = []
        
        // Simple heuristic: if code is long, suggest extract method
        if code.components(separatedBy: .newlines).count > 20 {
            suggestions.append(RefactoringSuggestion(
                type: .extractMethod,
                description: "This code block is long and could be extracted into a separate method for better readability",
                originalCode: code,
                refactoredCode: "// Extracted method would go here",
                affectedFiles: [],
                confidence: 0.7
            ))
        }
        
        // If no error handling, suggest adding it
        if !code.contains("try") && !code.contains("catch") && !code.contains("guard") {
            suggestions.append(RefactoringSuggestion(
                type: .addErrorHandling,
                description: "This code could benefit from error handling",
                originalCode: code,
                refactoredCode: "// Code with error handling",
                affectedFiles: [],
                confidence: 0.6
            ))
        }
        
        return suggestions
    }
    
    private func generatePreview(for suggestion: RefactoringSuggestion) async -> RefactoringPreview {
        // Generate preview with AI
        // In full implementation, this would call the AI service
        _ = """
        Refactor this code:
        
        Type: \(suggestion.type.rawValue)
        Original code:
        \(suggestion.originalCode)
        
        Provide the refactored code with detailed changes.
        """
        
        // For now, return a simple preview
        return RefactoringPreview(
            originalCode: suggestion.originalCode,
            refactoredCode: suggestion.refactoredCode,
            changes: [],
            affectedFiles: suggestion.affectedFiles
        )
    }
    
    private func applyChange(_ change: RefactoringCodeChange, in file: URL) async throws {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            throw NSError(domain: "RefactoringService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read file"])
        }
        
        let lines = content.components(separatedBy: .newlines)
        guard change.line > 0 && change.line <= lines.count else {
            throw NSError(domain: "RefactoringService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid line number"])
        }
        
        var newLines = lines
        newLines[change.line - 1] = change.modified
        
        let newContent = newLines.joined(separator: "\n")
        try newContent.write(to: file, atomically: true, encoding: .utf8)
    }
}

