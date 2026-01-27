//
//  RulesManagementView.swift
//  LingCode
//
//  UI for managing WORKSPACE.md and .cursorrules files (Cursor-style rules management)
//

import SwiftUI

struct RulesManagementView: View {
    let projectURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var rulesService = LingCodeRulesService.shared
    @State private var rulesContent: String = ""
    @State private var selectedFileType: RulesFileType = .workspace
    @State private var showSaveConfirmation = false
    @State private var hasUnsavedChanges = false
    
    enum RulesFileType: String, CaseIterable {
        case workspace = "WORKSPACE.md"
        case cursorrules = ".cursorrules"
        case lingcode = ".lingcode"
        
        var displayName: String {
            switch self {
            case .workspace: return "WORKSPACE.md (Recommended)"
            case .cursorrules: return ".cursorrules (Cursor Compatible)"
            case .lingcode: return ".lingcode (Legacy)"
            }
        }
        
        var description: String {
            switch self {
            case .workspace: return "Deterministic prompt architecture. Used by spec prompt system."
            case .cursorrules: return "Cursor-compatible format. Works with both Cursor and LingCode."
            case .lingcode: return "Legacy LingCode format. Still supported."
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // File type selector
                Picker("Rules File Type", selection: $selectedFileType) {
                    ForEach(RulesFileType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedFileType) { _, _ in
                    loadRules()
                }
                
                // Description
                Text(selectedFileType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                Divider()
                
                // Editor
                TextEditor(text: $rulesContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .onChange(of: rulesContent) { _, _ in
                        hasUnsavedChanges = true
                    }
                
                // Template button
                HStack {
                    Button(action: loadTemplate) {
                        Label("Load Template", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Text("\(rulesContent.components(separatedBy: .newlines).count) lines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Manage Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showSaveConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saveRules()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectURL == nil)
                }
            }
            .onAppear {
                loadRules()
            }
            .alert("Unsaved Changes", isPresented: $showSaveConfirmation) {
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func loadRules() {
        guard let projectURL = projectURL else {
            rulesContent = ""
            return
        }
        
        let fileName = selectedFileType.rawValue
        let fileURL = projectURL.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: fileURL.path),
           let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            rulesContent = content
        } else {
            // Load template if file doesn't exist
            rulesContent = getTemplate()
        }
        
        hasUnsavedChanges = false
    }
    
    private func loadTemplate() {
        rulesContent = getTemplate()
    }
    
    private func getTemplate() -> String {
        switch selectedFileType {
        case .workspace:
            return """
# WORKSPACE.md

Copy this file to `WORKSPACE.md` in your project root. LingCode loads it when using the deterministic prompt (project mode with a workspace).

## Language & Stack
- Swift 5.9
- SwiftUI
- Xcode 15+

## Conventions
- Prefer value types
- Avoid force unwraps
- Keep view models small

## Editing Rules
- Ask before refactors touching more than one file
- Keep diffs minimal
"""
        case .cursorrules:
            return """
# Cursor Rules

This file configures how Cursor and LingCode generate code for this project.

## Code Style
- Use 4-space indentation
- Follow Swift naming conventions
- Add documentation comments for public APIs

## Preferences
- Prefer Swift Concurrency (async/await) over callbacks
- Use SwiftUI for new views
- Follow MVVM architecture

## Don't
- Don't add emojis to code
- Don't create unnecessary abstractions
- Don't change unrelated code
"""
        case .lingcode:
            return LingCodeRulesService.defaultTemplate
        }
    }
    
    private func saveRules() {
        guard let projectURL = projectURL else { return }
        
        let fileName = selectedFileType.rawValue
        let fileURL = projectURL.appendingPathComponent(fileName)
        
        do {
            try rulesContent.write(to: fileURL, atomically: true, encoding: .utf8)
            hasUnsavedChanges = false
            
            // Reload rules service
            rulesService.loadRules(for: projectURL)
            
            // Show success
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                dismiss()
            }
        } catch {
            print("Failed to save rules: \(error)")
        }
    }
}
