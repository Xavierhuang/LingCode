//
//  AICodeReviewService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

struct CodeReviewIssue: Identifiable {
    let id = UUID()
    let severity: IssueSeverity
    let category: IssueCategory
    let message: String
    let suggestion: String?
    let lineNumber: Int?
    let codeSnippet: String?
    
    enum IssueSeverity: String {
        case critical = "Critical"
        case warning = "Warning"
        case info = "Info"
        case style = "Style"
    }
    
    enum IssueCategory: String {
        case security = "Security"
        case performance = "Performance"
        case bestPractice = "Best Practice"
        case codeQuality = "Code Quality"
        case documentation = "Documentation"
        case maintainability = "Maintainability"
        case testability = "Testability"
    }
}

struct CodeReviewResult: Identifiable {
    let id = UUID()
    let issues: [CodeReviewIssue]
    let summary: String
    let score: Int // 0-100
    let timestamp: Date
}

class AICodeReviewService: ObservableObject {
    static let shared = AICodeReviewService()
    
    @Published var isReviewing: Bool = false
    @Published var lastReview: CodeReviewResult?
    
    private let aiService = AIService.shared
    
    private init() {}
    
    func reviewCode(
        _ code: String,
        language: String?,
        fileName: String?,
        completion: @escaping (Result<CodeReviewResult, Error>) -> Void
    ) {
        isReviewing = true
        
        let prompt = """
        You are a senior code reviewer. Analyze the following \(language ?? "code") and provide a comprehensive review.
        
        File: \(fileName ?? "unknown")
        
        ```\(language ?? "")
        \(code)
        ```
        
        Provide your review in the following format:
        
        SCORE: [0-100]
        
        SUMMARY: [Brief overall assessment]
        
        ISSUES:
        - [SEVERITY: critical/warning/info/style] [CATEGORY: security/performance/bestPractice/codeQuality/documentation/maintainability/testability] [LINE: number or N/A] [MESSAGE: description] [SUGGESTION: how to fix]
        
        Be specific and actionable. Focus on real issues, not nitpicking.
        """
        
        Task { @MainActor in
            do {
                let response = try await aiService.sendMessage(prompt, context: nil, images: [], tools: nil)
                self.isReviewing = false
                let result = self.parseReviewResponse(response)
                if let result = result {
                    self.lastReview = result
                    completion(.success(result))
                } else {
                    completion(.failure(NSError(domain: "CodeReview", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse review"])))
                }
            } catch {
                self.isReviewing = false
                completion(.failure(NSError(domain: "CodeReview", code: -1, userInfo: [NSLocalizedDescriptionKey: String(describing: error)])))
            }
        }
    }
    
    private func parseReviewResponse(_ response: String) -> CodeReviewResult? {
        var score = 70
        var summary = ""
        var issues: [CodeReviewIssue] = []
        
        // Parse score
        if let scoreRange = response.range(of: #"SCORE:\s*(\d+)"#, options: .regularExpression) {
            let scoreStr = String(response[scoreRange]).replacingOccurrences(of: "SCORE:", with: "").trimmingCharacters(in: .whitespaces)
            score = Int(scoreStr) ?? 70
        }
        
        // Parse summary
        if let summaryStart = response.range(of: "SUMMARY:"),
           let issuesStart = response.range(of: "ISSUES:") {
            summary = String(response[summaryStart.upperBound..<issuesStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse issues
        let issuePattern = #"-\s*\[SEVERITY:\s*(critical|warning|info|style)\]\s*\[CATEGORY:\s*(\w+)\]\s*\[LINE:\s*(\d+|N/A)\]\s*\[MESSAGE:\s*([^\]]+)\]\s*\[SUGGESTION:\s*([^\]]+)\]"#
        
        if let regex = try? NSRegularExpression(pattern: issuePattern, options: [.caseInsensitive]) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches {
                if match.numberOfRanges >= 6 {
                    let severity = extractMatch(from: response, match: match, at: 1)
                    let category = extractMatch(from: response, match: match, at: 2)
                    let line = extractMatch(from: response, match: match, at: 3)
                    let message = extractMatch(from: response, match: match, at: 4)
                    let suggestion = extractMatch(from: response, match: match, at: 5)
                    
                    let issue = CodeReviewIssue(
                        severity: parseSeverity(severity),
                        category: parseCategory(category),
                        message: message,
                        suggestion: suggestion,
                        lineNumber: Int(line),
                        codeSnippet: nil
                    )
                    issues.append(issue)
                }
            }
        }
        
        // If no structured issues found, create generic ones from the response
        if issues.isEmpty && !summary.isEmpty {
            issues.append(CodeReviewIssue(
                severity: .info,
                category: .codeQuality,
                message: summary,
                suggestion: nil,
                lineNumber: nil,
                codeSnippet: nil
            ))
        }
        
        return CodeReviewResult(
            issues: issues,
            summary: summary,
            score: score,
            timestamp: Date()
        )
    }
    
    private func extractMatch(from string: String, match: NSTextCheckingResult, at index: Int) -> String {
        if let range = Range(match.range(at: index), in: string) {
            return String(string[range])
        }
        return ""
    }
    
    private func parseSeverity(_ str: String) -> CodeReviewIssue.IssueSeverity {
        switch str.lowercased() {
        case "critical": return .critical
        case "warning": return .warning
        case "style": return .style
        default: return .info
        }
    }
    
    private func parseCategory(_ str: String) -> CodeReviewIssue.IssueCategory {
        switch str.lowercased() {
        case "security": return .security
        case "performance": return .performance
        case "bestpractice": return .bestPractice
        case "documentation": return .documentation
        case "maintainability": return .maintainability
        case "testability": return .testability
        default: return .codeQuality
        }
    }
}

