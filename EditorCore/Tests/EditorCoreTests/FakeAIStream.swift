//
//  FakeAIStream.swift
//  EditorCoreTests
//
//  Deterministic fake AI streams for testing
//

import Foundation

/// Deterministic fake AI stream generator
struct FakeAIStream {
    /// Generate a valid JSON edit stream
    static func jsonEditStream(filePath: String, operation: String, startLine: Int, endLine: Int, content: [String]) -> String {
        let contentJSON = content.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n      ")
        
        return """
        Here's the edit:
        
        ```json
        {
          "edits": [
            {
              "file": "\(filePath)",
              "operation": "\(operation)",
              "range": {
                "startLine": \(startLine),
                "endLine": \(endLine)
              },
              "content": [
                \(contentJSON)
              ]
            }
          ]
        }
        ```
        """
    }
    
    /// Generate a code block fallback edit stream
    static func codeBlockStream(filePath: String, language: String, content: String) -> String {
        return """
        I'll update \(filePath):
        
        `\(filePath)`:
        ```\(language)
        \(content)
        ```
        """
    }
    
    /// Generate a multi-file stream (JSON format)
    static func multiFileJSONStream(edits: [(filePath: String, operation: String, range: (start: Int, end: Int), content: [String])]) -> String {
        let editsJSON = edits.map { edit in
            let contentJSON = edit.content.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n        ")
            return """
            {
              "file": "\(edit.filePath)",
              "operation": "\(edit.operation)",
              "range": {
                "startLine": \(edit.range.start),
                "endLine": \(edit.range.end)
              },
              "content": [
                \(contentJSON)
              ]
            }
            """
        }.joined(separator: ",\n      ")
        
        return """
        ```json
        {
          "edits": [
            \(editsJSON)
          ]
        }
        ```
        """
    }
    
    /// Generate streaming chunks (simulates real streaming)
    static func streamingChunks(_ fullText: String, chunkSize: Int = 10) -> [String] {
        var chunks: [String] = []
        var remaining = fullText
        
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(chunkSize))
            chunks.append(chunk)
            remaining = String(remaining.dropFirst(chunkSize))
        }
        
        return chunks
    }
}
