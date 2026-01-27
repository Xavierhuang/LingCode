//
//  TeamRulesService.swift
//  LingCode
//
//  Team/Cloud rules support (Cursor feature)
//  Allows sharing rules across team members via cloud storage or shared directory
//

import Foundation
import Combine

/// Service for managing team/cloud rules (Cursor feature)
class TeamRulesService: ObservableObject {
    static let shared = TeamRulesService()
    
    @Published var teamRules: String = ""
    @Published var isEnabled: Bool = false
    @Published var teamRulesURL: URL? = nil
    
    private init() {
        loadSettings()
    }
    
    // MARK: - Settings
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "teamRulesEnabled")
        if let urlString = defaults.string(forKey: "teamRulesURL"),
           let url = URL(string: urlString) {
            teamRulesURL = url
            loadTeamRules()
        }
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: "teamRulesEnabled")
        defaults.set(teamRulesURL?.absoluteString, forKey: "teamRulesURL")
    }
    
    // MARK: - Load Team Rules
    
    /// Configure team rules from a URL (file://, http://, or https://)
    func configureTeamRules(url: URL, enabled: Bool = true) {
        teamRulesURL = url
        isEnabled = enabled
        saveSettings()
        loadTeamRules()
    }
    
    /// Load team rules from configured URL
    func loadTeamRules() {
        guard isEnabled, let url = teamRulesURL else {
            teamRules = ""
            return
        }
        
        // Handle different URL schemes
        if url.scheme == "file" || url.scheme == nil {
            // Local file
            if FileManager.default.fileExists(atPath: url.path),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                teamRules = content
            }
        } else if url.scheme == "http" || url.scheme == "https" {
            // Remote URL - fetch asynchronously
            fetchRemoteRules(url: url)
        }
    }
    
    private func fetchRemoteRules(url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Failed to fetch team rules: \(error)")
                DispatchQueue.main.async {
                    self.teamRules = ""
                }
                return
            }
            
            if let data = data,
               let content = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.teamRules = content
                }
            }
        }
        task.resume()
    }
    
    /// Get team rules formatted for AI prompt
    func getTeamRulesForAI() -> String? {
        guard isEnabled, !teamRules.isEmpty else { return nil }
        let trimmed = teamRules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        return """
        ## Team Rules (shared across team)
        
        \(trimmed)
        """
    }
    
    /// Disable team rules
    func disable() {
        isEnabled = false
        teamRules = ""
        saveSettings()
    }
}
