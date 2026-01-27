//
//  AgentListView.swift
//  LingCode
//
//  List view for managing multiple agents with search
//

import SwiftUI

struct AgentListView: View {
    @StateObject private var historyService = AgentHistoryService.shared
    @State private var selectedAgentId: UUID?
    @Binding var selectedAgent: AgentHistoryItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
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
            
            // New Agent button
            Button(action: {
                selectedAgent = nil
                selectedAgentId = nil
            }) {
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
            .background(selectedAgentId == nil ? Color.accentColor.opacity(0.1) : Color.clear)
            
            Divider()
            
            // Agents list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(historyService.filteredHistory) { agent in
                        AgentListRow(
                            agent: agent,
                            isSelected: selectedAgentId == agent.id,
                            onSelect: {
                                selectedAgentId = agent.id
                                selectedAgent = agent
                            },
                            onDelete: {
                                historyService.deleteItem(agent.id)
                                if selectedAgentId == agent.id {
                                    selectedAgent = nil
                                    selectedAgentId = nil
                                }
                            }
                        )
                    }
                }
            }
        }
        .frame(minWidth: 250, idealWidth: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct AgentListRow: View {
    let agent: AgentHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Status icon
                    statusIcon
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.displayDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(agent.startTime, style: .relative)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Subtitle with file info
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
                    .padding(.leading, 24)
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
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch agent.status {
            case .running:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
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
