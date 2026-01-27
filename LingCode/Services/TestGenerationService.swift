//
//  TestGenerationService.swift
//  LingCode
//
//  Auto-generates tests for generated code
//

import Foundation
import Combine

struct GeneratedTest: Identifiable {
    let id = UUID()
    let filePath: String
    let testContent: String
    let testType: TestType
    let coverage: TestCoverage
    let timestamp: Date
    
    enum TestType {
        case unit
        case integration
        case e2e
    }
    
    struct TestCoverage {
        let functions: [String]
        let classes: [String]
        let lines: Int
    }
}

@MainActor
class TestGenerationService: ObservableObject {
    static let shared = TestGenerationService()
    
    @Published var isGenerating: Bool = false
    @Published var generatedTests: [GeneratedTest] = []
    
    private let aiService = AIService.shared
    
    private init() {}
    
    /// Generate tests for code
    func generateTests(
        for code: String,
        filePath: String,
        language: String,
        testType: GeneratedTest.TestType = .unit,
        completion: @escaping (Result<GeneratedTest, Error>) -> Void
    ) {
        isGenerating = true
        
        let testTypeStr = testType == .unit ? "unit" : (testType == .integration ? "integration" : "e2e")
        
        let prompt = """
        Generate comprehensive \(testTypeStr) tests for the following \(language) code.
        
        File: \(filePath)
        
        ```\(language)
        \(code)
        ```
        
        Requirements:
        1. Cover all public functions and methods
        2. Include edge cases and error handling
        3. Use appropriate testing framework for \(language)
        4. Make tests readable and maintainable
        5. Include setup and teardown if needed
        
        Provide the test code in a code block.
        """
        
        aiService.sendMessage(prompt, context: nil) { [weak self] response in
            DispatchQueue.main.async {
                self?.isGenerating = false
                
                // Extract test code from response
                let testContent = self?.extractTestCode(from: response, language: language) ?? response
                
                // Analyze coverage
                let coverage = self?.analyzeCoverage(code: code, testContent: testContent, language: language) ?? GeneratedTest.TestCoverage(functions: [], classes: [], lines: 0)
                
                let test = GeneratedTest(
                    filePath: filePath,
                    testContent: testContent,
                    testType: testType,
                    coverage: coverage,
                    timestamp: Date()
                )
                
                self?.generatedTests.append(test)
                completion(.success(test))
            }
        } onError: { [weak self] error in
            DispatchQueue.main.async {
                self?.isGenerating = false
                completion(.failure(error))
            }
        }
    }
    
    /// Extract test code from AI response
    private func extractTestCode(from response: String, language: String) -> String {
        // Look for code blocks
        let codeBlockPattern = #"```(?:\(language)|\(language.lowercased()))?\s*\n(.*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
           let range = Range(match.range(at: 1), in: response) {
            return String(response[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return response
    }
    
    /// Analyze test coverage
    private func analyzeCoverage(code: String, testContent: String, language: String) -> GeneratedTest.TestCoverage {
        // Simple heuristic-based coverage analysis
        var functions: [String] = []
        var classes: [String] = []
        
        // Extract function names from code (simplified)
        let funcPattern = #"(?:func|def|function)\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: funcPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: code, options: [], range: NSRange(code.startIndex..., in: code))
            functions = matches.compactMap { match in
                guard let range = Range(match.range(at: 1), in: code) else { return nil }
                return String(code[range])
            }
        }
        
        // Extract class names
        let classPattern = #"(?:class|struct)\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: classPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: code, options: [], range: NSRange(code.startIndex..., in: code))
            classes = matches.compactMap { match in
                guard let range = Range(match.range(at: 1), in: code) else { return nil }
                return String(code[range])
            }
        }
        
        let lines = testContent.components(separatedBy: .newlines).count
        
        return GeneratedTest.TestCoverage(functions: functions, classes: classes, lines: lines)
    }
}
