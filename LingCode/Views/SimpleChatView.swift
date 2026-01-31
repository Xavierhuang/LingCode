//
//  SimpleChatView.swift
//  LingCode
//
//  Simple chat interface for Ask mode - just conversation, no code generation
//

import SwiftUI
@preconcurrency import UniformTypeIdentifiers

struct SimpleChatView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var activeMentions: [Mention] = []
    @StateObject private var imageContextService = ImageContextService.shared
    @State private var shouldAutoScroll: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.conversation.messages) { message in
                            MessageBubble(
                                message: message,
                                isStreaming: viewModel.isLoading && message.id == viewModel.conversation.messages.last?.id,
                                workingDirectory: editorViewModel.rootFolderURL,
                                onCopyCode: { code in
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                }
                            )
                            .id(message.id)
                        }
                        
                        if viewModel.isLoading && viewModel.conversation.messages.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.conversation.messages.count) { oldValue, newValue in
                    if newValue > oldValue, let lastMessage = viewModel.conversation.messages.last {
                        // Always scroll to bottom when new messages arrive
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.conversation.messages.last?.content) { _, _ in
                    // Scroll to bottom when message content updates (during streaming)
                    if viewModel.isLoading, let lastMessage = viewModel.conversation.messages.last {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    // Always scroll to bottom on appear
                    if let lastMessage = viewModel.conversation.messages.last {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Simple input area
            VStack(spacing: 0) {
                // Context badges
                if !activeMentions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(activeMentions) { mention in
                                MentionBadgeView(mention: mention) {
                                    activeMentions.removeAll { $0.id == mention.id }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
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
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .padding(.horizontal)
                }
                
                // Input field
                HStack(alignment: .bottom) {
                    Button(action: { }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add context")
                    
                    TextField("Ask anything...", text: $viewModel.currentInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    Button(action: {
                        if viewModel.isLoading {
                            viewModel.cancelGeneration()
                        } else {
                            sendMessage()
                        }
                    }) {
                        Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.isLoading ? .red : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.currentInput.isEmpty && activeMentions.isEmpty && imageContextService.attachedImages.isEmpty)
                    .help(viewModel.isLoading ? "Stop" : "Send")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: .constant(false)) { providers in
                    Task {
                        _ = await handleImageDrop(providers: providers)
                    }
                    return true
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !viewModel.currentInput.isEmpty || !activeMentions.isEmpty || !imageContextService.attachedImages.isEmpty else { return }
        
        // Build context asynchronously with @docs and @web support
        Task { @MainActor in
            var context = await editorViewModel.getContextForAI() ?? ""
            let mentionContext = await MentionParser.shared.buildContextFromMentionsAsync(
                activeMentions,
                projectURL: editorViewModel.rootFolderURL,
                selectedText: editorViewModel.editorState.selectedText,
                terminalOutput: nil
            )
            context += mentionContext
            
            // Send message with images
            viewModel.sendMessage(
                context: context.isEmpty ? nil : context,
                projectURL: editorViewModel.rootFolderURL,
                images: imageContextService.attachedImages
            )
            
            // Clear after sending
            activeMentions.removeAll()
            imageContextService.clearImages()
        }
    }
    
    private func handleImageDrop(providers: [NSItemProvider]) async -> Bool {
        var handled = false
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                        Task { @MainActor in
                            if let error = error {
                                print("Error loading file URL: \(error.localizedDescription)")
                                continuation.resume()
                                return
                            }
                            
                            if let data = item as? Data,
                               let url = URL(dataRepresentation: data, relativeTo: nil) {
                                _ = imageContextService.addFromFile(url)
                            } else if let url = item as? URL {
                                _ = imageContextService.addFromFile(url)
                            }
                            continuation.resume()
                        }
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                        Task { @MainActor in
                            if let error = error {
                                print("Error loading image: \(error.localizedDescription)")
                                continuation.resume()
                                return
                            }
                            
                            if let url = item as? URL {
                                _ = imageContextService.addFromFile(url)
                            } else if let data = item as? Data,
                                      let image = NSImage(data: data) {
                                _ = imageContextService.addImage(image, source: .dragDrop)
                            } else if let image = item as? NSImage {
                                _ = imageContextService.addImage(image, source: .dragDrop)
                            }
                            continuation.resume()
                        }
                    }
                }
                handled = true
            }
        }
        
        return handled
    }
}
