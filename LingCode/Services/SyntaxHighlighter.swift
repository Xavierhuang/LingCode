//
//  SyntaxHighlighter.swift
//  LingCode
//
//  High-frequency UI: Tree-sitter for supported languages (incremental, fast for large files).
//  SwiftSyntax is reserved for deep refactors and AICodeReviewService only.
//

import Foundation
import AppKit

struct SyntaxHighlighter {
    enum Language: String, CaseIterable {
        case swift = "swift"
        case python = "python"
        case javascript = "javascript"
        case html = "html"
        case css = "css"
        case json = "json"
        case plaintext = "plaintext"
        
        var displayName: String {
            switch self {
            case .swift: return "Swift"
            case .python: return "Python"
            case .javascript: return "JavaScript"
            case .html: return "HTML"
            case .css: return "CSS"
            case .json: return "JSON"
            case .plaintext: return "Plain Text"
            }
        }
    }
    
    static func highlight(_ text: String, language: String?, theme: CodeTheme? = nil) -> NSAttributedString {
        // Use theme colors if provided, otherwise fall back to system colors
        let theme = theme ?? ThemeService.shared.currentTheme
        
        let attributedString = NSMutableAttributedString(string: text)
        
        // Set default foreground color for all text (ensures readable text in dark mode)
        attributedString.addAttribute(.foregroundColor, value: theme.foreground, range: NSRange(location: 0, length: text.utf16.count))
        
        guard let languageString = language,
              let lang = Language(rawValue: languageString.lowercased()) else {
            return attributedString
        }
        
        let normalized = languageString.lowercased()
        if normalized != "swift", TreeSitterUI.isLanguageSupported(normalized) {
            return highlightWithTreeSitter(text, language: normalized, theme: theme)
        }
        
        switch lang {
        case .swift:
            highlightSwift(attributedString, theme: theme)
        case .python:
            highlightPython(attributedString, theme: theme)
        case .javascript:
            highlightJavaScript(attributedString, theme: theme)
        case .html:
            highlightHTML(attributedString, theme: theme)
        case .css:
            highlightCSS(attributedString, theme: theme)
        case .json:
            highlightJSON(attributedString, theme: theme)
        case .plaintext:
            break
        }
        
        return attributedString
    }
    
    private static func highlightSwift(_ attributedString: NSMutableAttributedString, theme: CodeTheme) {
        let keywords = ["class", "struct", "enum", "func", "var", "let", "if", "else", "for", "while", "switch", "case", "default", "return", "import", "private", "public", "internal", "static", "override", "init", "self", "super", "extension", "protocol", "typealias", "associatedtype", "mutating", "weak", "strong", "unowned", "lazy", "final", "open", "fileprivate", "inout", "throws", "rethrows", "async", "await"]
        
        let types = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "UIView", "UIViewController", "Data", "URL", "Date"]
        
        // Highlight keywords using theme color
        for keyword in keywords {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: theme.keyword)
        }
        
        // Highlight types using theme color
        for type in types {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: type))\\b", color: theme.type)
        }
        
        // Highlight strings using theme color
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: theme.string)
        
        // Highlight numbers using theme color
        highlightPattern(attributedString, pattern: "\\b\\d+\\.?\\d*\\b", color: theme.number)
        
        // Highlight comments using theme color
        highlightPattern(attributedString, pattern: "//.*$", color: theme.comment, options: [.anchorsMatchLines])
        highlightPattern(attributedString, pattern: "/\\*[\\s\\S]*?\\*/", color: theme.comment, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    }
    
    private static func highlightPython(_ attributedString: NSMutableAttributedString, theme: CodeTheme) {
        let keywords = ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "import", "from", "return", "yield", "lambda", "and", "or", "not", "in", "is", "None", "True", "False", "pass", "break", "continue", "global", "nonlocal", "async", "await"]
        
        let types = ["str", "int", "float", "bool", "list", "dict", "tuple", "set", "frozenset"]
        
        // Highlight keywords using theme color
        for keyword in keywords {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: theme.keyword)
        }
        
        // Highlight types using theme color
        for type in types {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: type))\\b", color: theme.type)
        }
        
        // Highlight strings using theme color
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: theme.string)
        highlightPattern(attributedString, pattern: "'[^']*'", color: theme.string)
        
        // Highlight numbers using theme color
        highlightPattern(attributedString, pattern: "\\b\\d+\\.?\\d*\\b", color: theme.number)
        
        // Highlight comments using theme color
        highlightPattern(attributedString, pattern: "#.*$", color: theme.comment, options: [.anchorsMatchLines])
    }
    
    private static func highlightJavaScript(_ attributedString: NSMutableAttributedString, theme: CodeTheme) {
        let keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "try", "catch", "finally", "throw", "new", "this", "typeof", "instanceof", "in", "of", "class", "extends", "super", "static", "async", "await", "import", "export", "from", "default"]
        
        // Highlight keywords using theme color
        for keyword in keywords {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: theme.keyword)
        }
        
        // Highlight strings using theme color
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: theme.string)
        highlightPattern(attributedString, pattern: "'[^']*'", color: theme.string)
        highlightPattern(attributedString, pattern: "`[^`]*`", color: theme.string)
        
        // Highlight numbers using theme color
        highlightPattern(attributedString, pattern: "\\b\\d+\\.?\\d*\\b", color: theme.number)
        
        // Highlight comments using theme color
        highlightPattern(attributedString, pattern: "//.*$", color: theme.comment, options: [.anchorsMatchLines])
        highlightPattern(attributedString, pattern: "/\\*[\\s\\S]*?\\*/", color: theme.comment, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    }
    
    private static func highlightHTML(_ attributedString: NSMutableAttributedString, theme: CodeTheme) {
        // Highlight tags using theme type color
        highlightPattern(attributedString, pattern: "<[^>]+>", color: theme.type)
        
        // Highlight attributes using theme keyword color
        highlightPattern(attributedString, pattern: "\\w+=\"[^\"]*\"", color: theme.keyword)
        
        // Highlight strings within tags (attribute values) using theme string color
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: theme.string)
    }
    
    private static func highlightCSS(_ attributedString: NSMutableAttributedString, theme: CodeTheme) {
        // Highlight selectors using theme type color
        highlightPattern(attributedString, pattern: "[.#]?\\w+(?=\\s*\\{)", color: theme.type)
        
        // Highlight properties using theme keyword color
        highlightPattern(attributedString, pattern: "\\w+(?=\\s*:)", color: theme.keyword)
        
        // Highlight values using theme number color
        highlightPattern(attributedString, pattern: ":\\s*[^;]+", color: theme.number)
        
        // Highlight strings using theme string color
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: theme.string)
        highlightPattern(attributedString, pattern: "'[^']*'", color: theme.string)
    }
    
    private static func highlightJSON(_ attributedString: NSMutableAttributedString, theme: CodeTheme) {
        // Highlight keys using theme type color
        highlightPattern(attributedString, pattern: "\"[^\"]+\"(?=\\s*:)", color: theme.type)
        
        // Highlight string values using theme string color
        highlightPattern(attributedString, pattern: ":\\s*\"[^\"]*\"", color: theme.string)
        
        // Highlight numbers using theme number color
        highlightPattern(attributedString, pattern: ":\\s*\\d+\\.?\\d*", color: theme.number)
        
        // Highlight booleans and null using theme keyword color
        highlightPattern(attributedString, pattern: "\\b(true|false|null)\\b", color: theme.keyword)
    }
    
    private static func highlightWithTreeSitter(_ text: String, language: String, theme: CodeTheme) -> NSAttributedString {
        let ranges = TreeSitterUI.highlightRanges(content: text, language: language)
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttribute(.foregroundColor, value: theme.foreground, range: NSRange(location: 0, length: text.utf16.count))
        for (range, category) in ranges {
            guard range.location >= 0, range.length >= 0, range.location + range.length <= text.utf16.count else { continue }
            let color: NSColor
            switch category {
            case "keyword": color = theme.keyword
            case "string": color = theme.string
            case "comment": color = theme.comment
            case "number": color = theme.number
            case "type": color = theme.type
            default: color = theme.foreground
            }
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }
        return attributed
    }
    
    private static func highlightPattern(_ attributedString: NSMutableAttributedString, pattern: String, color: NSColor, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        
        let text = attributedString.string
        let range = NSRange(location: 0, length: text.utf16.count)
        
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }
}
