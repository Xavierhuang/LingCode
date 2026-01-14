//
//  ThemeService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit
import Combine

struct CodeTheme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let keyword: NSColor
    let string: NSColor
    let comment: NSColor
    let number: NSColor
    let type: NSColor
    let selection: NSColor
    let lineNumber: NSColor
    let cursor: NSColor
}

class ThemeService: ObservableObject {
    static let shared = ThemeService()
    
    @Published var forcedTheme: ThemePreference? = nil
    
    enum ThemePreference: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
    }
    
    private init() {
        // Load saved preference
        if let saved = UserDefaults.standard.string(forKey: "themePreference"),
           let preference = ThemePreference(rawValue: saved) {
            forcedTheme = preference
        } else {
            forcedTheme = .system
        }
    }
    
    var currentTheme: CodeTheme {
        let isDark: Bool
        switch forcedTheme {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system, .none:
            isDark = NSApp.effectiveAppearance.name == .darkAqua
        }
        return isDark ? darkTheme : lightTheme
    }
    
    func setTheme(_ preference: ThemePreference) {
        forcedTheme = preference
        UserDefaults.standard.set(preference.rawValue, forKey: "themePreference")
        
        // Apply theme to app appearance - this affects all windows
        DispatchQueue.main.async {
            if preference == .dark {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            } else if preference == .light {
                NSApp.appearance = NSAppearance(named: .aqua)
            } else {
                NSApp.appearance = nil // Use system default
            }
            
            // Force all windows to update their appearance
            for window in NSApplication.shared.windows {
                window.appearance = NSApp.appearance
            }
        }
    }
    
    let darkTheme = CodeTheme(
        name: "Dark",
        background: NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0),
        foreground: NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
        keyword: NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0),
        string: NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0),
        comment: NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
        number: NSColor(red: 0.8, green: 0.6, blue: 0.8, alpha: 1.0),
        type: NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0),
        selection: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0),
        lineNumber: NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0),
        cursor: NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
    )
    
    let lightTheme = CodeTheme(
        name: "Light",
        background: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        foreground: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
        keyword: NSColor(red: 0.0, green: 0.2, blue: 0.8, alpha: 1.0),
        string: NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0),
        comment: NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0),
        number: NSColor(red: 0.6, green: 0.2, blue: 0.6, alpha: 1.0),
        type: NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
        selection: NSColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0),
        lineNumber: NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0),
        cursor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
    )
}



