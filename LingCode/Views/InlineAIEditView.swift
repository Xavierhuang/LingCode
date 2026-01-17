//
//  InlineAIEditView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct InlineAIEditView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: EditorViewModel
    @State private var prompt: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("AI Edit")
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text("Describe how you want to edit the selected code:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("e.g., add error handling, refactor to use async/await...", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...10)
                .focused($isFocused)
                .onSubmit {
                    performEdit()
                }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Apply") {
                    performEdit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isEmpty || isLoading)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            isFocused = true
        }
    }
    
    private func performEdit() {
        guard let document = viewModel.editorState.activeDocument else { return }
        guard !prompt.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        let selectedText = viewModel.editorState.selectedText.isEmpty 
            ? document.content 
            : viewModel.editorState.selectedText
        
        let fullPrompt = "Edit this code according to the following instruction: \(prompt)\n\nCode:\n\(selectedText)\n\nReturn only the edited code, nothing else."
        
        // Include related files context if enabled
        var context = document.content
        if viewModel.includeRelatedFilesInContext,
           let relatedContext = viewModel.getContextForAI() {
            context += "\n\n" + relatedContext
        }
        
        Task { @MainActor in
            do {
                let aiService: AIProviderProtocol = ServiceContainer.shared.ai
                let response = try await aiService.sendMessage(fullPrompt, context: context, images: [], tools: nil)
                
                isLoading = false
                
                if viewModel.editorState.selectedText.isEmpty {
                    document.content = response
                } else {
                    // Replace selected text
                    let content = document.content
                    // TODO: Replace selection with response
                    document.content = content.replacingOccurrences(
                        of: selectedText,
                        with: response
                    )
                }
                
                document.isModified = true
                viewModel.updateDocumentContent(document.content)
                isPresented = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}


