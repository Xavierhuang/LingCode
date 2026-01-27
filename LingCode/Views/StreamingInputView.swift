//
//  StreamingInputView.swift
//  LingCode
//
//  Input view component for streaming interface
//

import SwiftUI
import AppKit
@preconcurrency import UniformTypeIdentifiers

struct StreamingInputView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @StateObject private var imageContextService = ImageContextService.shared
    
    @Binding var activeMentions: [Mention]
    @State private var showMentionPopup = false
    @State private var showFilePicker = false
    
    let onSendMessage: () -> Void
    let onImageDrop: ([NSItemProvider]) async -> Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Context files indicator
            if let contextFiles = getContextFiles(), !contextFiles.isEmpty {
                ContextFilesIndicator(files: contextFiles)
            }
            
            // Context file indicator (if active)
            if let file = editorViewModel.editorState.activeDocument?.filePath?.lastPathComponent {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(file)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(0.5)
                )
            }
            
            // Attached images preview
            if !imageContextService.attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageContextService.attachedImages) { image in
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: image.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                Button(action: {
                                    imageContextService.removeImage(image.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(0.4)
                )
            }
            
            // Context badges
            if !activeMentions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeMentions) { mention in
                            MentionBadgeView(mention: mention) {
                                activeMentions.removeAll { $0.id == mention.id }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            // Input field (Cursor-style)
            HStack(spacing: 8) {
                // @ mention button
                Button(action: {
                    showMentionPopup = true
                }) {
                    Image(systemName: "at")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add context (@file, @codebase, etc.)")
                .popover(isPresented: $showMentionPopup, arrowEdge: .top) {
                    MentionPopupView(
                        isVisible: $showMentionPopup,
                        onSelect: { type in
                            if type == .file {
                                showFilePicker = true
                            } else {
                                addMention(type)
                            }
                        },
                        editorViewModel: editorViewModel
                    )
                }
                .sheet(isPresented: $showFilePicker) {
                    FileMentionPickerView(
                        editorViewModel: editorViewModel,
                        onSelect: { filePath in
                            let mention = Mention(
                                type: .file,
                                value: filePath,
                                displayName: "@file:\(filePath)"
                            )
                            if !activeMentions.contains(where: { $0.type == .file && $0.value == filePath }) {
                                activeMentions.append(mention)
                            }
                        },
                        isVisible: $showFilePicker
                    )
                }
                
                // Image attachment button
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.image]
                    
                    if panel.runModal() == .OK {
                        for url in panel.urls {
                            _ = imageContextService.addFromFile(url)
                        }
                    }
                }) {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Attach image")
                
                // Paste image from clipboard button
                Button(action: {
                    _ = imageContextService.addFromClipboard()
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Paste image from clipboard")
                
                // Text input with better styling
                TextField("Plan, @ for context, / for commands", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .onSubmit {
                        if !viewModel.currentInput.isEmpty && !viewModel.isLoading {
                            onSendMessage()
                        }
                    }
                    .onChange(of: viewModel.currentInput) { _, newValue in
                        // Check for @ trigger
                        if newValue.hasSuffix("@") {
                            showMentionPopup = true
                        }
                        // Note: Speculative context is now handled by AIViewModel's Combine pipeline
                    }
                
                // ⚡️ Speculative context indicator
                if viewModel.isSpeculating {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.yellow)
                        .opacity(0.8)
                        .help("Preparing context...")
                }
                
                // Send/Stop button
                Button(action: {
                    if viewModel.isLoading {
                        viewModel.cancelGeneration()
                    } else {
                        onSendMessage()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                viewModel.isLoading 
                                    ? Color.red 
                                    : (viewModel.currentInput.isEmpty 
                                        ? Color.gray.opacity(0.3) 
                                        : Color(red: 0.5, green: 0.3, blue: 0.9))
                            )
                            .frame(width: 24, height: 24)
                            .shadow(
                                color: (!viewModel.isLoading && !viewModel.currentInput.isEmpty) 
                                    ? Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.4) 
                                    : Color.clear,
                                radius: 4
                            )
                        
                        Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(viewModel.isLoading || !viewModel.currentInput.isEmpty ? .white : .secondary)
                    }
                    .scaleEffect(viewModel.isLoading ? 1.0 : (viewModel.currentInput.isEmpty ? 0.95 : 1.0))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.isLoading && viewModel.currentInput.isEmpty)
                .help(viewModel.isLoading ? "Stop generation" : "Send message")
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: viewModel.isLoading)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: viewModel.currentInput.isEmpty)
                .onTapGesture {
                    if !viewModel.isLoading && !viewModel.currentInput.isEmpty {
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                            // Button press feedback
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                DesignSystem.Colors.secondaryBackground
                    .opacity(0.8)
            )
            .onDrop(of: [.image, .fileURL], isTargeted: .constant(false)) { providers in
                Task {
                    _ = await onImageDrop(providers)
                }
                return true
            }
        }
        .background(
            Color(NSColor.windowBackgroundColor)
        )
    }
    
    private func addMention(_ type: MentionType) {
        var value = ""
        var displayName = type.rawValue
        
        switch type {
        case .file:
            if let doc = editorViewModel.editorState.activeDocument,
               let filePath = doc.filePath {
                value = filePath.lastPathComponent
                displayName = "@file:\(value)"
            }
        case .selection:
            if !editorViewModel.editorState.selectedText.isEmpty {
                displayName = "@selection"
            }
        case .folder:
            if let url = editorViewModel.rootFolderURL {
                value = url.lastPathComponent
                displayName = "@folder:\(value)"
            }
        case .codebase:
            displayName = "@codebase"
        case .terminal:
            displayName = "@terminal"
        case .web:
            displayName = "@web"
        }
        
        let mention = Mention(type: type, value: value, displayName: displayName)
        
        // Don't add duplicates
        if !activeMentions.contains(where: { $0.type == type && $0.value == value }) {
            activeMentions.append(mention)
        }
    }
    
    private func getContextFiles() -> [String]? {
        var files: [String] = []
        
        // Add active file
        if let activeFile = editorViewModel.editorState.activeDocument?.filePath {
            files.append(activeFile.lastPathComponent)
        }
        
        // Add related files if enabled
        if editorViewModel.includeRelatedFilesInContext,
           let document = editorViewModel.editorState.activeDocument,
           let filePath = document.filePath,
           let projectURL = editorViewModel.rootFolderURL {
            let relatedFiles = FileDependencyService.shared.findRelatedFiles(
                for: filePath,
                in: projectURL
            )
            files.append(contentsOf: relatedFiles.map { $0.lastPathComponent })
        }
        
        return files.isEmpty ? nil : files
    }
}

