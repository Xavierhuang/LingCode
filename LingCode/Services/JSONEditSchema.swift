//
//  JSONEditSchema.swift
//  LingCode
//
//  Cursor-compatible JSON edit schema for structured code modifications
//

import Foundation

struct EditSchema: Codable {
    let edits: [Edit]
}

struct Edit: Codable {
    let file: String
    let operation: Operation
    let range: EditRange?
    let anchor: Anchor?
    let content: [String]
    
    enum Operation: String, Codable {
        case insert = "insert"
        case replace = "replace"
        case delete = "delete"
    }
}

struct Anchor: Codable {
    let type: AnchorType
    let name: String
    let parent: String?
    let childIndex: Int?
    
    enum AnchorType: String, Codable {
        case function = "function"
        case classSymbol = "class"
        case method = "method"
        case structSymbol = "struct"
        case enumSymbol = "enum"
        case protocolSymbol = "protocol"
        case property = "property"
        case variable = "variable"
    }
}

struct EditRange: Codable {
    let startLine: Int
    let endLine: Int
    
    var isValid: Bool {
        startLine > 0 && endLine >= startLine
    }
}

enum EditError: Error, LocalizedError {
    case invalidRange
    case fileNotFound
    case tooLarge
    case fileOutsideWorkspace
    case editOverlaps
    case invalidOperation
    
    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "Invalid range: startLine must be <= endLine"
        case .fileNotFound:
            return "File not found"
        case .tooLarge:
            return "Edit content exceeds maximum size (500 lines)"
        case .fileOutsideWorkspace:
            return "File is outside the workspace"
        case .editOverlaps:
            return "Edit overlaps with generated code blocks"
        case .invalidOperation:
            return "Invalid operation type"
        }
    }
}

class JSONEditSchemaService {
    static let shared = JSONEditSchemaService()
    
    private init() {}
    
    /// Parse JSON edit schema from AI response
    func parseEdits(from response: String) -> [Edit]? {
        // Try to find JSON block
        let jsonPattern = #"```json\s*(\{[\s\S]*?\})\s*```"#
        guard let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..<response.endIndex, in: response)),
              let jsonRange = Range(match.range(at: 1), in: response) else {
            return nil
        }
        
        let jsonString = String(response[jsonRange])
        
        guard let jsonData = jsonString.data(using: .utf8),
              let schema = try? JSONDecoder().decode(EditSchema.self, from: jsonData) else {
            return nil
        }
        
        return schema.edits
    }
    
    /// Validate an edit
    func validate(edit: Edit, workspaceURL: URL) throws {
        // Validate range
        if let range = edit.range, !range.isValid {
            throw EditError.invalidRange
        }
        
        // Validate file exists
        let fileURL = workspaceURL.appendingPathComponent(edit.file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EditError.fileNotFound
        }
        
        // Validate file is within workspace
        let filePath = fileURL.path
        let workspacePath = workspaceURL.path
        guard filePath.hasPrefix(workspacePath) else {
            throw EditError.fileOutsideWorkspace
        }
        
        // Validate content size
        if edit.content.count > 500 {
            throw EditError.tooLarge
        }
        
        // Validate operation
        switch edit.operation {
        case .insert:
            guard edit.range != nil else {
                throw EditError.invalidOperation
            }
        case .replace:
            guard edit.range != nil else {
                throw EditError.invalidOperation
            }
        case .delete:
            guard edit.range != nil else {
                throw EditError.invalidOperation
            }
        }
    }
    
    /// Apply a single edit (with AST anchor resolution)
    func apply(edit: Edit, in workspaceURL: URL) throws {
        let fileURL = workspaceURL.appendingPathComponent(edit.file)
        let existingContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let lines = existingContent.components(separatedBy: .newlines)
        
        var newLines = lines
        
        // Try AST anchor first, fallback to range
        var resolvedRange: EditRange? = edit.range
        
        if let anchor = edit.anchor {
            if let anchorRange = ASTAnchorService.shared.resolveAnchor(anchor, in: fileURL) {
                resolvedRange = anchorRange
            } else if edit.range == nil {
                // Anchor failed and no range provided - error
                throw EditError.invalidRange
            }
            // If anchor fails but range exists, use range (fallback)
        }
        
        guard let range = resolvedRange else {
            // No range means replace entire file
            if edit.operation == .replace {
                try edit.content.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                return
            }
            throw EditError.invalidRange
        }
        
        let startIndex = max(0, range.startLine - 1)
        let endIndex = min(lines.count, range.endLine)
        
        switch edit.operation {
        case .insert:
            // Insert at startLine
            if startIndex <= newLines.count {
                newLines.insert(contentsOf: edit.content, at: startIndex)
            }
            
        case .replace:
            // Replace lines from startLine to endLine
            if startIndex < newLines.count {
                let safeEndIndex = min(endIndex, newLines.count)
                newLines.replaceSubrange(startIndex..<safeEndIndex, with: edit.content)
            }
            
        case .delete:
            // Delete lines from startLine to endLine
            if startIndex < newLines.count {
                let safeEndIndex = min(endIndex, newLines.count)
                newLines.removeSubrange(startIndex..<safeEndIndex)
            }
        }
        
        let newContent = newLines.joined(separator: "\n")
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    /// Check if edits modify more than 30% of a file
    func checkModificationPercentage(edit: Edit, in workspaceURL: URL) -> Double {
        let fileURL = workspaceURL.appendingPathComponent(edit.file)
        guard let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return 0.0
        }
        
        let totalLines = existingContent.components(separatedBy: .newlines).count
        guard totalLines > 0, let range = edit.range else {
            return edit.operation == .replace ? 1.0 : 0.0
        }
        
        let modifiedLines = range.endLine - range.startLine + 1
        return Double(modifiedLines) / Double(totalLines)
    }
}
