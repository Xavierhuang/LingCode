//
//  LingCodeRulesService.swift
//  LingCode
//
//  Like .cursorrules - project-specific AI instructions
//

import Foundation
import Combine

/// Service to manage .lingcode rules files (like .cursorrules)
class LingCodeRulesService: ObservableObject {
    static let shared = LingCodeRulesService()
    
    @Published var projectRules: String = ""
    @Published var globalRules: String = ""
    @Published var hasProjectRules: Bool = false
    
    private let rulesFileNames = [".lingcode", ".lingrules", ".cursorrules"]
    
    private init() {
        loadGlobalRules()
    }
    
    // MARK: - Load Rules
    
    /// Load rules for a project directory
    func loadRules(for projectURL: URL?) {
        guard let projectURL = projectURL else {
            projectRules = ""
            hasProjectRules = false
            return
        }
        
        // Look for rules file in project root
        for fileName in rulesFileNames {
            let rulesURL = projectURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: rulesURL.path) {
                do {
                    projectRules = try String(contentsOf: rulesURL, encoding: .utf8)
                    hasProjectRules = true
                    return
                } catch {
                    print("Failed to load rules: \(error)")
                }
            }
        }
        
        projectRules = ""
        hasProjectRules = false
    }
    
    /// Load global rules from app support directory
    func loadGlobalRules() {
        guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        let lingcodeDir = supportURL.appendingPathComponent("LingCode")
        let globalRulesURL = lingcodeDir.appendingPathComponent("global_rules.md")
        
        if FileManager.default.fileExists(atPath: globalRulesURL.path) {
            do {
                globalRules = try String(contentsOf: globalRulesURL, encoding: .utf8)
            } catch {
                print("Failed to load global rules: \(error)")
            }
        }
    }
    
    // MARK: - Save Rules
    
    /// Create a new .lingcode file in the project
    func createProjectRules(at projectURL: URL, content: String) throws {
        let rulesURL = projectURL.appendingPathComponent(".lingcode")
        try content.write(to: rulesURL, atomically: true, encoding: .utf8)
        projectRules = content
        hasProjectRules = true
    }
    
    /// Save global rules
    func saveGlobalRules(_ content: String) throws {
        guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        let lingcodeDir = supportURL.appendingPathComponent("LingCode")
        try FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        
        let globalRulesURL = lingcodeDir.appendingPathComponent("global_rules.md")
        try content.write(to: globalRulesURL, atomically: true, encoding: .utf8)
        globalRules = content
    }
    
    // MARK: - Combined Rules
    
    /// Get combined rules for AI context
    var combinedRules: String {
        var rules = ""
        
        if !globalRules.isEmpty {
            rules += "# Global Rules\n\n\(globalRules)\n\n"
        }
        
        if !projectRules.isEmpty {
            rules += "# Project Rules\n\n\(projectRules)\n\n"
        }
        
        return rules
    }
    
    /// Get rules as AI system prompt addition
    func getRulesForAI() -> String? {
        let combined = combinedRules
        guard !combined.isEmpty else { return nil }
        
        return """
        <user_rules>
        The following rules have been set by the user. Follow them when generating code:
        
        \(combined)
        </user_rules>
        """
    }
    
    // MARK: - Templates
    
    /// Default template for new .lingcode file
    static let defaultTemplate = """
    # LingCode Project Rules
    
    ## Code Style
    - Use 4-space indentation
    - Follow Swift naming conventions
    - Add documentation comments for public APIs
    
    ## Preferences
    - Prefer Swift Concurrency (async/await) over callbacks
    - Use SwiftUI for new views
    - Follow MVVM architecture
    
    ## Don't
    - Don't add emojis to code
    - Don't create unnecessary abstractions
    - Don't change unrelated code
    
    ## Project Structure
    - Views go in /Views
    - Services go in /Services
    - Models go in /Models
    """
}

