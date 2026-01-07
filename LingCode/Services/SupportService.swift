//
//  SupportService.swift
//  LingCode
//
//  In-app help and support system
//  Better than Cursor's "AI support going rogue"
//

import Foundation

/// Service for in-app help and support
/// Addresses Cursor's support issues
class SupportService {
    static let shared = SupportService()
    
    private init() {}
    
    /// Get help content for a topic
    func getHelp(topic: HelpTopic) -> HelpContent? {
        return helpDatabase[topic]
    }
    
    /// Search help content
    func searchHelp(query: String) -> [HelpContent] {
        return helpDatabase.values.filter { content in
            content.title.localizedCaseInsensitiveContains(query) ||
            content.content.localizedCaseInsensitiveContains(query)
        }
    }
    
    /// Check for updates
    func checkForUpdates() -> UpdateInfo? {
        // In production, would check remote server
        // For now, return nil (no updates)
        return nil
    }
    
    /// Submit feedback
    func submitFeedback(_ feedback: Feedback) {
        // In production, would send to server
        // For now, just log locally
        print("Feedback submitted: \(feedback)")
    }
    
    /// Get changelog
    func getChangelog() -> [ChangelogEntry] {
        return [
            ChangelogEntry(
                version: "1.0.0",
                date: Date(),
                changes: [
                    "Initial release",
                    "Code validation system",
                    "Usage tracking",
                    "Performance optimization",
                    "Graphite integration"
                ]
            )
        ]
    }
    
    private var helpDatabase: [HelpTopic: HelpContent] = [
        .gettingStarted: HelpContent(
            topic: .gettingStarted,
            title: "Getting Started",
            content: """
            Welcome to LingCode!
            
            1. Set up your API key in Settings (Cmd+,)
            2. Open a folder or create a new file
            3. Start coding with AI assistance
            
            Use Cmd+K for inline editing
            Use Cmd+L for AI chat
            """
        ),
        .keyboardShortcuts: HelpContent(
            topic: .keyboardShortcuts,
            title: "Keyboard Shortcuts",
            content: """
            Essential Shortcuts:
            
            Cmd+K - Inline AI Edit
            Cmd+L - Open AI Chat
            Cmd+P - Quick Open
            Cmd+F - Find in File
            Cmd+Shift+F - Find in Files
            Cmd+, - Settings
            Cmd+Shift+U - Usage Dashboard
            """
        ),
        .codeValidation: HelpContent(
            topic: .codeValidation,
            title: "Code Validation",
            content: """
            LingCode validates all code changes before applying:
            
            - Syntax checking
            - Scope validation
            - Unintended deletion detection
            - Architecture compliance
            
            Review validation warnings before applying changes.
            """
        ),
        .usageTracking: HelpContent(
            topic: .usageTracking,
            title: "Usage Tracking",
            content: """
            Complete transparency:
            
            - Real-time request counter
            - Token usage tracking
            - Cost estimation
            - Rate limit warnings
            
            Open Usage Dashboard with Cmd+Shift+U
            """
        )
    ]
}

// MARK: - Models

enum HelpTopic: String {
    case gettingStarted = "getting_started"
    case keyboardShortcuts = "keyboard_shortcuts"
    case codeValidation = "code_validation"
    case usageTracking = "usage_tracking"
    case performance = "performance"
    case security = "security"
}

struct HelpContent {
    let topic: HelpTopic
    let title: String
    let content: String
}

struct UpdateInfo {
    let version: String
    let releaseNotes: String
    let downloadURL: URL?
    let isRequired: Bool
}

struct Feedback {
    let type: FeedbackType
    let message: String
    let email: String?
    let timestamp: Date
    
    enum FeedbackType {
        case bug
        case feature
        case question
        case other
    }
}

struct ChangelogEntry {
    let version: String
    let date: Date
    let changes: [String]
}





