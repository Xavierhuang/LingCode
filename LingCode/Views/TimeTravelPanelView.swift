//
//  TimeTravelPanelView.swift
//  LingCode
//
//  A slide-out panel showing the full undo/redo snapshot history.
//  Each row shows the operation name, timestamp, and affected file count.
//  Tapping any row calls jumpToSnapshot() to restore that exact state.
//  Presented as a sheet from the editor toolbar or via ⌘⇧Z.
//

import SwiftUI

struct TimeTravelPanelView: View {
    let workspaceURL: URL
    var onDismiss: () -> Void

    @State private var undoStack: [UndoSnapshot] = []
    @State private var redoStack: [UndoSnapshot] = []
    @State private var jumping: UUID? = nil
    @State private var justRestored: UUID? = nil

    private let service = TimeTravelUndoService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if undoStack.isEmpty && redoStack.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !redoStack.isEmpty {
                            sectionLabel("Redo (\(redoStack.count))", color: .secondary)
                            ForEach(Array(redoStack.reversed())) { snap in
                                snapshotRow(snap, isRedo: true)
                                Divider().padding(.leading, 48)
                            }
                        }

                        sectionLabel("History (\(undoStack.count))", color: .accentColor)
                        // Most recent first
                        ForEach(Array(undoStack.reversed())) { snap in
                            snapshotRow(snap, isRedo: false)
                            Divider().padding(.leading, 48)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 440)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.2.circlepath")
                .foregroundColor(.accentColor)
                .font(.system(size: 15))
            Text("Checkpoints")
                .font(.headline)
            Spacer()
            Button {
                service.clearHistory()
                refresh()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(undoStack.isEmpty && redoStack.isEmpty)

            Button("Done") { onDismiss() }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 40))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
            Text("No checkpoints yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Checkpoints are created automatically when the agent edits files, renames symbols, or performs refactors.")
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Snapshot row

    private func snapshotRow(_ snap: UndoSnapshot, isRedo: Bool) -> some View {
        let isJumping = jumping == snap.id
        let wasRestored = justRestored == snap.id

        return Button {
            jumpTo(snap)
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isRedo ? Color(NSColor.controlBackgroundColor) : Color.accentColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    if isJumping {
                        ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
                    } else if wasRestored {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: operationIcon(snap.operation))
                            .font(.system(size: 11))
                            .foregroundColor(isRedo ? .secondary : .accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(relativeTime(snap.timestamp))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if snap.affectedFilesCount > 0 {
                            Text("·")
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            Text("\(snap.affectedFilesCount) file\(snap.affectedFilesCount == 1 ? "" : "s")")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Text("Restore")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .opacity(isJumping ? 0 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(wasRestored ? Color.green.opacity(0.06) : Color.clear)
    }

    // MARK: - Actions

    private func jumpTo(_ snap: UndoSnapshot) {
        jumping = snap.id
        Task.detached(priority: .userInitiated) {
            _ = TimeTravelUndoService.shared.jumpToSnapshot(snap.id, in: workspaceURL)
            await MainActor.run {
                jumping = nil
                justRestored = snap.id
                refresh()
                // Clear the "restored" highlight after 2 s
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if justRestored == snap.id { justRestored = nil }
                }
            }
        }
    }

    private func refresh() {
        undoStack = service.getUndoStack()
        redoStack = service.getRedoStack()
    }

    // MARK: - Helpers

    private func operationIcon(_ op: UndoSnapshot.UndoOperation) -> String {
        switch op {
        case .rename:           return "pencil.and.outline"
        case .refactor:         return "wand.and.stars"
        case .extractFunction:  return "arrow.up.right.and.arrow.down.left.rectangle"
        case .multiFileEdit:    return "doc.on.doc"
        case .generic:          return "clock.arrow.circlepath"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 60    { return "\(diff)s ago" }
        if diff < 3600  { return "\(diff / 60)m ago" }
        if diff < 86400 { return "\(diff / 3600)h ago" }
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Convenience toolbar button

/// Drop-in button that presents the TimeTravelPanelView as a sheet.
struct TimeTravelButton: View {
    let workspaceURL: URL
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "clock.arrow.2.circlepath")
                .help("Checkpoints — browse and restore AI edit history")
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $isPresented) {
            TimeTravelPanelView(workspaceURL: workspaceURL) {
                isPresented = false
            }
        }
    }
}
