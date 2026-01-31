//
//  TodoListView.swift
//  LingCode
//
//  Todo list view for complex prompts (Cursor-style)
//

import SwiftUI

struct TodoListView: View {
    @Binding var todos: [TodoItem]
    let onExecute: () -> Void
    let onCancel: () -> Void
    @State private var isExecuting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text("Task Breakdown")
                    .font(.headline)
                Spacer()
                Text("\(todos.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            
            Divider()
            
            // Todo list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                        TodoItemRow(
                            todo: todo,
                            index: index + 1,
                            onToggle: {
                                if let todoIndex = todos.firstIndex(where: { $0.id == todo.id }) {
                                    var updated = todos[todoIndex]
                                    if updated.status == .pending {
                                        updated.status = .completed
                                    } else if updated.status == .completed {
                                        updated.status = .pending
                                    }
                                    withAnimation(DesignSystem.Animation.smooth) {
                                        todos[todoIndex] = updated
                                    }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    isExecuting = true
                    onExecute()
                }) {
                    HStack {
                        if isExecuting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Execute All")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TodoItemRow: View {
    let todo: TodoItem
    let index: Int
    let onToggle: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator
            Button(action: onToggle) {
                Group {
                    switch todo.status {
                    case .pending:
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    case .inProgress:
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundColor(.blue)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .skipped:
                        Image(systemName: "circle.slash")
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(index).")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(todo.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(todo.status == .completed)
                        .foregroundColor(todo.status == .completed ? .secondary : .primary)
                }
                
                if let description = todo.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(todo.status == .completed ? DesignSystem.Colors.success.opacity(0.08) : Color.clear)
        )
        .animation(DesignSystem.Animation.smooth, value: todo.status)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
