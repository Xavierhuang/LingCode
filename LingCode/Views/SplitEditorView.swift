//
//  SplitEditorView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

enum SplitDirection {
    case none
    case horizontal
    case vertical
}

struct SplitEditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var splitDirection: SplitDirection
    @State private var splitRatio: CGFloat = 0.5
    
    var body: some View {
        GeometryReader { geometry in
            switch splitDirection {
            case .none:
                EditorView(viewModel: viewModel)
                
            case .horizontal:
                HSplitView {
                    EditorView(viewModel: viewModel)
                        .frame(minWidth: 200)
                    
                    Divider()
                    
                    SecondaryEditorView(viewModel: viewModel)
                        .frame(minWidth: 200)
                }
                
            case .vertical:
                VSplitView {
                    EditorView(viewModel: viewModel)
                        .frame(minHeight: 100)
                    
                    Divider()
                    
                    SecondaryEditorView(viewModel: viewModel)
                        .frame(minHeight: 100)
                }
            }
        }
    }
}

struct SecondaryEditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var secondaryDocumentId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Secondary tab bar
            HStack {
                ForEach(viewModel.editorState.documents) { document in
                    Button(action: {
                        secondaryDocumentId = document.id
                    }) {
                        Text(document.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(secondaryDocumentId == document.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Secondary editor content
            if let docId = secondaryDocumentId,
               let document = viewModel.editorState.documents.first(where: { $0.id == docId }) {
                HStack(spacing: 0) {
                    let lineCount = document.content.components(separatedBy: .newlines).count
                    LineNumbersView(
                        lineCount: lineCount,
                        fontSize: viewModel.fontSize,
                        fontName: viewModel.fontName
                    )
                    .frame(width: 55)
                    
                    // Separator line
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1)
                    
                    CodeEditor(
                        text: Binding(
                            get: { document.content },
                            set: { document.content = $0 }
                        ),
                        isModified: Binding(
                            get: { document.isModified },
                            set: { document.isModified = $0 }
                        ),
                        fontSize: viewModel.fontSize,
                        fontName: viewModel.fontName,
                        language: document.language,
                        onTextChange: { _ in },
                        onSelectionChange: { _, _ in },
                        onAutocompleteRequest: { _ in }
                    )
                }
            } else {
                VStack {
                    Text("Select a file to view")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

