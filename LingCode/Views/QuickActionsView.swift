//
//  QuickActionsView.swift
//  LingCode
//
//  Quick actions panel (Cursor Tab-like feature)
//  Provides fast access to common AI operations
//

import SwiftUI

struct QuickActionsView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAction: QuickAction?
    @State private var isExecuting = false
    
    enum QuickAction: String, CaseIterable, Identifiable {
        case explain = "Explain Code"
        case refactor = "Refactor"
        case addTests = "Add Tests"
        case fixBugs = "Fix Bugs"
        case optimize = "Optimize"
        case document = "Document"
        case review = "Code Review"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .explain: return "questionmark.circle"
            case .refactor: return "arrow.triangle.2.circlepath"
            case .addTests: return "checkmark.circle"
            case .fixBugs: return "wrench.and.screwdriver"
            case .optimize: return "bolt"
            case .document: return "doc.text"
            case .review: return "eye"
            }
        }
        
        var color: Color {
            switch self {
            case .explain: return .blue
            case .refactor: return .purple
            case .addTests: return .green
            case .fixBugs: return .orange
            case .optimize: return .yellow
            case .document: return .cyan
            case .review: return .indigo
            }
        }
        
        func generatePrompt(selectedText: String?, filePath: String?) -> String {
            let context = selectedText != nil ? "selected code" : (filePath != nil ? "this file" : "the code")
            
            switch self {
            case .explain:
                return "Explain \(context) in detail. What does it do and how does it work?"
            case .refactor:
                return "Refactor \(context) to improve code quality, readability, and maintainability."
            case .addTests:
                return "Add comprehensive unit tests for \(context). Include edge cases and error handling."
            case .fixBugs:
                return "Find and fix any bugs in \(context). Explain what was wrong and how you fixed it."
            case .optimize:
                return "Optimize \(context) for better performance. Focus on speed and memory usage."
            case .document:
                return "Add comprehensive documentation to \(context). Include function descriptions, parameters, and return values."
            case .review:
                return "Review \(context) for code quality, best practices, potential issues, and improvements."
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Quick Actions")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select an action to perform on your code")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                ForEach(QuickAction.allCases) { action in
                    Button(action: {
                        selectedAction = action
                        executeAction(action)
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: action.icon)
                                .font(.system(size: 32))
                                .foregroundColor(action.color)
                            
                            Text(action.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .frame(width: 140, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedAction == action ? action.color : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func executeAction(_ action: QuickAction) {
        guard !isExecuting else { return }
        isExecuting = true
        
        let selectedText = editorViewModel.editorState.selectedText.isEmpty ? nil : editorViewModel.editorState.selectedText
        let filePath = editorViewModel.editorState.activeDocument?.filePath?.path
        
        let prompt = action.generatePrompt(selectedText: selectedText, filePath: filePath)
        
        // Set the prompt and send
        viewModel.currentInput = prompt
        
        // Send message to AI
        viewModel.sendMessage(
            context: selectedText,
            projectURL: editorViewModel.rootFolderURL,
            images: []
        )
        
        dismiss()
    }
}
