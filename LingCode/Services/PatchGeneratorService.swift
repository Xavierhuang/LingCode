//
//  PatchGeneratorService.swift
//  LingCode
//
//  Cursor-like patch generator - converts AI responses to structured edits
//

import Foundation

/// Represents a structured code edit (patch)
struct CodePatch: Identifiable {
    let id = UUID()
    let filePath: String
    let operation: PatchOperation
    let range: PatchRange?
    let content: [String]
    let description: String?
    
    enum PatchOperation: String {
        case insert
        case replace
        case delete
    }
    
    struct PatchRange {
        let startLine: Int
        let endLine: Int
        let startColumn: Int?
        let endColumn: Int?
    }
}

/// Service that generates structured patches from AI responses
class PatchGeneratorService {
    static let shared = PatchGeneratorService()
    
    private init() {}
    
    /// Parse AI response and extract structured patches
    func generatePatches(from response: String, projectURL: URL?) -> [CodePatch] {
        var patches: [CodePatch] = []
        
        // Try to parse JSON edit format first
        if let jsonPatches = parseJSONEdits(from: response, projectURL: projectURL) {
            patches.append(contentsOf: jsonPatches)
        }
        
        // Also parse file blocks (backup method)
        let fileBlocks = parseFileBlocks(from: response, projectURL: projectURL)
        patches.append(contentsOf: fileBlocks)
        
        return patches
    }
    
    /// Parse JSON edit format
    private func parseJSONEdits(from response: String, projectURL: URL?) -> [CodePatch]? {
        // Look for JSON edit blocks
        let jsonPattern = #"```json\s*\{[^`]+\}\s*```"#
        guard let regex = try? NSRegularExpression(pattern: jsonPattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: response, range: NSRange(location: 0, length: response.utf16.count)),
              let jsonRange = Range(match.range, in: response) else {
            return nil
        }
        
        let jsonString = String(response[jsonRange])
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let edits = json["edits"] as? [[String: Any]] else {
            return nil
        }
        
        var patches: [CodePatch] = []
        
        for edit in edits {
            guard let file = edit["file"] as? String,
                  let operationString = edit["operation"] as? String,
                  let operation = CodePatch.PatchOperation(rawValue: operationString) else {
                continue
            }
            
            var range: CodePatch.PatchRange? = nil
            if let rangeDict = edit["range"] as? [String: Any],
               let startLine = rangeDict["startLine"] as? Int,
               let endLine = rangeDict["endLine"] as? Int {
                range = CodePatch.PatchRange(
                    startLine: startLine,
                    endLine: endLine,
                    startColumn: rangeDict["startColumn"] as? Int,
                    endColumn: rangeDict["endColumn"] as? Int
                )
            }
            
            let content = edit["content"] as? [String] ?? []
            let description = edit["description"] as? String
            
            let patch = CodePatch(
                filePath: file,
                operation: operation,
                range: range,
                content: content,
                description: description
            )
            
            patches.append(patch)
        }
        
        return patches
    }
    
    /// Parse file blocks (for both new and existing files)
    private func parseFileBlocks(from response: String, projectURL: URL?) -> [CodePatch] {
        var patches: [CodePatch] = []
        
        // Pattern: `path/to/file.ext`:
        let filePattern = #"`([^`]+)`:\s*\n```(\w+)?\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: filePattern, options: []) else {
            return patches
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count))
        
        for match in matches {
            guard match.numberOfRanges >= 4,
                  let filePathRange = Range(match.range(at: 1), in: response),
                  let contentRange = Range(match.range(at: 3), in: response) else {
                continue
            }
            
            let filePath = String(response[filePathRange])
            let content = String(response[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty content - don't create patches for empty files
            guard !content.isEmpty else {
                print("⚠️ Warning: Skipping empty file content for \(filePath)")
                continue
            }
            
            let lines = content.components(separatedBy: .newlines)
            
            let fullPath: String
            if let projectURL = projectURL {
                fullPath = (projectURL.path as NSString).appendingPathComponent(filePath)
            } else {
                fullPath = filePath
            }
            
            // Determine if this is a new file or edit
            let operation: CodePatch.PatchOperation
            let fileExists = FileManager.default.fileExists(atPath: fullPath)
            operation = fileExists ? .replace : .insert
            
            // For existing files, replace entire file (no range = full replacement)
            // For new files, insert (no range = new file)
            let patch = CodePatch(
                filePath: fullPath,
                operation: operation,
                range: nil, // Full file replacement/insertion
                content: lines,
                description: nil
            )
            
            patches.append(patch)
        }
        
        return patches
    }
    
    /// Apply a patch to a file
    func applyPatch(_ patch: CodePatch) throws -> String {
        let fileURL = URL(fileURLWithPath: patch.filePath)
        
        // Read existing content
        let existingContent: String
        if FileManager.default.fileExists(atPath: patch.filePath) {
            existingContent = try String(contentsOf: fileURL, encoding: .utf8)
        } else {
            existingContent = ""
        }
        
        let existingLines = existingContent.components(separatedBy: .newlines)
        
        switch patch.operation {
        case .insert:
            // Insert at specified line, or append
            if let range = patch.range {
                var newLines = existingLines
                let insertIndex = min(range.startLine - 1, newLines.count)
                newLines.insert(contentsOf: patch.content, at: insertIndex)
                return newLines.joined(separator: "\n")
            } else {
                // Append to end
                return existingContent + "\n" + patch.content.joined(separator: "\n")
            }
            
        case .replace:
            if let range = patch.range {
                // Replace specific range
                var newLines = existingLines
                let startIndex = max(0, range.startLine - 1)
                let endIndex = min(range.endLine, newLines.count)
                
                // Fix: Ensure startIndex <= endIndex
                if startIndex > endIndex {
                    // Invalid range - replace entire file as fallback
                    let newContent = patch.content.joined(separator: "\n")
                    guard !newContent.isEmpty else {
                        throw NSError(domain: "PatchGeneratorService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot replace with empty content"])
                    }
                    return newContent
                }
                
                newLines.replaceSubrange(startIndex..<endIndex, with: patch.content)
                return newLines.joined(separator: "\n")
            } else {
                // Replace entire file
                let newContent = patch.content.joined(separator: "\n")
                // Safety check: Don't allow replacing with completely empty content unless explicitly deleting
                guard !newContent.isEmpty || patch.content.isEmpty == false else {
                    throw NSError(domain: "PatchGeneratorService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot replace file with empty content"])
                }
                return newContent
            }
            
        case .delete:
            if let range = patch.range {
                var newLines = existingLines
                let startIndex = max(0, range.startLine - 1)
                let endIndex = min(range.endLine, newLines.count)
                newLines.removeSubrange(startIndex..<endIndex)
                return newLines.joined(separator: "\n")
            } else {
                return "" // Delete entire file
            }
        }
    }
}
