//
//  DebugModeView.swift
//  LingCode
//
//  Debug Mode - Debugging assistance
//

import SwiftUI

struct DebugModeView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "ant")
                    .foregroundColor(.orange)
                Text("Debug Mode")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Debug info
                    if let activeDoc = editorViewModel.editorState.activeDocument {
                        DebugInfoCard(document: activeDoc)
                    }
                    
                    // Debug suggestions
                    DebugSuggestionsCard()
                    
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "ant")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Debug Mode")
                            .font(.headline)
                        
                        Text("Ask the AI to help debug your code, analyze errors, or find issues.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .padding()
            }
            
            Divider()
            
            // Input area with debug-specific prompt enhancement
            StreamingInputView(
                viewModel: viewModel,
                editorViewModel: editorViewModel,
                activeMentions: .constant([]),
                onSendMessage: { },
                onImageDrop: { _ in false }
            )
        }
        .onAppear {
            // Enhance prompt for debugging when in debug mode
            if viewModel.currentInput.isEmpty {
                viewModel.currentInput = "Debug this code: "
            }
        }
    }
}

struct DebugInfoCard: View {
    let document: Document
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.orange)
                Text("Current File")
                    .font(.headline)
            }
            
            if let filePath = document.filePath {
                Text(filePath.lastPathComponent)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Text("\(document.content.components(separatedBy: .newlines).count) lines")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
}

struct DebugSuggestionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.orange)
                Text("Debug Suggestions")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                suggestionRow("Find bugs in this code", icon: "ant")
                suggestionRow("Explain this error", icon: "exclamationmark.triangle")
                suggestionRow("Optimize this code", icon: "bolt")
                suggestionRow("Check for security issues", icon: "lock.shield")
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func suggestionRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text(text)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
