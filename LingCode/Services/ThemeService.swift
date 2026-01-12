//
//  ThemeService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit

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

class ThemeService {
    static let shared = ThemeService()
    
    private init() {}
    
    var currentTheme: CodeTheme {
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
        return isDark ? darkTheme : lightTheme
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



