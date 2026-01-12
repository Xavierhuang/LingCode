//
//  SyntaxHighlighter.swift
//  LingCode
//
//  Created by Weijia Huang on 1/11/26.
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
    
    static func highlight(_ text: String, language: String?) -> NSAttributedString {
        guard let languageString = language,
              let lang = Language(rawValue: languageString.lowercased()) else {
            return NSAttributedString(string: text)
        }
        
        let attributedString = NSMutableAttributedString(string: text)
        
        switch lang {
        case .swift:
            highlightSwift(attributedString)
        case .python:
            highlightPython(attributedString)
        case .javascript:
            highlightJavaScript(attributedString)
        case .html:
            highlightHTML(attributedString)
        case .css:
            highlightCSS(attributedString)
        case .json:
            highlightJSON(attributedString)
        case .plaintext:
            break
        }
        
        return attributedString
    }
    
    private static func highlightSwift(_ attributedString: NSMutableAttributedString) {
        let keywords = ["class", "struct", "enum", "func", "var", "let", "if", "else", "for", "while", "switch", "case", "default", "return", "import", "private", "public", "internal", "static", "override", "init", "self", "super", "extension", "protocol", "typealias", "associatedtype", "mutating", "weak", "strong", "unowned", "lazy", "final", "open", "fileprivate", "inout", "throws", "rethrows", "async", "await"]
        
        let types = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "UIView", "UIViewController", "Data", "URL", "Date"]
        
        // Highlight keywords
        for keyword in keywords {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: .systemPurple)
        }
        
        // Highlight types
        for type in types {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: type))\\b", color: .systemBlue)
        }
        
        // Highlight strings
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: .systemRed)
        
        // Highlight numbers
        highlightPattern(attributedString, pattern: "\\b\\d+\\.?\\d*\\b", color: .systemGreen)
        
        // Highlight comments
        highlightPattern(attributedString, pattern: "//.*$", color: .systemGray, options: [.anchorsMatchLines])
        highlightPattern(attributedString, pattern: "/\\*[\\s\\S]*?\\*/", color: .systemGray, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    }
    
    private static func highlightPython(_ attributedString: NSMutableAttributedString) {
        let keywords = ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "import", "from", "return", "yield", "lambda", "and", "or", "not", "in", "is", "None", "True", "False", "pass", "break", "continue", "global", "nonlocal", "async", "await"]
        
        let types = ["str", "int", "float", "bool", "list", "dict", "tuple", "set", "frozenset"]
        
        // Highlight keywords
        for keyword in keywords {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: .systemPurple)
        }
        
        // Highlight types
        for type in types {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: type))\\b", color: .systemBlue)
        }
        
        // Highlight strings
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: .systemRed)
        highlightPattern(attributedString, pattern: "'[^']*'", color: .systemRed)
        
        // Highlight numbers
        highlightPattern(attributedString, pattern: "\\b\\d+\\.?\\d*\\b", color: .systemGreen)
        
        // Highlight comments
        highlightPattern(attributedString, pattern: "#.*$", color: .systemGray, options: [.anchorsMatchLines])
    }
    
    private static func highlightJavaScript(_ attributedString: NSMutableAttributedString) {
        let keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "try", "catch", "finally", "throw", "new", "this", "typeof", "instanceof", "in", "of", "class", "extends", "super", "static", "async", "await", "import", "export", "from", "default"]
        
        // Highlight keywords
        for keyword in keywords {
            highlightPattern(attributedString, pattern: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", color: .systemPurple)
        }
        
        // Highlight strings
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: .systemRed)
        highlightPattern(attributedString, pattern: "'[^']*'", color: .systemRed)
        highlightPattern(attributedString, pattern: "`[^`]*`", color: .systemRed)
        
        // Highlight numbers
        highlightPattern(attributedString, pattern: "\\b\\d+\\.?\\d*\\b", color: .systemGreen)
        
        // Highlight comments
        highlightPattern(attributedString, pattern: "//.*$", color: .systemGray, options: [.anchorsMatchLines])
        highlightPattern(attributedString, pattern: "/\\*[\\s\\S]*?\\*/", color: .systemGray, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    }
    
    private static func highlightHTML(_ attributedString: NSMutableAttributedString) {
        // Highlight tags
        highlightPattern(attributedString, pattern: "<[^>]+>", color: .systemBlue)
        
        // Highlight attributes
        highlightPattern(attributedString, pattern: "\\w+=\"[^\"]*\"", color: .systemGreen)
        
        // Highlight strings within tags (attribute values)
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: .systemRed)
    }
    
    private static func highlightCSS(_ attributedString: NSMutableAttributedString) {
        // Highlight selectors
        highlightPattern(attributedString, pattern: "[.#]?\\w+(?=\\s*\\{)", color: .systemBlue)
        
        // Highlight properties
        highlightPattern(attributedString, pattern: "\\w+(?=\\s*:)", color: .systemPurple)
        
        // Highlight values
        highlightPattern(attributedString, pattern: ":\\s*[^;]+", color: .systemGreen)
        
        // Highlight strings
        highlightPattern(attributedString, pattern: "\"[^\"]*\"", color: .systemRed)
        highlightPattern(attributedString, pattern: "'[^']*'", color: .systemRed)
    }
    
    private static func highlightJSON(_ attributedString: NSMutableAttributedString) {
        // Highlight keys
        highlightPattern(attributedString, pattern: "\"[^\"]+\"(?=\\s*:)", color: .systemBlue)
        
        // Highlight string values
        highlightPattern(attributedString, pattern: ":\\s*\"[^\"]*\"", color: .systemRed)
        
        // Highlight numbers
        highlightPattern(attributedString, pattern: ":\\s*\\d+\\.?\\d*", color: .systemGreen)
        
        // Highlight booleans and null
        highlightPattern(attributedString, pattern: "\\b(true|false|null)\\b", color: .systemPurple)
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
