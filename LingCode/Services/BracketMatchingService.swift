//
//  BracketMatchingService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit

struct BracketPair {
    let openPosition: Int
    let closePosition: Int
    let type: BracketType
    
    enum BracketType: Character {
        case parenthesis = "("
        case bracket = "["
        case brace = "{"
        case angleBracket = "<"
        
        var closingChar: Character {
            switch self {
            case .parenthesis: return ")"
            case .bracket: return "]"
            case .brace: return "}"
            case .angleBracket: return ">"
            }
        }
        
        static func from(opening: Character) -> BracketType? {
            switch opening {
            case "(": return .parenthesis
            case "[": return .bracket
            case "{": return .brace
            case "<": return .angleBracket
            default: return nil
            }
        }
        
        static func from(closing: Character) -> BracketType? {
            switch closing {
            case ")": return .parenthesis
            case "]": return .bracket
            case "}": return .brace
            case ">": return .angleBracket
            default: return nil
            }
        }
    }
}

class BracketMatchingService {
    static let shared = BracketMatchingService()
    
    private let bracketColors: [NSColor] = [
        NSColor.systemYellow,
        NSColor.systemPurple,
        NSColor.systemCyan,
        NSColor.systemOrange,
        NSColor.systemPink
    ]
    
    private init() {}
    
    func findMatchingBracket(
        in content: String,
        at position: Int
    ) -> Int? {
        guard position >= 0 && position < content.count else { return nil }
        
        let index = content.index(content.startIndex, offsetBy: position)
        let char = content[index]
        
        // Check if it's an opening bracket
        if let bracketType = BracketPair.BracketType.from(opening: char) {
            return findClosingBracket(in: content, from: position, type: bracketType)
        }
        
        // Check if it's a closing bracket
        if let bracketType = BracketPair.BracketType.from(closing: char) {
            return findOpeningBracket(in: content, from: position, type: bracketType)
        }
        
        return nil
    }
    
    private func findClosingBracket(
        in content: String,
        from position: Int,
        type: BracketPair.BracketType
    ) -> Int? {
        var depth = 1
        var currentPos = position + 1
        var inString = false
        var stringChar: Character?
        var prevChar: Character?
        
        while currentPos < content.count && depth > 0 {
            let index = content.index(content.startIndex, offsetBy: currentPos)
            let char = content[index]
            
            // Track string literals
            if (char == "\"" || char == "'") && prevChar != "\\" {
                if inString && char == stringChar {
                    inString = false
                    stringChar = nil
                } else if !inString {
                    inString = true
                    stringChar = char
                }
            }
            
            if !inString {
                if char == type.rawValue {
                    depth += 1
                } else if char == type.closingChar {
                    depth -= 1
                }
            }
            
            prevChar = char
            currentPos += 1
        }
        
        if depth == 0 {
            return currentPos - 1
        }
        
        return nil
    }
    
    private func findOpeningBracket(
        in content: String,
        from position: Int,
        type: BracketPair.BracketType
    ) -> Int? {
        var depth = 1
        var currentPos = position - 1
        
        while currentPos >= 0 && depth > 0 {
            let index = content.index(content.startIndex, offsetBy: currentPos)
            let char = content[index]
            
            if char == type.closingChar {
                depth += 1
            } else if char == type.rawValue {
                depth -= 1
            }
            
            currentPos -= 1
        }
        
        if depth == 0 {
            return currentPos + 1
        }
        
        return nil
    }
    
    func getAllBracketPairs(in content: String) -> [BracketPair] {
        var pairs: [BracketPair] = []
        var stacks: [BracketPair.BracketType: [(position: Int, depth: Int)]] = [:]
        var depthCounter: [BracketPair.BracketType: Int] = [:]
        
        var inString = false
        var stringChar: Character?
        var prevChar: Character?
        
        for (index, char) in content.enumerated() {
            // Track string literals
            if (char == "\"" || char == "'") && prevChar != "\\" {
                if inString && char == stringChar {
                    inString = false
                    stringChar = nil
                } else if !inString {
                    inString = true
                    stringChar = char
                }
            }
            
            if !inString {
                if let type = BracketPair.BracketType.from(opening: char) {
                    let depth = depthCounter[type, default: 0]
                    stacks[type, default: []].append((position: index, depth: depth))
                    depthCounter[type] = depth + 1
                } else if let type = BracketPair.BracketType.from(closing: char) {
                    if var stack = stacks[type], !stack.isEmpty {
                        let (openPos, _) = stack.removeLast()
                        stacks[type] = stack
                        pairs.append(BracketPair(openPosition: openPos, closePosition: index, type: type))
                        depthCounter[type, default: 1] -= 1
                    }
                }
            }
            
            prevChar = char
        }
        
        return pairs
    }
    
    func colorForDepth(_ depth: Int) -> NSColor {
        return bracketColors[depth % bracketColors.count]
    }
    
    func highlightBrackets(
        in attributedString: NSMutableAttributedString,
        pairs: [BracketPair],
        cursorPosition: Int?
    ) {
        // Rainbow brackets
        var depthMap: [BracketPair.BracketType: Int] = [:]
        
        // Sort by position
        let sortedPairs = pairs.sorted { $0.openPosition < $1.openPosition }
        
        for pair in sortedPairs {
            let depth = depthMap[pair.type, default: 0]
            let color = colorForDepth(depth)
            
            // Color opening bracket
            if pair.openPosition < attributedString.length {
                attributedString.addAttribute(.foregroundColor, value: color, range: NSRange(location: pair.openPosition, length: 1))
            }
            
            // Color closing bracket
            if pair.closePosition < attributedString.length {
                attributedString.addAttribute(.foregroundColor, value: color, range: NSRange(location: pair.closePosition, length: 1))
            }
            
            depthMap[pair.type] = depth + 1
        }
        
        // Highlight matching bracket at cursor
        if let position = cursorPosition {
            if let matchPos = findMatchingBracket(in: attributedString.string, at: position) {
                let highlightColor = NSColor.systemYellow.withAlphaComponent(0.3)
                
                if position < attributedString.length {
                    attributedString.addAttribute(.backgroundColor, value: highlightColor, range: NSRange(location: position, length: 1))
                }
                if matchPos < attributedString.length {
                    attributedString.addAttribute(.backgroundColor, value: highlightColor, range: NSRange(location: matchPos, length: 1))
                }
            }
        }
    }
}

