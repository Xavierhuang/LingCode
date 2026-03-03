//
//  EditorState.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import SwiftUI
import Combine

class EditorState: ObservableObject {
    static let claudeCodeTabIdKey = "LingCode.ClaudeCodeDocumentId"

    @Published var documents: [Document] = []
    @Published var activeDocumentId: UUID?
    @Published var selectedText: String = ""
    @Published var cursorPosition: Int = 0
    
    var activeDocument: Document? {
        guard let activeDocumentId = activeDocumentId else { return nil }
        return documents.first { $0.id == activeDocumentId }
    }
    
    func addDocument(_ document: Document) {
        documents.append(document)
        activeDocumentId = document.id
    }
    
    func closeDocument(_ documentId: UUID) {
        documents.removeAll { $0.id == documentId }
        if activeDocumentId == documentId {
            activeDocumentId = documents.first?.id
        }
    }
    
    func setActiveDocument(_ documentId: UUID) {
        guard documents.contains(where: { $0.id == documentId }) else { return }
        // Defer so we don't publish during view update (e.g. when called from tab or file tree)
        let docId = documentId
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.documents.contains(where: { $0.id == docId }) else { return }
            self.activeDocumentId = docId
        }
    }
    
    func hasUnsavedChanges() -> Bool {
        documents.contains { $0.isModified && !$0.isClaudeCodeTab }
    }

    /// Ensures a Claude Code tab exists in the main editor and makes it active.
    func ensureClaudeCodeTab() {
        if let existing = documents.first(where: { $0.isClaudeCodeTab }) {
            activeDocumentId = existing.id
            return
        }
        let doc = Document(id: UUID(), filePath: nil, content: "", isModified: false)
        doc.isClaudeCodeTab = true
        doc.customDisplayName = "Claude Code"
        documents.append(doc)
        activeDocumentId = doc.id
    }
}

