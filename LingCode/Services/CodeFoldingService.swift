//
//  CodeFoldingService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct FoldableRegion: Identifiable {
    let id = UUID()
    let startLine: Int
    let endLine: Int
    let kind: FoldKind
    var isCollapsed: Bool = false
    
    enum FoldKind {
        case braces       // { }
        case brackets     // [ ]
        case parentheses  // ( )
        case comment      // /* */ or multi-line comments
        case region       // #region / #endregion
        case imports      // import block
    }
    
    var lineCount: Int {
        return endLine - startLine + 1
    }
}

class CodeFoldingService {
    static let shared = CodeFoldingService()
    
    private init() {}
    
    func findFoldableRegions(in content: String, language: String?) -> [FoldableRegion] {
        var regions: [FoldableRegion] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Find brace-delimited blocks
        regions.append(contentsOf: findBraceBlocks(lines))
        
        // Find multi-line comments
        regions.append(contentsOf: findCommentBlocks(lines, language: language))
        
        // Find import blocks
        regions.append(contentsOf: findImportBlocks(lines, language: language))
        
        // Find region markers
        regions.append(contentsOf: findRegionMarkers(lines))
        
        // Sort by start line
        return regions.sorted { $0.startLine < $1.startLine }
    }
    
    private func findBraceBlocks(_ lines: [String]) -> [FoldableRegion] {
        var regions: [FoldableRegion] = []
        var braceStack: [(line: Int, type: Character)] = []
        
        for (lineIndex, line) in lines.enumerated() {
            var inString = false
            var stringChar: Character?
            var prevChar: Character?
            
            for char in line {
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
                    if char == "{" || char == "[" || char == "(" {
                        braceStack.append((line: lineIndex, type: char))
                    } else if char == "}" || char == "]" || char == ")" {
                        let openChar: Character
                        let kind: FoldableRegion.FoldKind
                        
                        switch char {
                        case "}":
                            openChar = "{"
                            kind = .braces
                        case "]":
                            openChar = "["
                            kind = .brackets
                        case ")":
                            openChar = "("
                            kind = .parentheses
                        default:
                            prevChar = char
                            continue
                        }
                        
                        // Find matching open brace
                        if let index = braceStack.lastIndex(where: { $0.type == openChar }) {
                            let openLine = braceStack[index].line
                            braceStack.remove(at: index)
                            
                            // Only create region if it spans multiple lines
                            if lineIndex > openLine {
                                regions.append(FoldableRegion(
                                    startLine: openLine,
                                    endLine: lineIndex,
                                    kind: kind
                                ))
                            }
                        }
                    }
                }
                
                prevChar = char
            }
        }
        
        return regions
    }
    
    private func findCommentBlocks(_ lines: [String], language: String?) -> [FoldableRegion] {
        var regions: [FoldableRegion] = []
        var commentStart: Int?
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // C-style multi-line comments
            if trimmed.contains("/*") && commentStart == nil {
                commentStart = lineIndex
            }
            
            if trimmed.contains("*/") && commentStart != nil {
                if lineIndex > commentStart! {
                    regions.append(FoldableRegion(
                        startLine: commentStart!,
                        endLine: lineIndex,
                        kind: .comment
                    ))
                }
                commentStart = nil
            }
            
            // Python/Ruby multi-line strings (docstrings)
            if language == "python" {
                if trimmed.hasPrefix("\"\"\"") || trimmed.hasPrefix("'''") {
                    if commentStart == nil {
                        commentStart = lineIndex
                    } else {
                        if lineIndex > commentStart! {
                            regions.append(FoldableRegion(
                                startLine: commentStart!,
                                endLine: lineIndex,
                                kind: .comment
                            ))
                        }
                        commentStart = nil
                    }
                }
            }
        }
        
        return regions
    }
    
    private func findImportBlocks(_ lines: [String], language: String?) -> [FoldableRegion] {
        var regions: [FoldableRegion] = []
        var importStart: Int?
        var lastImportLine: Int?
        
        let importKeywords: [String]
        switch language?.lowercased() {
        case "swift":
            importKeywords = ["import"]
        case "python":
            importKeywords = ["import", "from"]
        case "javascript", "typescript":
            importKeywords = ["import", "require"]
        case "java", "kotlin":
            importKeywords = ["import"]
        case "go":
            importKeywords = ["import"]
        default:
            importKeywords = ["import", "using", "#include", "require"]
        }
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isImport = importKeywords.contains { trimmed.hasPrefix($0) }
            
            if isImport {
                if importStart == nil {
                    importStart = lineIndex
                }
                lastImportLine = lineIndex
            } else if importStart != nil && !trimmed.isEmpty {
                // End of import block
                if let start = importStart, let end = lastImportLine, end > start {
                    regions.append(FoldableRegion(
                        startLine: start,
                        endLine: end,
                        kind: .imports
                    ))
                }
                importStart = nil
                lastImportLine = nil
            }
        }
        
        // Handle trailing import block
        if let start = importStart, let end = lastImportLine, end > start {
            regions.append(FoldableRegion(
                startLine: start,
                endLine: end,
                kind: .imports
            ))
        }
        
        return regions
    }
    
    private func findRegionMarkers(_ lines: [String]) -> [FoldableRegion] {
        var regions: [FoldableRegion] = []
        var regionStack: [(line: Int, name: String)] = []
        
        let regionPatterns = [
            (#"#region\s*(.*)"#, #"#endregion"#),
            (#"// MARK: -\s*(.*)"#, nil),
            (#"// MARK:\s*(.*)"#, nil),
            (#"//region\s*(.*)"#, #"//endregion"#),
            (#"//<editor-fold.*>"#, #"//</editor-fold>"#)
        ]
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            for (startPattern, endPattern) in regionPatterns {
                if let regex = try? NSRegularExpression(pattern: startPattern, options: []),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    let name = match.numberOfRanges > 1 ?
                        String(trimmed[Range(match.range(at: 1), in: trimmed)!]) : ""
                    
                    if endPattern == nil {
                        // MARK-style - look for next MARK or end of file
                        // For now, don't create region
                    } else {
                        regionStack.append((line: lineIndex, name: name))
                    }
                }
                
                if let endPattern = endPattern,
                   trimmed.range(of: endPattern, options: .regularExpression) != nil,
                   let region = regionStack.popLast() {
                    if lineIndex > region.line {
                        regions.append(FoldableRegion(
                            startLine: region.line,
                            endLine: lineIndex,
                            kind: .region
                        ))
                    }
                }
            }
        }
        
        return regions
    }
    
    func applyFolding(to content: String, with regions: [FoldableRegion]) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var skipUntil: Int?
        
        for (index, line) in lines.enumerated() {
            if let skip = skipUntil {
                if index >= skip {
                    skipUntil = nil
                    result.append(line)
                }
                continue
            }
            
            if let region = regions.first(where: { $0.startLine == index && $0.isCollapsed }) {
                // Add folded indicator
                let indicator = "... (\(region.lineCount - 1) lines hidden)"
                result.append(line + " " + indicator)
                skipUntil = region.endLine
            } else {
                result.append(line)
            }
        }
        
        return result.joined(separator: "\n")
    }
}

