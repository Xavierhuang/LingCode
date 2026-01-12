//
//  AIDocumentationService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct DocumentationResult {
    let originalCode: String
    let documentedCode: String
    let summary: String?
}

class AIDocumentationService {
    static let shared = AIDocumentationService()
    
    private let aiService = AIService.shared
    
    private init() {}
    
    func generateDocumentation(
        for code: String,
        language: String?,
        style: DocumentationStyle = .auto,
        completion: @escaping (Result<DocumentationResult, Error>) -> Void
    ) {
        let styleInstructions = getStyleInstructions(for: style, language: language)
        
        let prompt = """
        Add comprehensive documentation to the following \(language ?? "code").
        
        Documentation style: \(styleInstructions)
        
        Requirements:
        - Add documentation comments to all public functions, classes, and properties
        - Include parameter descriptions
        - Include return value descriptions
        - Include usage examples where helpful
        - Preserve all existing code exactly
        - Only add documentation, do not modify the code logic
        
        Code to document:
        ```\(language ?? "")
        \(code)
        ```
        
        Return ONLY the documented code, no explanations.
        """
        
        aiService.sendMessage(prompt, context: nil) { response in
            let documentedCode = self.extractCode(from: response, language: language)
            let result = DocumentationResult(
                originalCode: code,
                documentedCode: documentedCode,
                summary: nil
            )
            completion(.success(result))
        } onError: { error in
            completion(.failure(NSError(domain: "Documentation", code: -1, userInfo: [NSLocalizedDescriptionKey: error])))
        }
    }
    
    func generateFunctionDocumentation(
        for functionCode: String,
        language: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let prompt = """
        Generate a documentation comment for this \(language ?? "function").
        
        Use the appropriate documentation format for the language:
        - Swift: /// DocC style
        - Python: Google/NumPy style docstring
        - JavaScript/TypeScript: JSDoc style
        - Java: Javadoc style
        
        Function:
        ```\(language ?? "")
        \(functionCode)
        ```
        
        Return ONLY the documentation comment that should go before the function.
        """
        
        aiService.sendMessage(prompt, context: nil) { response in
            let doc = response
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```\(language ?? "")", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            completion(.success(doc))
        } onError: { error in
            completion(.failure(NSError(domain: "Documentation", code: -1, userInfo: [NSLocalizedDescriptionKey: error])))
        }
    }
    
    func generateReadme(
        for projectContent: String,
        projectName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let prompt = """
        Generate a comprehensive README.md for a project called "\(projectName)".
        
        Based on the following code/file structure:
        \(projectContent.prefix(5000))
        
        Include:
        - Project title and description
        - Features list
        - Installation instructions
        - Usage examples
        - Configuration options (if any)
        - Contributing guidelines
        - License section
        
        Use proper Markdown formatting.
        """
        
        aiService.sendMessage(prompt, context: nil) { response in
            completion(.success(response))
        } onError: { error in
            completion(.failure(NSError(domain: "Documentation", code: -1, userInfo: [NSLocalizedDescriptionKey: error])))
        }
    }
    
    private func getStyleInstructions(for style: DocumentationStyle, language: String?) -> String {
        switch style {
        case .auto:
            switch language?.lowercased() {
            case "swift": return "Swift DocC (/// comments)"
            case "python": return "Google-style docstrings"
            case "javascript", "typescript": return "JSDoc (/** */ comments)"
            case "java", "kotlin": return "Javadoc (/** */ comments)"
            case "go": return "Go documentation comments"
            case "rust": return "Rust documentation (/// comments)"
            case "c", "cpp", "c++": return "Doxygen style"
            default: return "Standard documentation comments"
            }
        case .docC: return "Swift DocC (/// comments)"
        case .jsDoc: return "JSDoc (/** */ comments)"
        case .pythonDocstring: return "Google-style docstrings"
        case .javadoc: return "Javadoc (/** */ comments)"
        case .doxygen: return "Doxygen style"
        }
    }
    
    private func extractCode(from response: String, language: String?) -> String {
        var code = response
        
        // Remove code fence markers
        if let startRange = code.range(of: "```\(language ?? "")") {
            code = String(code[startRange.upperBound...])
        } else if let startRange = code.range(of: "```") {
            code = String(code[startRange.upperBound...])
        }
        
        if let endRange = code.range(of: "```", options: .backwards) {
            code = String(code[..<endRange.lowerBound])
        }
        
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    enum DocumentationStyle {
        case auto
        case docC
        case jsDoc
        case pythonDocstring
        case javadoc
        case doxygen
    }
}

