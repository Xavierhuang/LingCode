//
//  InlineEditView.swift
//  LingCode
//
//  Cmd+K style inline AI editing (like Cursor)
//

import SwiftUI

/// Cursor-style Cmd+K inline edit popup
struct InlineEditView: View {
    @Binding var isPresented: Bool
    let selectedCode: String
    let onSubmit: (String) -> Void
    
    @State private var prompt: String = ""
    @State private var isLoading: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.accentColor)
                
                Text("Edit with AI")
                    .font(.headline)
                
                Spacer()
                
                Text("Cmd+K")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Selected code preview
            if !selectedCode.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(selectedCode.prefix(500) + (selectedCode.count > 500 ? "..." : ""))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
                .padding()
            }
            
            Divider()
            
            // Input
            VStack(alignment: .leading, spacing: 8) {
                Text("What would you like to do?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("e.g., Add error handling, Refactor this function...", text: $prompt)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            submitEdit()
                        }
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(action: submitEdit) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(prompt.isEmpty ? .secondary : .accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(prompt.isEmpty)
                    }
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
            .padding()
            
            // Quick actions
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickActionButton(title: "Add comments", icon: "text.bubble") {
                            prompt = "Add clear comments explaining this code"
                            submitEdit()
                        }
                        
                        QuickActionButton(title: "Add error handling", icon: "exclamationmark.triangle") {
                            prompt = "Add proper error handling"
                            submitEdit()
                        }
                        
                        QuickActionButton(title: "Optimize", icon: "bolt") {
                            prompt = "Optimize this code for performance"
                            submitEdit()
                        }
                        
                        QuickActionButton(title: "Add types", icon: "t.square") {
                            prompt = "Add type annotations"
                            submitEdit()
                        }
                        
                        QuickActionButton(title: "Simplify", icon: "arrow.triangle.branch") {
                            prompt = "Simplify and clean up this code"
                            submitEdit()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20)
        .onAppear {
            isFocused = true
        }
    }
    
    private func submitEdit() {
        guard !prompt.isEmpty else { return }
        isLoading = true
        onSubmit(prompt)
        
        // Reset after a delay (actual implementation would wait for response)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
            isPresented = false
        }
    }
}

struct QuickActionButton: View {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Floating inline edit trigger (appears on selection)
struct InlineEditTrigger: View {
    let selectedText: String
    let onTrigger: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTrigger) {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                Text("Edit")
                Text("Cmd+K")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.3))
                    .cornerRadius(3)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovering ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isHovering ? .white : .primary)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.1), radius: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// Result view after inline edit
struct InlineEditResultView: View {
    let originalCode: String
    let newCode: String
    let onAccept: () -> Void
    let onReject: () -> Void
    
    @State private var showDiff = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("AI Suggestion")
                    .font(.headline)
                
                Spacer()
                
                Picker("", selection: $showDiff) {
                    Text("Diff").tag(true)
                    Text("Result").tag(false)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 120)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            if showDiff {
                // Diff view
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let oldLines = originalCode.components(separatedBy: .newlines)
                        let newLines = newCode.components(separatedBy: .newlines)
                        
                        // Simple diff: show removed then added
                        ForEach(Array(oldLines.enumerated()), id: \.offset) { index, line in
                            DiffLineView(lineNumber: index + 1, content: line, type: .removed)
                        }
                        
                        ForEach(Array(newLines.enumerated()), id: \.offset) { index, line in
                            DiffLineView(lineNumber: index + 1, content: line, type: .added)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
                .background(Color(NSColor.textBackgroundColor))
            } else {
                // Result only
                ScrollView {
                    Text(newCode)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 300)
                .background(Color(NSColor.textBackgroundColor))
            }
            
            Divider()
            
            // Actions
            HStack {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(newCode, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onReject) {
                    Label("Reject", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button(action: onAccept) {
                    Label("Accept", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20)
    }
}

struct DiffLineView: View {
    let lineNumber: Int
    let content: String
    let type: DiffLineType
    
    enum DiffLineType {
        case added
        case removed
        case unchanged
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text("\(lineNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 8)
            
            // Indicator
            Text(indicator)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(indicatorColor)
                .frame(width: 16)
            
            // Content
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 1)
        .background(backgroundColor)
    }
    
    private var indicator: String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }
    
    private var indicatorColor: Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .secondary
        }
    }
    
    private var backgroundColor: Color {
        switch type {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .unchanged: return Color.clear
        }
    }
}

