//
//  InlineTaskQueueView.swift
//  LingCode
//
//  Inline task queue display (Cursor-style)
//

import SwiftUI

struct InlineTaskQueueView: View {
    @ObservedObject var queueService = TaskQueueService.shared
    @State private var isExpanded: Bool = true
    
    var body: some View {
        if !queueService.queue.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header with smooth animation
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            
                            Text("\(queueService.queue.count) Queued")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        // Status indicator
                        if queueService.isProcessing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                                Text("Processing...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
                
                // Queue items with smooth transitions
                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(queueService.queue) { item in
                            InlineTaskQueueItemRow(item: item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    )
                    .clipShape(
                        .rect(
                            bottomLeadingRadius: 6,
                            bottomTrailingRadius: 6
                        )
                    )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct InlineTaskQueueItemRow: View {
    let item: TaskQueueItem
    @State private var isHovered: Bool = false
    @State private var showEditDialog: Bool = false
    @State private var editedPrompt: String = ""
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator with smooth animation
            statusIcon
                .frame(width: 16, height: 16)
                .transition(.scale.combined(with: .opacity))
            
            // Prompt text with better typography
            VStack(alignment: .leading, spacing: 2) {
                Text(item.prompt)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(item.status == .cancelled ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Timestamp
                Text(item.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Actions (show on hover with smooth fade)
            if isHovered && (item.status == .pending || item.status == .executing) {
                HStack(spacing: 6) {
                    // Edit button
                    Button(action: {
                        editedPrompt = item.prompt
                        showEditDialog = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Edit task")
                    
                    // Move up button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            TaskQueueService.shared.moveUp(item)
                        }
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Move up")
                    .disabled(item.status == .executing)
                    
                    // Delete button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            TaskQueueService.shared.remove(item)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Delete task")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showEditDialog) {
            EditTaskDialog(
                prompt: $editedPrompt,
                onSave: {
                    // Update the task in queue
                    if let index = TaskQueueService.shared.queue.firstIndex(where: { $0.id == item.id }) {
                        var updated = item
                        updated = TaskQueueItem(
                            id: item.id,
                            prompt: editedPrompt,
                            timestamp: item.timestamp,
                            status: item.status,
                            result: item.result,
                            error: item.error,
                            priority: item.priority
                        )
                        TaskQueueService.shared.queue[index] = updated
                    }
                    showEditDialog = false
                },
                onCancel: {
                    showEditDialog = false
                }
            )
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch item.status {
            case .pending:
                Circle()
                    .stroke(Color.secondary, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
            case .executing:
                ProgressView()
                    .scaleEffect(0.6)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            case .cancelled:
                Image(systemName: "circle.slash")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
            }
        }
    }
}

struct EditTaskDialog: View {
    @Binding var prompt: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
                    .font(.system(size: 16, weight: .medium))
                Text("Edit Task")
                    .font(DesignSystem.Typography.headline)
                Spacer()
            }
            
            Divider()
            
            // Text editor
            TextEditor(text: $prompt)
                .font(.system(size: 13))
                .frame(width: 450, height: 120)
                .padding(DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                        )
                )
                .focused($isFocused)
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 500)
        .onAppear {
            isFocused = true
        }
    }
}
