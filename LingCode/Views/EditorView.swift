//
//  EditorView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var showInlineEdit: Bool = false
    @State private var inlineEditInstruction: String = ""
    @StateObject private var suggestionService = InlineSuggestionService.shared
    @State private var editorScrollView: NSScrollView?
    
    var body: some View {
        Group {
            if let document = viewModel.editorState.activeDocument {
                ZStack {
                    // Combined editor with line numbers in a single scroll view
                    GhostTextEditorWithLineNumbers(
                        text: Binding(
                            get: { document.content },
                            set: { newValue in
                                document.content = newValue
                            }
                        ),
                        isModified: Binding(
                            get: { document.isModified },
                            set: { newValue in
                                document.isModified = newValue
                            }
                        ),
                        fontSize: viewModel.fontSize,
                        fontName: viewModel.fontName,
                        language: document.language,
                        aiGeneratedRanges: document.aiGeneratedRanges,
                        onTextChange: { text in
                            viewModel.updateDocumentContent(text)
                        },
                        onSelectionChange: { text, position in
                            viewModel.updateSelection(text, position: position)
                        },
                        onScrollViewCreated: { scrollView in
                            editorScrollView = scrollView
                        }
                    )
                    
                    // Ghost text indicator
                    if suggestionService.isLoading {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Generating...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                                .cornerRadius(4)
                                .padding()
                            }
                        }
                    }
                    
                    // Inline Edit (Cmd+K) overlay
                    if showInlineEdit {
                        InlineEditOverlay(
                            isPresented: $showInlineEdit,
                            instruction: $inlineEditInstruction,
                            selectedText: viewModel.editorState.selectedText,
                            onSubmit: { instruction in
                                applyInlineEdit(instruction)
                            }
                        )
                    }
                }
                // Cmd+K shortcut for inline edit
                .keyboardShortcut("k", modifiers: .command)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerInlineEdit"))) { _ in
                    showInlineEdit = true
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No file open")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Open a file to start editing")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func applyInlineEdit(_ instruction: String) {
        guard !viewModel.editorState.selectedText.isEmpty else { return }
        
        viewModel.aiViewModel.inlineEdit(
            selectedCode: viewModel.editorState.selectedText,
            instruction: instruction
        ) { result in
            if let newCode = result {
                // Replace selected text with AI result
                if let document = viewModel.editorState.activeDocument {
                    let content = document.content
                    let selected = viewModel.editorState.selectedText
                    if let range = content.range(of: selected) {
                        document.content = content.replacingCharacters(in: range, with: newCode)
                        viewModel.updateDocumentContent(document.content)
                    }
                }
            }
        }
        
        showInlineEdit = false
        inlineEditInstruction = ""
    }
}

// MARK: - Inline Edit Overlay (Cmd+K)

struct InlineEditOverlay: View {
    @Binding var isPresented: Bool
    @Binding var instruction: String
    let selectedText: String
    let onSubmit: (String) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("Edit with AI")
                        .font(.headline)
                    Spacer()
                    Text("Cmd+K")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Selected code preview
                if !selectedText.isEmpty {
                    ScrollView {
                        Text(selectedText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 100)
                    .background(Color(NSColor.textBackgroundColor))
                }
                
                Divider()
                
                // Instruction input
                HStack {
                    TextField("What do you want to change?", text: $instruction)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .onSubmit {
                            if !instruction.isEmpty {
                                onSubmit(instruction)
                            }
                        }
                    
                    Button(action: {
                        if !instruction.isEmpty {
                            onSubmit(instruction)
                        }
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(instruction.isEmpty ? .gray : .purple)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(instruction.isEmpty)
                }
                .padding()
                
                // Quick actions
                HStack(spacing: 8) {
                    QuickEditButton(title: "Add comments", icon: "text.bubble") {
                        instruction = "Add comments to explain this code"
                        onSubmit(instruction)
                    }
                    QuickEditButton(title: "Fix bugs", icon: "ladybug") {
                        instruction = "Fix any bugs in this code"
                        onSubmit(instruction)
                    }
                    QuickEditButton(title: "Optimize", icon: "bolt") {
                        instruction = "Optimize this code for performance"
                        onSubmit(instruction)
                    }
                    QuickEditButton(title: "Simplify", icon: "arrow.triangle.branch") {
                        instruction = "Simplify this code"
                        onSubmit(instruction)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 20)
            .frame(maxWidth: 600)
            .padding()
        }
        .background(Color.black.opacity(0.3))
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            isPresented = false
        }
    }
}

struct QuickEditButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

