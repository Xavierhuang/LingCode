//
//  IntegrationExample.swift
//  EditorCore
//
//  Example of integrating EditorCore with SwiftUI Editor
//

import Foundation
import SwiftUI
import EditorCore

// MARK: - SwiftUI View Model (Editor-facing)

/// View model that integrates EditorCore with SwiftUI
@MainActor
class EditorViewModel: ObservableObject {
    // EditorCore integration
    private let coordinator: EditSessionCoordinator
    
    // Current edit session
    @Published private(set) var editSession: EditSessionHandle?
    
    // UI state (from EditSessionModel)
    @Published var editStatus: EditSessionStatus = .idle
    @Published var streamingText: String = ""
    @Published var proposedEdits: [EditProposal] = []
    @Published var errorMessage: String?
    
    init(coordinator: EditSessionCoordinator = DefaultEditSessionCoordinator()) {
        self.coordinator = coordinator
    }
    
    // MARK: - Editor Actions
    
    /// Start an AI edit session
    func startAIEdit(instruction: String, currentFiles: [FileState]) {
        // Create session via coordinator
        let session = coordinator.startEditSession(
            instruction: instruction,
            files: currentFiles
        )
        
        editSession = session
        
        // Observe session model
        observeSession(session)
    }
    
    /// Feed streaming text from AI service
    func receiveStreamingText(_ text: String) {
        editSession?.appendStreamingText(text)
    }
    
    /// Complete streaming
    func completeStreaming() {
        editSession?.completeStreaming()
    }
    
    /// Accept all edits
    func acceptAllEdits() {
        guard let session = editSession else { return }
        
        let editsToApply = session.acceptAll()
        applyEditsToEditor(editsToApply)
    }
    
    /// Accept specific edits
    func acceptEdits(ids: Set<UUID>) {
        guard let session = editSession else { return }
        
        let editsToApply = session.accept(editIds: ids)
        applyEditsToEditor(editsToApply)
    }
    
    /// Reject all edits
    func rejectAllEdits() {
        editSession?.rejectAll()
    }
    
    /// Undo last edit
    func undoLastEdit() {
        guard let session = editSession,
              let editsToApply = session.undo() else {
            return
        }
        
        applyEditsToEditor(editsToApply)
    }
    
    // MARK: - Private Helpers
    
    private func observeSession(_ session: EditSessionHandle) {
        // Observe model changes
        session.model.$status
            .assign(to: &$editStatus)
        
        session.model.$streamingText
            .assign(to: &$streamingText)
        
        session.model.$proposedEdits
            .assign(to: &$proposedEdits)
        
        session.model.$errorMessage
            .assign(to: &$errorMessage)
    }
    
    /// Apply edits to actual editor (this is editor-specific)
    private func applyEditsToEditor(_ edits: [EditToApply]) {
        for edit in edits {
            // Editor applies this to actual file
            // This is where editor-specific logic goes
            print("Applying edit to \(edit.filePath)")
            print("  Original: \(edit.originalContent.prefix(50))...")
            print("  New: \(edit.newContent.prefix(50))...")
            
            // In real app:
            // editor.openFile(edit.filePath)
            // editor.replaceContent(edit.newContent)
        }
    }
}

// MARK: - SwiftUI View Example

struct EditSessionView: View {
    @StateObject private var viewModel = EditorViewModel()
    @State private var instruction: String = ""
    @State private var currentFiles: [FileState] = []
    
    var body: some View {
        VStack {
            // Status
            statusView
            
            // Streaming text
            if viewModel.editStatus == .streaming {
                streamingView
            }
            
            // Proposed edits
            if viewModel.editStatus == .ready {
                proposedEditsView
            }
            
            // Input
            inputView
        }
    }
    
    private var statusView: some View {
        HStack {
            Text("Status: \(viewModel.editStatus.description)")
            if viewModel.editSession?.canUndo == true {
                Button("Undo") {
                    viewModel.undoLastEdit()
                }
            }
        }
    }
    
    private var streamingView: some View {
        ScrollView {
            Text(viewModel.streamingText)
                .font(.monospaced(.body)())
        }
    }
    
    private var proposedEditsView: some View {
        List(viewModel.proposedEdits) { proposal in
            EditProposalRow(proposal: proposal) { accepted in
                if accepted {
                    viewModel.acceptEdits(ids: [proposal.id])
                } else {
                    viewModel.rejectAllEdits()
                }
            }
        }
    }
    
    private var inputView: some View {
        HStack {
            TextField("Enter instruction", text: $instruction)
            Button("Start Edit") {
                viewModel.startAIEdit(
                    instruction: instruction,
                    currentFiles: currentFiles
                )
            }
        }
    }
}

struct EditProposalRow: View {
    let proposal: EditProposal
    let onAction: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(proposal.fileName)
                .font(.headline)
            
            Text("+\(proposal.statistics.addedLines) -\(proposal.statistics.removedLines)")
                .font(.caption)
            
            HStack {
                Button("Accept") {
                    onAction(true)
                }
                Button("Reject") {
                    onAction(false)
                }
            }
        }
    }
}

extension EditSessionStatus {
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .streaming: return "Streaming..."
        case .ready: return "Ready"
        case .applied: return "Applied"
        case .rejected: return "Rejected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
