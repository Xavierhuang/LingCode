//
//  RulesService.swift
//  LingCode
//
//  Rules for AI (.lingcoderules / .cursorrules) - Project-level AI rules
//  Allows projects to define custom AI behavior rules
//

import Foundation
import Combine

// MARK: - Rule Types

struct AIRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var pattern: String?  // File pattern this rule applies to (e.g., "*.swift")
    var content: String   // The actual rule content
    var isEnabled: Bool
    var priority: Int     // Higher priority rules override lower ones
    var source: RuleSource
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        pattern: String? = nil,
        content: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        source: RuleSource = .project
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.pattern = pattern
        self.content = content
        self.isEnabled = isEnabled
        self.priority = priority
        self.source = source
    }
}

enum RuleSource: String, Codable {
    case builtin = "Built-in"
    case project = "Project"
    case user = "User"
    case workspace = "Workspace"
}

// MARK: - Rules Service

class RulesService: ObservableObject {
    static let shared = RulesService()
    
    @Published var projectRules: [AIRule] = []
    @Published var userRules: [AIRule] = []
    @Published var workspaceRules: [AIRule] = []
    @Published var currentProjectURL: URL?
    
    private let userRulesURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        userRulesURL = lingcodeDir.appendingPathComponent("user_rules.json")
        
        loadUserRules()
    }
    
    // MARK: - Built-in Rules
    
    var builtinRules: [AIRule] {
        return [
            AIRule(
                name: "Code Quality",
                description: "Enforce code quality standards",
                content: """
                Always follow these code quality guidelines:
                - Write clean, readable code with meaningful names
                - Add comments for complex logic
                - Handle errors appropriately
                - Avoid code duplication
                - Keep functions focused and small
                """,
                priority: 100,
                source: .builtin
            ),
            AIRule(
                name: "Security First",
                description: "Security-focused coding practices",
                content: """
                Security requirements:
                - Never hardcode secrets, passwords, or API keys
                - Always validate and sanitize user input
                - Use parameterized queries for database operations
                - Implement proper authentication and authorization
                - Log security-relevant events
                """,
                priority: 90,
                source: .builtin
            ),
            AIRule(
                name: "Swift Best Practices",
                description: "Swift-specific guidelines",
                pattern: "*.swift",
                content: """
                Swift coding standards:
                - Use Swift naming conventions (camelCase for variables, PascalCase for types)
                - Prefer value types (struct/enum) over reference types when appropriate
                - Use guard for early exits
                - Leverage optionals safely with if-let, guard-let, or nil coalescing
                - Use strong typing and avoid Any when possible
                - Mark classes as final unless inheritance is intended
                """,
                priority: 80,
                source: .builtin
            ),
            AIRule(
                name: "SwiftUI Patterns",
                description: "SwiftUI-specific guidelines",
                pattern: "*.swift",
                content: """
                SwiftUI best practices:
                - Keep views small and focused
                - Extract reusable components
                - Use @State for local state, @Binding for parent state
                - Use @StateObject for owned objects, @ObservedObject for passed objects
                - Prefer computed properties over methods for derived state
                - Use ViewModifiers for reusable styling
                """,
                priority: 75,
                source: .builtin
            ),
            AIRule(
                name: "Testing Requirements",
                description: "Test coverage guidelines",
                content: """
                Testing standards:
                - Write tests for all public interfaces
                - Include happy path, edge cases, and error scenarios
                - Use descriptive test names that explain what's being tested
                - Mock external dependencies
                - Aim for high coverage of critical paths
                """,
                priority: 70,
                source: .builtin
            ),
            AIRule(
                name: "Documentation",
                description: "Documentation requirements",
                content: """
                Documentation guidelines:
                - Add doc comments to all public APIs
                - Include parameter descriptions and return values
                - Document thrown errors
                - Add usage examples for complex APIs
                - Keep README updated with setup instructions
                """,
                priority: 60,
                source: .builtin
            )
        ]
    }
    
    // MARK: - Load Rules
    
    func loadProjectRules(from projectURL: URL) {
        currentProjectURL = projectURL
        projectRules = []
        workspaceRules = []
        
        // Check for .lingcoderules
        loadRulesFile(projectURL.appendingPathComponent(".lingcoderules"), source: .project)
        
        // Check for .cursorrules (Cursor compatibility)
        loadRulesFile(projectURL.appendingPathComponent(".cursorrules"), source: .project)
        
        // Check for .cursor/rules directory
        let cursorRulesDir = projectURL.appendingPathComponent(".cursor/rules")
        loadRulesDirectory(cursorRulesDir, source: .project)
        
        // Check for WORKSPACE.md
        loadWorkspaceMd(projectURL.appendingPathComponent("WORKSPACE.md"))
    }
    
    private func loadRulesFile(_ url: URL, source: RuleSource) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let rules = parseRulesFile(content, filename: url.lastPathComponent, source: source)
            
            switch source {
            case .project:
                projectRules.append(contentsOf: rules)
            case .user:
                userRules.append(contentsOf: rules)
            case .workspace:
                workspaceRules.append(contentsOf: rules)
            default:
                break
            }
        } catch {
            print("RulesService: Failed to load \(url.path): \(error)")
        }
    }
    
    private func loadRulesDirectory(_ url: URL, source: RuleSource) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "md" || file.pathExtension == "txt" {
                loadRulesFile(file, source: source)
            }
        } catch {
            print("RulesService: Failed to load rules directory: \(error)")
        }
    }
    
    private func loadWorkspaceMd(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let rule = AIRule(
                name: "WORKSPACE.md",
                description: "Project workspace rules",
                content: content,
                priority: 50,
                source: .workspace
            )
            workspaceRules.append(rule)
        } catch {
            print("RulesService: Failed to load WORKSPACE.md: \(error)")
        }
    }
    
    private func parseRulesFile(_ content: String, filename: String, source: RuleSource) -> [AIRule] {
        var rules: [AIRule] = []
        
        // Check if it's a JSON array of rules
        if content.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            if let data = content.data(using: .utf8),
               let parsed = try? JSONDecoder().decode([AIRule].self, from: data) {
                return parsed
            }
        }
        
        // Check for sectioned format (## Section)
        let sections = content.components(separatedBy: "\n## ").dropFirst()
        if !sections.isEmpty {
            for section in sections {
                let lines = section.components(separatedBy: "\n")
                let name = lines.first?.trimmingCharacters(in: .whitespaces) ?? "Rule"
                let ruleContent = lines.dropFirst().joined(separator: "\n")
                
                rules.append(AIRule(
                    name: name,
                    content: ruleContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    source: source
                ))
            }
        } else {
            // Treat entire file as single rule
            rules.append(AIRule(
                name: filename.replacingOccurrences(of: ".", with: " ").capitalized,
                content: content,
                source: source
            ))
        }
        
        return rules
    }
    
    // MARK: - User Rules
    
    func addUserRule(_ rule: AIRule) {
        var newRule = rule
        newRule.source = .user
        userRules.append(newRule)
        saveUserRules()
    }
    
    func updateUserRule(_ rule: AIRule) {
        if let index = userRules.firstIndex(where: { $0.id == rule.id }) {
            userRules[index] = rule
            saveUserRules()
        }
    }
    
    func deleteUserRule(_ id: UUID) {
        userRules.removeAll { $0.id == id }
        saveUserRules()
    }
    
    private func loadUserRules() {
        guard FileManager.default.fileExists(atPath: userRulesURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: userRulesURL)
            userRules = try JSONDecoder().decode([AIRule].self, from: data)
        } catch {
            print("RulesService: Failed to load user rules: \(error)")
        }
    }
    
    private func saveUserRules() {
        do {
            let data = try JSONEncoder().encode(userRules)
            try data.write(to: userRulesURL)
        } catch {
            print("RulesService: Failed to save user rules: \(error)")
        }
    }
    
    // MARK: - Rule Matching
    
    func getActiveRules(for filePath: String? = nil) -> [AIRule] {
        var allRules = builtinRules + userRules + projectRules + workspaceRules
        
        // Filter by enabled
        allRules = allRules.filter { $0.isEnabled }
        
        // Filter by pattern if file path provided
        if let path = filePath {
            allRules = allRules.filter { rule in
                guard let pattern = rule.pattern else { return true }
                return matchesPattern(path: path, pattern: pattern)
            }
        }
        
        // Sort by priority (higher first)
        allRules.sort { $0.priority > $1.priority }
        
        return allRules
    }
    
    private func matchesPattern(path: String, pattern: String) -> Bool {
        // Simple glob matching
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return path.hasSuffix(".\(ext)")
        }
        
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return path.range(of: "^\(regex)$", options: .regularExpression) != nil
        }
        
        return path.contains(pattern)
    }
    
    // MARK: - Generate System Prompt
    
    func generateRulesPrompt(for filePath: String? = nil) -> String {
        let rules = getActiveRules(for: filePath)
        guard !rules.isEmpty else { return "" }
        
        var prompt = "## Project Rules\n\n"
        prompt += "Follow these rules when generating code:\n\n"
        
        for rule in rules {
            prompt += "### \(rule.name)\n"
            if !rule.description.isEmpty {
                prompt += "_\(rule.description)_\n\n"
            }
            prompt += "\(rule.content)\n\n"
        }
        
        return prompt
    }
    
    // MARK: - Save Project Rules
    
    func saveProjectRules(to projectURL: URL) {
        let rulesURL = projectURL.appendingPathComponent(".lingcoderules")
        
        var content = "# LingCode Project Rules\n\n"
        content += "Rules defined here will guide AI behavior for this project.\n\n"
        
        for rule in projectRules where rule.source == .project {
            content += "## \(rule.name)\n\n"
            if !rule.description.isEmpty {
                content += "_\(rule.description)_\n\n"
            }
            if let pattern = rule.pattern {
                content += "Pattern: `\(pattern)`\n\n"
            }
            content += "\(rule.content)\n\n"
        }
        
        try? content.write(to: rulesURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Templates
    
    func createFromTemplate(_ template: RuleTemplate, projectURL: URL) {
        let rule = AIRule(
            name: template.name,
            description: template.description,
            pattern: template.pattern,
            content: template.content,
            source: .project
        )
        
        projectRules.append(rule)
        saveProjectRules(to: projectURL)
    }
    
    enum RuleTemplate {
        case swiftConventions
        case reactBestPractices
        case apiDesign
        case gitCommitStyle
        case custom(name: String, content: String)
        
        var name: String {
            switch self {
            case .swiftConventions: return "Swift Conventions"
            case .reactBestPractices: return "React Best Practices"
            case .apiDesign: return "API Design Guidelines"
            case .gitCommitStyle: return "Git Commit Style"
            case .custom(let name, _): return name
            }
        }
        
        var description: String {
            switch self {
            case .swiftConventions: return "Swift coding conventions and style"
            case .reactBestPractices: return "React and hooks best practices"
            case .apiDesign: return "REST API design guidelines"
            case .gitCommitStyle: return "Conventional commit message format"
            case .custom: return "Custom rule"
            }
        }
        
        var pattern: String? {
            switch self {
            case .swiftConventions: return "*.swift"
            case .reactBestPractices: return "*.tsx"
            default: return nil
            }
        }
        
        var content: String {
            switch self {
            case .swiftConventions:
                return """
                - Use Swift API Design Guidelines naming conventions
                - Prefer value semantics (structs) over reference semantics
                - Use extensions to organize code by protocol conformance
                - Mark classes as final unless designed for inheritance
                - Use @MainActor for UI-related code
                """
            case .reactBestPractices:
                return """
                - Use functional components with hooks
                - Memoize expensive computations with useMemo
                - Use useCallback for callback stability
                - Avoid prop drilling - use context or state management
                - Keep components small and focused
                """
            case .apiDesign:
                return """
                - Use RESTful conventions (GET, POST, PUT, DELETE)
                - Return appropriate HTTP status codes
                - Use plural nouns for resources (/users, /posts)
                - Version APIs in URL (/api/v1/)
                - Include pagination for list endpoints
                """
            case .gitCommitStyle:
                return """
                Use conventional commits format:
                type(scope): description
                
                Types: feat, fix, docs, style, refactor, test, chore
                Scope: optional component name
                Description: imperative mood, lowercase, no period
                
                Examples:
                - feat(auth): add password reset flow
                - fix(api): handle null response correctly
                """
            case .custom(_, let content):
                return content
            }
        }
    }
}
