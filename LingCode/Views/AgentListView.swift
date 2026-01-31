//
//  AgentListView.swift
//  LingCode
//
//  List view for managing multiple agents with search
//

import SwiftUI

struct AgentListView: View {
    @ObservedObject var coordinator: AgentCoordinator
    @StateObject private var historyService = AgentHistoryService.shared
    @Binding var selectedChatId: UUID?
    let onNewAgent: () -> Void
    @State private var renameItemId: UUID?
    @State private var renameText: String = ""

    private var currentTaskIds: Set<UUID> {
        Set(coordinator.agents.compactMap { $0.currentTask?.id })
    }

    private func excludeActiveTask(_ item: AgentHistoryItem) -> Bool {
        if item.status != .running { return true }
        return !currentTaskIds.contains(item.id)
    }

    private var pinnedToShow: [AgentHistoryItem] {
        historyService.pinnedHistory.filter(excludeActiveTask)
    }

    private var unpinnedToShow: [AgentHistoryItem] {
        historyService.unpinnedHistory.filter(excludeActiveTask)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search Agents...", text: $historyService.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button(action: onNewAgent) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("New Agent")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !pinnedToShow.isEmpty {
                        SectionHeader(title: "Pinned")
                        ForEach(pinnedToShow) { item in
                            AgentListRow(
                                agent: item,
                                isSelected: selectedChatId == item.id,
                                onSelect: { selectedChatId = item.id; historyService.markAsRead(item.id) },
                                onDelete: {
                                    historyService.deleteItem(item.id)
                                    if selectedChatId == item.id { selectedChatId = coordinator.agents.first?.id }
                                },
                                onMarkAsFailed: (item.status == .running && Date().timeIntervalSince(item.startTime) > 5 * 60) ? { historyService.markAsFailed(item.id) } : nil,
                                onTogglePin: { historyService.togglePin(item.id) },
                                onDuplicate: {
                                    if let newId = historyService.duplicateItem(item.id) { selectedChatId = newId }
                                },
                                onRename: {
                                    renameText = item.displayDescription
                                    renameItemId = item.id
                                },
                                onMarkAsUnread: { historyService.markAsUnread(item.id) },
                                isPinned: true
                            )
                        }
                    }

                    SectionHeader(title: "Agents")
                    ForEach(coordinator.agents) { agent in
                        AgentListAgentRow(
                            agent: agent,
                            isSelected: selectedChatId == agent.id,
                            onSelect: { selectedChatId = agent.id }
                        )
                    }
                    ForEach(unpinnedToShow) { item in
                        AgentListRow(
                            agent: item,
                            isSelected: selectedChatId == item.id,
                            onSelect: { selectedChatId = item.id; historyService.markAsRead(item.id) },
                            onDelete: {
                                historyService.deleteItem(item.id)
                                if selectedChatId == item.id { selectedChatId = coordinator.agents.first?.id }
                            },
                            onMarkAsFailed: (item.status == .running && Date().timeIntervalSince(item.startTime) > 5 * 60) ? { historyService.markAsFailed(item.id) } : nil,
                            onTogglePin: { historyService.togglePin(item.id) },
                            onDuplicate: {
                                if let newId = historyService.duplicateItem(item.id) { selectedChatId = newId }
                            },
                            onRename: {
                                renameText = item.displayDescription
                                renameItemId = item.id
                            },
                            onMarkAsUnread: { historyService.markAsUnread(item.id) },
                            isPinned: false
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Rename Agent", isPresented: Binding(get: { renameItemId != nil }, set: { if !$0 { renameItemId = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameItemId = nil }
            Button("OK") {
                if let id = renameItemId { historyService.renameItem(id, name: renameText) }
                renameItemId = nil
            }
        } message: {
            Text("Enter a display name for this agent run.")
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct AgentListAgentRow: View {
    @ObservedObject var agent: AgentService
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Group {
                    if !agent.steps.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                    } else if agent.isRunning {
                        PulseDot(color: .accentColor, size: 8, minScale: 0.75, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 1.1)
                    } else {
                        Image(systemName: "bubble.left")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.agentName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !agent.steps.isEmpty {
                        Text("\(agent.steps.count) step\(agent.steps.count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else if agent.currentTask != nil {
                        Text(agent.currentTask!.description.prefix(40) + (agent.currentTask!.description.count > 40 ? "..." : ""))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Idle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AgentListRow: View {
    let agent: AgentHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    var onMarkAsFailed: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onMarkAsUnread: (() -> Void)? = nil
    var isPinned: Bool = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if agent.isUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    statusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.displayDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Group {
                            if agent.status == .running && Date().timeIntervalSince(agent.startTime) > 5 * 60 {
                                Text("Stalled")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            } else {
                                Text(agent.startTime, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                if !agent.filesChanged.isEmpty {
                    HStack(spacing: 4) {
                        if agent.linesAdded > 0 || agent.linesRemoved > 0 {
                            Text("+\(agent.linesAdded) -\(agent.linesRemoved)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("·")
                                .foregroundColor(.secondary)
                        }
                        Text("\(agent.filesChanged.count) File\(agent.filesChanged.count == 1 ? "" : "s")")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, agent.isUnread ? 20 : 24)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if let onTogglePin = onTogglePin {
                Button(isPinned ? "Unpin" : "Pin") {
                    onTogglePin()
                }
            }
            if let onDuplicate = onDuplicate {
                Button("Duplicate") {
                    onDuplicate()
                }
            }
            if let onMarkAsUnread = onMarkAsUnread, !agent.isUnread {
                Button("Mark as Unread") {
                    onMarkAsUnread()
                }
            }
            if let onRename = onRename {
                Button("Rename") {
                    onRename()
                }
            }
            if let onMarkAsFailed = onMarkAsFailed {
                Button("Mark as failed") {
                    onMarkAsFailed()
                }
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch agent.status {
            case .running:
                if Date().timeIntervalSince(agent.startTime) > 5 * 60 {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                } else {
                    PulseDot(color: .accentColor, size: 8, minScale: 0.75, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 1.1)
                }
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            case .cancelled:
                Image(systemName: "slash.circle")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
            }
        }
    }
}
