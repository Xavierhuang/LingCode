//
//  RefactoringView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct RefactoringView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: EditorViewModel
    @State private var suggestions: [RefactoringSuggestion] = []
    @State private var selectedSuggestion: RefactoringSuggestion?
    @State private var preview: RefactoringPreview?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedType: RefactoringType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.blue)
                Text("Refactoring Suggestions")
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Analyzing code...")
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding()
            } else if suggestions.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Text("No refactoring suggestions available")
                        .foregroundColor(.secondary)
                    
                    if viewModel.editorState.activeDocument != nil {
                        Button("Analyze Code") {
                            analyzeCode()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                HSplitView {
                    // Suggestions list
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Suggestions")
                                .font(.headline)
                            Spacer()
                            Menu {
                                ForEach(RefactoringType.allCases, id: \.self) { type in
                                    Button(action: {
                                        selectedType = type
                                        analyzeCode()
                                    }) {
                                        Text(type.rawValue)
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease")
                            }
                        }
                        .padding()
                        
                        Divider()
                        
                        List {
                            ForEach(suggestions) { suggestion in
                                Button(action: {
                                    selectedSuggestion = suggestion
                                    loadPreview(for: suggestion)
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(suggestion.type.rawValue)
                                                .font(.headline)
                                            Spacer()
                                            HStack(spacing: 4) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.yellow)
                                                Text(String(format: "%.0f%%", suggestion.confidence * 100))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Text(suggestion.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .background(selectedSuggestion?.id == suggestion.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            }
                        }
                        .listStyle(.sidebar)
                    }
                    .frame(width: 300)
                    
                    Divider()
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 0) {
                        if let preview = preview {
                            HStack {
                                Text("Preview")
                                    .font(.headline)
                                Spacer()
                                Button("Apply") {
                                    applyRefactoring()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isLoading)
                            }
                            .padding()
                            
                            Divider()
                            
                            HSplitView {
                                // Original
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Original")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding()
                                    
                                    ScrollView {
                                        Text(preview.originalCode)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding()
                                    }
                                }
                                .frame(minWidth: 200)
                                
                                Divider()
                                
                                // Refactored
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Refactored")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding()
                                    
                                    ScrollView {
                                        Text(preview.refactoredCode)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding()
                                    }
                                }
                                .frame(minWidth: 200)
                            }
                        } else if let suggestion = selectedSuggestion {
                            VStack(spacing: 12) {
                                Text("Select a suggestion to preview")
                                    .foregroundColor(.secondary)
                                
                                Button("Preview Changes") {
                                    loadPreview(for: suggestion)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            VStack {
                                Text("Select a suggestion to see preview")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        }
                    }
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .frame(width: 900, height: 700)
        .onAppear {
            if suggestions.isEmpty {
                analyzeCode()
            }
        }
    }
    
    private func analyzeCode() {
        guard let document = viewModel.editorState.activeDocument else { return }
        
        isLoading = true
        errorMessage = nil
        suggestions = []
        
        let code = viewModel.editorState.selectedText.isEmpty 
            ? document.content 
            : viewModel.editorState.selectedText
        
        Task {
            do {
                let newSuggestions = try await RefactoringService.shared.suggestRefactoring(
                    for: code,
                    type: selectedType,
                    language: document.language
                )
                
                await MainActor.run {
                    self.suggestions = newSuggestions
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadPreview(for suggestion: RefactoringSuggestion) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let newPreview = try await RefactoringService.shared.previewRefactoring(suggestion: suggestion)
                
                await MainActor.run {
                    self.preview = newPreview
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func applyRefactoring() {
        guard let preview = preview else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await RefactoringService.shared.applyRefactoring(
                    preview: preview,
                    in: preview.affectedFiles
                )
                
                await MainActor.run {
                    // Reload the document
                    if let filePath = viewModel.editorState.activeDocument?.filePath {
                        viewModel.openFile(at: filePath)
                    }
                    self.isLoading = false
                    self.isPresented = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

