//
//  SyntaxHighlighter.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit

struct SyntaxHighlighter {
    static func highlight(_ text: String, language: String?) -> NSAttributedString {
        guard let language = language else {
            return NSAttributedString(string: text)
        }
        
        let attributedString = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        
        switch language.lowercased() {
        case "swift":
            highlightSwift(text, attributedString: attributedString, range: fullRange)
        case "python":
            highlightPython(text, attributedString: attributedString, range: fullRange)
        case "javascript", "typescript":
            highlightJavaScript(text, attributedString: attributedString, range: fullRange)
        case "html":
            highlightHTML(text, attributedString: attributedString, range: fullRange)
        case "css":
            highlightCSS(text, attributedString: attributedString, range: fullRange)
        case "json":
            highlightJSON(text, attributedString: attributedString, range: fullRange)
        case "markdown":
            highlightMarkdown(text, attributedString: attributedString, range: fullRange)
        default:
            break
        }
        
        return attributedString
    }
    
    private static func highlightSwift(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        let keywords = ["func", "var", "let", "class", "struct", "enum", "protocol", "extension", "import", "if", "else", "for", "while", "switch", "case", "default", "return", "true", "false", "nil", "self", "super", "init", "deinit", "guard", "defer", "try", "catch", "throw", "async", "await", "in", "where", "as", "is", "public", "private", "internal", "static", "final", "override", "convenience", "required", "weak", "unowned", "lazy", "mutating", "nonmutating", "subscript", "associatedtype", "typealias", "precedencegroup", "infix", "prefix", "postfix"]
        
        highlightKeywords(text, attributedString: attributedString, keywords: keywords, color: .systemBlue)
        highlightStrings(text, attributedString: attributedString, color: .systemGreen)
        highlightComments(text, attributedString: attributedString, color: .systemGray)
    }
    
    private static func highlightPython(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        let keywords = ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "import", "from", "return", "yield", "pass", "break", "continue", "raise", "assert", "lambda", "and", "or", "not", "in", "is", "None", "True", "False", "async", "await", "global", "nonlocal"]
        
        highlightKeywords(text, attributedString: attributedString, keywords: keywords, color: .systemBlue)
        highlightStrings(text, attributedString: attributedString, color: .systemGreen)
        highlightComments(text, attributedString: attributedString, color: .systemGray)
    }
    
    private static func highlightJavaScript(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        let keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue", "try", "catch", "finally", "throw", "new", "this", "class", "extends", "super", "async", "await", "import", "export", "from", "as", "default", "typeof", "instanceof", "in", "of", "true", "false", "null", "undefined"]
        
        highlightKeywords(text, attributedString: attributedString, keywords: keywords, color: .systemBlue)
        highlightStrings(text, attributedString: attributedString, color: .systemGreen)
        highlightComments(text, attributedString: attributedString, color: .systemGray)
    }
    
    private static func highlightHTML(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        let tagPattern = "<(/?)([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*>"
        highlightRegex(text, attributedString: attributedString, pattern: tagPattern, color: .systemPurple)
        highlightStrings(text, attributedString: attributedString, color: .systemGreen)
        highlightComments(text, attributedString: attributedString, color: .systemGray)
    }
    
    private static func highlightCSS(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        let properties = ["color", "background", "margin", "padding", "border", "width", "height", "display", "position", "flex", "grid", "font", "text", "align", "justify", "overflow", "z-index", "opacity", "transform", "transition", "animation"]
        
        highlightKeywords(text, attributedString: attributedString, keywords: properties, color: .systemOrange)
        highlightStrings(text, attributedString: attributedString, color: .systemGreen)
        highlightComments(text, attributedString: attributedString, color: .systemGray)
        
        let colorPattern = "#[0-9a-fA-F]{3,6}|rgb\\([^)]+\\)|rgba\\([^)]+\\)"
        highlightRegex(text, attributedString: attributedString, pattern: colorPattern, color: .systemTeal)
    }
    
    private static func highlightJSON(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        highlightStrings(text, attributedString: attributedString, color: .systemGreen)
        highlightKeywords(text, attributedString: attributedString, keywords: ["true", "false", "null"], color: .systemBlue)
    }
    
    private static func highlightMarkdown(_ text: String, attributedString: NSMutableAttributedString, range: NSRange) {
        let headingPattern = "^#{1,6}\\s+.+$"
        highlightRegex(text, attributedString: attributedString, pattern: headingPattern, options: [.anchorsMatchLines], color: .systemBlue)
        
        let boldPattern = "\\*\\*[^*]+\\*\\*|__[^_]+__"
        highlightRegex(text, attributedString: attributedString, pattern: boldPattern, color: .systemOrange)
        
        let codePattern = "`[^`]+`"
        highlightRegex(text, attributedString: attributedString, pattern: codePattern, color: .systemPurple)
        
        highlightComments(text, attributedString: attributedString, color: .systemGray)
    }
    
    private static func highlightKeywords(_ text: String, attributedString: NSMutableAttributedString, keywords: [String], color: NSColor) {
        for keyword in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            highlightRegex(text, attributedString: attributedString, pattern: pattern, color: color)
        }
    }
    
    private static func highlightStrings(_ text: String, attributedString: NSMutableAttributedString, color: NSColor) {
        let patterns = [
            "\"([^\"\\\\]|\\\\.)*\"",
            "'([^'\\\\]|\\\\.)*'",
            "`([^`\\\\]|\\\\.)*`"
        ]
        
        for pattern in patterns {
            highlightRegex(text, attributedString: attributedString, pattern: pattern, color: color)
        }
    }
    
    private static func highlightComments(_ text: String, attributedString: NSMutableAttributedString, color: NSColor) {
        let patterns = [
            "//.*$",
            "/\\*[\\s\\S]*?\\*/"
        ]
        
        for pattern in patterns {
            highlightRegex(text, attributedString: attributedString, pattern: pattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators], color: color)
        }
    }
    
    private static func highlightRegex(_ text: String, attributedString: NSMutableAttributedString, pattern: String, options: NSRegularExpression.Options = [], color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches {
            attributedString.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

