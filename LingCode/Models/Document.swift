//
//  Document.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

class Document: ObservableObject, Identifiable {
    let id: UUID
    var filePath: URL?
    @Published var content: String
    @Published var isModified: Bool
    @Published var language: String?

    // AI-generated change tracking
    @Published var aiGeneratedRanges: [NSRange] = []
    @Published var originalContent: String?

    init(id: UUID = UUID(), filePath: URL? = nil, content: String = "", isModified: Bool = false) {
        self.id = id
        self.filePath = filePath
        self.content = content
        self.isModified = isModified
        self.language = filePath?.pathExtension.lowercased()
    }
    
    var fileName: String {
        filePath?.lastPathComponent ?? "Untitled"
    }
    
    var displayName: String {
        if isModified {
            return fileName + " •"
        }
        return fileName
    }
    
    func detectLanguage() {
        guard let filePath = filePath else { return }
        let ext = filePath.pathExtension.lowercased()

        let languageMap: [String: String] = [
            "swift": "swift",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "jsx": "javascript",
            "tsx": "typescript",
            "html": "html",
            "css": "css",
            "json": "json",
            "md": "markdown",
            "sh": "bash",
            "go": "go",
            "rs": "rust",
            "java": "java",
            "cpp": "cpp",
            "c": "c",
            "h": "c",
            "hpp": "cpp"
        ]

        self.language = languageMap[ext]
    }

    /// Mark content as AI-generated with change detection
    func markAsAIGenerated(originalContent: String?) {
        self.originalContent = originalContent
        self.aiGeneratedRanges = ChangeHighlighter.detectChangedRanges(
            original: originalContent ?? "",
            modified: content
        )
        print("🎨 Document.markAsAIGenerated: Found \(aiGeneratedRanges.count) changed ranges")
        for (index, range) in aiGeneratedRanges.prefix(3).enumerated() {
            print("   Range \(index): location=\(range.location), length=\(range.length)")
        }
    }

    /// Clear AI-generated change highlighting
    func clearAIHighlighting() {
        self.aiGeneratedRanges = []
        self.originalContent = nil
    }
}

