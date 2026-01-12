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
        if documents.contains(where: { $0.id == documentId }) {
            activeDocumentId = documentId
            objectWillChange.send()
        }
    }
    
    func hasUnsavedChanges() -> Bool {
        documents.contains { $0.isModified }
    }
}

