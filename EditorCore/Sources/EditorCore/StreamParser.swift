//
//  StreamParser.swift
//  EditorCore
//
//  Parser for streaming AI text output
//

import Foundation

/// Parser for extracting structured edits from streaming AI text
public struct StreamParser {
    public init() {}
    
    /// Parse streaming text and extract file edits
    func parseStreamingText(
        _ text: String,
        fileSnapshots: [String: FileSnapshot]
    ) -> [ParsedEdit] {
        var edits: [ParsedEdit] = []
        
        // Try JSON edit format first (preferred for targeted edits)
        if let jsonEdits = parseJSONEdits(text) {
            edits.append(contentsOf: jsonEdits)
        }
        
        // Fall back to code block parsing
        if edits.isEmpty {
            edits.append(contentsOf: parseCodeBlocks(text, fileSnapshots: fileSnapshots))
        }
        
        return edits
    }
    
    // MARK: - JSON Edit Format
    
    private struct JSONEdit: Codable {
        let file: String
        let operation: String // "insert", "replace", "delete"
        let range: LineRange?
        let content: [String]
    }
    
    private struct LineRange: Codable {
        let startLine: Int
        let endLine: Int
    }
    
    private struct JSONEditResponse: Codable {
        let edits: [JSONEdit]
    }
    
    private func parseJSONEdits(_ text: String) -> [ParsedEdit]? {
        // Look for JSON code blocks
        let jsonBlockPattern = #"```json\s*(\{.*?\})\s*```"#
        guard let regex = try? NSRegularExpression(pattern: jsonBlockPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let jsonNSRange = match.range(at: 1)
        guard jsonNSRange.location != NSNotFound,
              let jsonRange = Range(jsonNSRange, in: text),
              let jsonData = String(text[jsonRange]).data(using: .utf8) else {
            return nil
        }
        
        guard let response = try? JSONDecoder().decode(JSONEditResponse.self, from: jsonData) else {
            return nil
        }
        
        return response.edits.compactMap { jsonEdit -> ParsedEdit? in
            let content = jsonEdit.content.joined(separator: "\n")
            return ParsedEdit(
                filePath: jsonEdit.file,
                content: content,
                operation: jsonEdit.operation,
                range: jsonEdit.range.map { r in
                    (start: r.startLine, end: r.endLine)
                }
            )
        }
    }
    
    // MARK: - Code Block Parsing
    
    private func parseCodeBlocks(_ text: String, fileSnapshots: [String: FileSnapshot]) -> [ParsedEdit] {
        var edits: [ParsedEdit] = []
        
        // Pattern: `path/to/file.ext`:\n```language\n...\n```
        let pattern = #"`?([^\s`]+)`?\s*:\s*```(\w+)?\s*\n(.*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return edits
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            guard match.numberOfRanges >= 4 else {
                continue
            }
            
            let filePathNSRange = match.range(at: 1)
            let contentNSRange = match.range(at: 3)
            
            guard filePathNSRange.location != NSNotFound,
                  contentNSRange.location != NSNotFound,
                  let filePathRange = Range(filePathNSRange, in: text),
                  let contentRange = Range(contentNSRange, in: text) else {
                continue
            }
            
            let filePath = String(text[filePathRange])
            let content = String(text[contentRange])
            
            edits.append(ParsedEdit(
                filePath: filePath,
                content: content,
                operation: "replace",
                range: nil
            ))
        }
        
        return edits
    }
}

// MARK: - ParsedEdit

/// Intermediate representation of a parsed edit
internal struct ParsedEdit {
    let filePath: String
    let content: String
    let operation: String
    let range: (start: Int, end: Int)?
}
