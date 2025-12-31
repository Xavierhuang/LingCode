//
//  SnippetsView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import Combine

struct CodeSnippet: Identifiable, Codable {
    let id: UUID
    var name: String
    var prefix: String
    var body: String
    var language: String?
    var description: String
    
    init(id: UUID = UUID(), name: String, prefix: String, body: String, language: String? = nil, description: String = "") {
        self.id = id
        self.name = name
        self.prefix = prefix
        self.body = body
        self.language = language
        self.description = description
    }
}

class SnippetManager: ObservableObject {
    static let shared = SnippetManager()
    
    @Published var snippets: [CodeSnippet] = []
    
    private init() {
        loadDefaultSnippets()
        loadCustomSnippets()
    }
    
    func getSnippet(for prefix: String, language: String?) -> CodeSnippet? {
        return snippets.first { snippet in
            snippet.prefix == prefix && (snippet.language == nil || snippet.language == language)
        }
    }
    
    func insertSnippet(_ snippet: CodeSnippet, at position: Int, in text: String) -> String {
        let beforeCursor = String(text.prefix(position))
        let afterCursor = String(text.suffix(text.count - position))
        
        let currentLine = beforeCursor.components(separatedBy: .newlines).last ?? ""
        let indent = String(currentLine.prefix { $0 == " " || $0 == "\t" })
        
        let snippetBody = snippet.body
            .replacingOccurrences(of: "${1}", with: "")
            .replacingOccurrences(of: "${2}", with: "")
            .replacingOccurrences(of: "${3}", with: "")
        
        let indentedBody = snippetBody
            .components(separatedBy: .newlines)
            .map { line in
                if line.isEmpty {
                    return line
                }
                return indent + line
            }
            .joined(separator: "\n")
        
        return beforeCursor + indentedBody + afterCursor
    }
    
    private func getDefaultSnippets() -> [CodeSnippet] {
        return [
            CodeSnippet(
                name: "Swift Function",
                prefix: "func",
                body: "func ${1:functionName}(${2:parameters}) -> ${3:ReturnType} {\n    ${4:// body}\n}",
                language: "swift",
                description: "Swift function template"
            ),
            CodeSnippet(
                name: "Swift Class",
                prefix: "class",
                body: "class ${1:ClassName} {\n    ${2:// properties and methods}\n}",
                language: "swift",
                description: "Swift class template"
            ),
            CodeSnippet(
                name: "Python Function",
                prefix: "def",
                body: "def ${1:function_name}(${2:parameters}):\n    ${3:pass}",
                language: "python",
                description: "Python function template"
            ),
            CodeSnippet(
                name: "JavaScript Function",
                prefix: "function",
                body: "function ${1:functionName}(${2:parameters}) {\n    ${3:// body}\n}",
                language: "javascript",
                description: "JavaScript function template"
            ),
            CodeSnippet(
                name: "If Statement",
                prefix: "if",
                body: "if (${1:condition}) {\n    ${2:// body}\n}",
                language: nil,
                description: "If statement template"
            ),
            CodeSnippet(
                name: "For Loop",
                prefix: "for",
                body: "for (${1:i} = 0; ${1:i} < ${2:length}; ${1:i}++) {\n    ${3:// body}\n}",
                language: nil,
                description: "For loop template"
            )
        ]
    }
    
    private func loadDefaultSnippets() {
        snippets = getDefaultSnippets()
    }
    
    private func loadCustomSnippets() {
        // Load from UserDefaults or file
        if let data = UserDefaults.standard.data(forKey: "custom_snippets"),
           let custom = try? JSONDecoder().decode([CodeSnippet].self, from: data) {
            snippets.append(contentsOf: custom)
        }
    }
    
    func saveCustomSnippets() {
        let defaultIds = Set(getDefaultSnippets().map { $0.id })
        let custom = snippets.filter { !defaultIds.contains($0.id) }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: "custom_snippets")
        }
    }
}

