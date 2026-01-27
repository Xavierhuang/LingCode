//
//  TaskQueueView.swift
//  LingCode
//
//  Task queue UI (Cursor feature)
//

import SwiftUI

struct TaskQueueView: View {
    @ObservedObject var queueService = TaskQueueService.shared
    @State private var expandedItems: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.blue)
                Text("Task Queue")
                    .font(.headline)
                Spacer()
                if !queueService.queue.isEmpty {
                    Text("\(queueService.queue.count) task\(queueService.queue.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            
            Divider()
            
            // Queue list
            if queueService.queue.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No tasks in queue")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tasks you submit will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(queueService.queue) { item in
                            TaskQueueItemRow(
                                item: item,
                                isExpanded: expandedItems.contains(item.id),
                                onToggleExpand: {
                                    if expandedItems.contains(item.id) {
                                        expandedItems.remove(item.id)
                                    } else {
                                        expandedItems.insert(item.id)
                                    }
                                },
                                onCancel: {
                                    queueService.cancel(item)
                                },
                                onRemove: {
                                    queueService.remove(item)
                                },
                                onMoveUp: {
                                    queueService.moveUp(item)
                                },
                                onMoveDown: {
                                    queueService.moveDown(item)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Clear Completed") {
                    queueService.clearCompleted()
                }
                .buttonStyle(.bordered)
                .disabled(queueService.queue.allSatisfy { $0.status == .pending || $0.status == .executing })
                
                Spacer()
                
                Button("Clear All") {
                    queueService.clearAll()
                }
                .buttonStyle(.bordered)
                .disabled(queueService.queue.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TaskQueueItemRow: View {
    let item: TaskQueueItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Status icon
                statusIcon
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.prompt)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(isExpanded ? nil : 2)
                            .foregroundColor(item.status == .cancelled ? .secondary : .primary)
                        
                        Spacer()
                        
                        // Priority badge
                        if item.priority == .high {
                            Text("HIGH")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    // Metadata
                    HStack {
                        Text(item.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if item.status == .executing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    
                    // Result/Error (if expanded)
                    if isExpanded {
                        if let result = item.result {
                            Text("Result:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(result)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if let error = item.error {
                            Text("Error:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Actions
                HStack(spacing: 4) {
                    if item.status == .pending {
                        Button(action: onMoveUp) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Move up")
                        
                        Button(action: onMoveDown) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Move down")
                    }
                    
                    if item.status == .executing || item.status == .pending {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Cancel")
                    } else {
                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Remove")
                    }
                    
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isExpanded ? "Collapse" : "Expand")
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: item.status == .executing ? 2 : 1)
        )
    }
    
    private var statusIcon: some View {
        Group {
            switch item.status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            case .executing:
                ProgressView()
                    .scaleEffect(0.7)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .cancelled:
                Image(systemName: "circle.slash")
                    .foregroundColor(.orange)
            }
        }
        .font(.system(size: 16))
    }
    
    private var backgroundColor: Color {
        switch item.status {
        case .executing:
            return Color.blue.opacity(0.1)
        case .completed:
            return Color.green.opacity(0.05)
        case .failed:
            return Color.red.opacity(0.05)
        case .cancelled:
            return Color.orange.opacity(0.05)
        default:
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        switch item.status {
        case .executing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        default:
            return Color.secondary.opacity(0.2)
        }
    }
}
