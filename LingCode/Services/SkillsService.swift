//
//  SkillsService.swift
//  LingCode
//
//  Skills system for slash commands (/commit, /review, /test, etc.)
//

import Foundation
import Combine

// MARK: - Skill Definition

/// A skill is a reusable command/workflow that can be triggered with /command
struct Skill: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String
    let icon: String
    let prompt: String
    let category: SkillCategory
    let requiresSelection: Bool
    let requiresFile: Bool
    var isBuiltIn: Bool
    var isEnabled: Bool
    
    init(
        name: String,
        description: String,
        icon: String = "command",
        prompt: String,
        category: SkillCategory = .custom,
        requiresSelection: Bool = false,
        requiresFile: Bool = false,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.prompt = prompt
        self.category = category
        self.requiresSelection = requiresSelection
        self.requiresFile = requiresFile
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }
}

enum SkillCategory: String, Codable, CaseIterable {
    case git = "Git"
    case code = "Code"
    case testing = "Testing"
    case documentation = "Documentation"
    case refactoring = "Refactoring"
    case debugging = "Debugging"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .git: return "arrow.triangle.branch"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .testing: return "checkmark.circle"
        case .documentation: return "doc.text"
        case .refactoring: return "arrow.triangle.2.circlepath"
        case .debugging: return "ladybug"
        case .custom: return "star"
        }
    }
}

/// Skill execution context
struct SkillContext {
    let currentFile: URL?
    let selectedText: String?
    let projectURL: URL?
    let additionalArgs: [String]
}

/// Skill execution result
struct SkillResult {
    let success: Bool
    let output: String
    let actions: [SkillAction]
}

enum SkillAction {
    case sendToChat(String)
    case runTerminal(String)
    case openFile(URL)
    case showNotification(String)
}

// MARK: - Skills Service

class SkillsService: ObservableObject {
    static let shared = SkillsService()
    
    @Published var skills: [Skill] = []
    @Published var recentlyUsed: [String] = []
    
    private let configURL: URL
    private let maxRecentSkills = 5
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        configURL = lingcodeDir.appendingPathComponent("skills.json")
        
        loadSkills()
    }
    
    // MARK: - Built-in Skills
    
    private func builtInSkills() -> [Skill] {
        return [
            // Git Skills
            Skill(
                name: "commit",
                description: "Create a git commit with AI-generated message",
                icon: "arrow.up.circle",
                prompt: """
                Analyze the current git diff and create a commit:
                1. Run `git diff --staged` to see staged changes (or `git diff` if nothing staged)
                2. Generate a concise, conventional commit message following this format:
                   - type(scope): description
                   - Types: feat, fix, docs, style, refactor, test, chore
                3. Stage all changes if needed with `git add -A`
                4. Create the commit with the generated message
                5. Show the commit result
                
                Be concise but descriptive. Focus on WHAT changed and WHY.
                """,
                category: .git,
                isBuiltIn: true
            ),
            Skill(
                name: "push",
                description: "Push commits to remote with safety checks",
                icon: "arrow.up.to.line",
                prompt: """
                Push the current branch to remote:
                1. Check current branch name with `git branch --show-current`
                2. Check if there are unpushed commits with `git status`
                3. If on main/master, warn the user and ask for confirmation
                4. Run `git push origin <branch>` (or `git push -u origin <branch>` if new)
                5. Show the push result and any CI/CD links if available
                """,
                category: .git,
                isBuiltIn: true
            ),
            Skill(
                name: "pr",
                description: "Create a pull request with AI-generated description",
                icon: "arrow.triangle.pull",
                prompt: """
                Create a pull request:
                1. Get the current branch and compare with main/master
                2. Run `git log main..HEAD --oneline` to see commits
                3. Run `git diff main..HEAD --stat` to see changed files
                4. Generate a PR title and description:
                   - Title: Clear, concise summary
                   - Description: What changed, why, how to test
                5. Use `gh pr create` or provide the GitHub URL to create manually
                """,
                category: .git,
                isBuiltIn: true
            ),
            
            // Code Skills
            Skill(
                name: "review",
                description: "Review the current file or selection for issues",
                icon: "eye",
                prompt: """
                Review the code for potential issues:
                1. Check for bugs, logic errors, and edge cases
                2. Identify security vulnerabilities
                3. Look for performance issues
                4. Check code style and best practices
                5. Suggest improvements with specific line numbers
                
                Format your review as:
                - CRITICAL: Issues that must be fixed
                - WARNING: Issues that should be addressed
                - SUGGESTION: Optional improvements
                - GOOD: Things done well (brief)
                """,
                category: .code,
                requiresFile: true,
                isBuiltIn: true
            ),
            Skill(
                name: "explain",
                description: "Explain the selected code or current file",
                icon: "questionmark.circle",
                prompt: """
                Explain this code clearly:
                1. High-level overview: What does this code do?
                2. Key components and their responsibilities
                3. Important algorithms or patterns used
                4. Data flow and state management
                5. Any non-obvious behavior or gotchas
                
                Use simple language. If there's selected text, focus on that.
                Otherwise, explain the entire file.
                """,
                category: .code,
                requiresFile: true,
                isBuiltIn: true
            ),
            Skill(
                name: "optimize",
                description: "Suggest optimizations for the current code",
                icon: "bolt",
                prompt: """
                Analyze and optimize this code:
                1. Identify performance bottlenecks
                2. Look for unnecessary computations or allocations
                3. Check for N+1 queries or repeated operations
                4. Suggest algorithmic improvements
                5. Consider memory usage and caching opportunities
                
                Provide before/after code examples for each suggestion.
                """,
                category: .code,
                requiresFile: true,
                isBuiltIn: true
            ),
            
            // Testing Skills
            Skill(
                name: "test",
                description: "Generate unit tests for the current file",
                icon: "checkmark.shield",
                prompt: """
                Generate comprehensive unit tests:
                1. Identify all public functions and methods
                2. Create tests for:
                   - Happy path (normal usage)
                   - Edge cases (empty, nil, boundaries)
                   - Error conditions
                3. Use the project's testing framework (detect from imports)
                4. Include setup/teardown if needed
                5. Add descriptive test names that explain what's being tested
                
                Generate the test file content ready to save.
                """,
                category: .testing,
                requiresFile: true,
                isBuiltIn: true
            ),
            Skill(
                name: "coverage",
                description: "Analyze test coverage and suggest missing tests",
                icon: "chart.pie",
                prompt: """
                Analyze test coverage:
                1. List all functions/methods in the current file
                2. Check if corresponding tests exist
                3. Identify untested code paths
                4. Suggest specific tests to add
                5. Prioritize by risk and importance
                
                Focus on critical business logic first.
                """,
                category: .testing,
                requiresFile: true,
                isBuiltIn: true
            ),
            
            // Documentation Skills
            Skill(
                name: "doc",
                description: "Generate documentation for the current code",
                icon: "doc.text",
                prompt: """
                Generate documentation:
                1. Add doc comments to all public interfaces
                2. Include parameter descriptions
                3. Document return values and errors
                4. Add usage examples where helpful
                5. Follow the language's doc comment conventions
                
                For Swift: Use /// and - Parameter:, - Returns:, - Throws:
                For Python: Use docstrings with Args, Returns, Raises
                For TypeScript: Use JSDoc with @param, @returns, @throws
                """,
                category: .documentation,
                requiresFile: true,
                isBuiltIn: true
            ),
            Skill(
                name: "readme",
                description: "Generate or update README for the project",
                icon: "book",
                prompt: """
                Generate a README.md:
                1. Analyze the project structure
                2. Create sections:
                   - Title and description
                   - Installation instructions
                   - Usage examples
                   - API documentation (if applicable)
                   - Contributing guidelines
                   - License
                3. Include code examples
                4. Add badges if appropriate
                """,
                category: .documentation,
                isBuiltIn: true
            ),
            
            // Refactoring Skills
            Skill(
                name: "refactor",
                description: "Suggest refactoring opportunities",
                icon: "arrow.triangle.2.circlepath",
                prompt: """
                Analyze code for refactoring:
                1. Identify code smells:
                   - Long methods
                   - Duplicate code
                   - Complex conditionals
                   - Deep nesting
                2. Suggest specific refactorings:
                   - Extract method/function
                   - Extract class/module
                   - Replace conditional with polymorphism
                   - Introduce parameter object
                3. Show before/after examples
                4. Estimate risk and effort for each
                """,
                category: .refactoring,
                requiresFile: true,
                isBuiltIn: true
            ),
            Skill(
                name: "rename",
                description: "Suggest better names for variables and functions",
                icon: "textformat.abc",
                prompt: """
                Review naming in this code:
                1. Identify unclear or misleading names
                2. Suggest more descriptive alternatives
                3. Check for naming convention consistency
                4. Look for abbreviations that should be expanded
                5. Ensure names reveal intent
                
                Good names should:
                - Be pronounceable
                - Be searchable
                - Reveal intention
                - Avoid disinformation
                """,
                category: .refactoring,
                requiresFile: true,
                isBuiltIn: true
            ),
            
            // Debugging Skills
            Skill(
                name: "debug",
                description: "Help debug an issue in the current code",
                icon: "ladybug",
                prompt: """
                Help debug this code:
                1. Analyze the code for potential issues
                2. Identify likely sources of bugs
                3. Suggest debugging steps:
                   - Print statements to add
                   - Breakpoints to set
                   - Values to inspect
                4. Propose fixes for identified issues
                5. Explain the root cause
                
                If there's an error message, focus on that specific issue.
                """,
                category: .debugging,
                requiresFile: true,
                isBuiltIn: true
            ),
            Skill(
                name: "fix",
                description: "Automatically fix linting and compilation errors",
                icon: "wrench",
                prompt: """
                Fix errors in this code:
                1. Run the linter/compiler to get current errors
                2. Analyze each error
                3. Apply fixes automatically where safe
                4. For ambiguous errors, explain options
                5. Re-run to verify fixes
                
                Focus on:
                - Syntax errors
                - Type errors
                - Import/dependency issues
                - Linting violations
                """,
                category: .debugging,
                requiresFile: true,
                isBuiltIn: true
            )
        ]
    }
    
    // MARK: - Skill Management
    
    func loadSkills() {
        // Start with built-in skills
        var allSkills = builtInSkills()
        
        // Load custom skills from disk
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let customSkills = try JSONDecoder().decode([Skill].self, from: data)
                allSkills.append(contentsOf: customSkills)
            } catch {
                print("Skills: Failed to load custom skills: \(error)")
            }
        }
        
        skills = allSkills
        loadRecentlyUsed()
    }
    
    func saveCustomSkills() {
        let customSkills = skills.filter { !$0.isBuiltIn }
        do {
            let data = try JSONEncoder().encode(customSkills)
            try data.write(to: configURL)
        } catch {
            print("Skills: Failed to save skills: \(error)")
        }
    }
    
    func addSkill(_ skill: Skill) {
        var newSkill = skill
        newSkill.isBuiltIn = false
        skills.append(newSkill)
        saveCustomSkills()
    }
    
    func updateSkill(_ skill: Skill) {
        if let index = skills.firstIndex(where: { $0.name == skill.name }) {
            skills[index] = skill
            if !skill.isBuiltIn {
                saveCustomSkills()
            }
        }
    }
    
    func deleteSkill(_ name: String) {
        skills.removeAll { $0.name == name && !$0.isBuiltIn }
        saveCustomSkills()
    }
    
    // MARK: - Skill Search
    
    func findSkill(_ name: String) -> Skill? {
        return skills.first { $0.name.lowercased() == name.lowercased() && $0.isEnabled }
    }
    
    func searchSkills(_ query: String) -> [Skill] {
        guard !query.isEmpty else { return skills.filter { $0.isEnabled } }
        
        let lowercased = query.lowercased()
        return skills.filter { skill in
            skill.isEnabled && (
                skill.name.lowercased().contains(lowercased) ||
                skill.description.lowercased().contains(lowercased) ||
                skill.category.rawValue.lowercased().contains(lowercased)
            )
        }
    }
    
    func skillsByCategory() -> [SkillCategory: [Skill]] {
        var result: [SkillCategory: [Skill]] = [:]
        for skill in skills where skill.isEnabled {
            result[skill.category, default: []].append(skill)
        }
        return result
    }
    
    // MARK: - Skill Execution
    
    func executeSkill(_ skill: Skill, context: SkillContext) -> SkillResult {
        // Record usage
        recordUsage(skill.name)
        
        // Build the prompt with context
        var prompt = skill.prompt
        
        if skill.requiresFile, let file = context.currentFile {
            prompt = "Current file: \(file.path)\n\n" + prompt
        }
        
        if skill.requiresSelection, let selection = context.selectedText, !selection.isEmpty {
            prompt = "Selected code:\n```\n\(selection)\n```\n\n" + prompt
        }
        
        if let projectURL = context.projectURL {
            prompt = "Project: \(projectURL.path)\n" + prompt
        }
        
        // Return action to send to chat
        return SkillResult(
            success: true,
            output: prompt,
            actions: [.sendToChat(prompt)]
        )
    }
    
    // MARK: - Recently Used
    
    private func recordUsage(_ skillName: String) {
        recentlyUsed.removeAll { $0 == skillName }
        recentlyUsed.insert(skillName, at: 0)
        if recentlyUsed.count > maxRecentSkills {
            recentlyUsed = Array(recentlyUsed.prefix(maxRecentSkills))
        }
        saveRecentlyUsed()
    }
    
    private func loadRecentlyUsed() {
        recentlyUsed = UserDefaults.standard.stringArray(forKey: "lingcode.skills.recent") ?? []
    }
    
    private func saveRecentlyUsed() {
        UserDefaults.standard.set(recentlyUsed, forKey: "lingcode.skills.recent")
    }
    
    func getRecentSkills() -> [Skill] {
        return recentlyUsed.compactMap { findSkill($0) }
    }
    
    // MARK: - Slash Command Parsing
    
    /// Parse a slash command from user input
    func parseSlashCommand(_ input: String) -> (skill: Skill, args: [String])? {
        guard input.hasPrefix("/") else { return nil }
        
        let parts = input.dropFirst().split(separator: " ", maxSplits: 1)
        guard let commandName = parts.first else { return nil }
        
        guard let skill = findSkill(String(commandName)) else { return nil }
        
        let args = parts.count > 1 ? String(parts[1]).components(separatedBy: " ") : []
        return (skill, args)
    }
    
    /// Check if input starts with a valid slash command
    func isSlashCommand(_ input: String) -> Bool {
        guard input.hasPrefix("/") else { return false }
        let commandName = input.dropFirst().split(separator: " ").first.map(String.init) ?? ""
        return findSkill(commandName) != nil
    }
    
    /// Get autocomplete suggestions for partial slash command
    func getSlashSuggestions(_ partial: String) -> [Skill] {
        guard partial.hasPrefix("/") else { return [] }
        let query = String(partial.dropFirst())
        
        if query.isEmpty {
            // Show recent + all skills
            let recent = getRecentSkills()
            let others = skills.filter { skill in
                skill.isEnabled && !recent.contains(where: { $0.name == skill.name })
            }
            return recent + others
        }
        
        return searchSkills(query)
    }
}
