//
//  ConversationListView.swift
//  LingCode
//
//  List view for managing multiple conversations with search
//

import SwiftUI

struct ConversationListView: View {
    @StateObject private var historyService = ConversationHistoryService.shared
    @Binding var selectedConversation: ConversationHistoryItem?
    let onNewConversation: () -> Void
    let onLoadConversation: (AIConversation) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search Conversations...", text: $historyService.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // New Conversation button
            Button(action: {
                onNewConversation()
                selectedConversation = nil
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("New Conversation")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .background(selectedConversation == nil ? Color.accentColor.opacity(0.1) : Color.clear)
            
            Divider()
            
            // Conversations list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(historyService.filteredConversations) { conversation in
                        ConversationListRow(
                            conversation: conversation,
                            isSelected: selectedConversation?.id == conversation.id,
                            onSelect: {
                                selectedConversation = conversation
                                if let loaded = historyService.loadConversation(by: conversation.id) {
                                    onLoadConversation(loaded)
                                }
                            },
                            onDelete: {
                                historyService.deleteConversation(conversation.id)
                                if selectedConversation?.id == conversation.id {
                                    selectedConversation = nil
                                }
                            },
                            onTogglePin: {
                                historyService.togglePin(conversation.id)
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

struct ConversationListRow: View {
    let conversation: ConversationHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 10))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(conversation.updatedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Subtitle with message/file info
                if conversation.fileCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(conversation.fileCount) file\(conversation.fileCount == 1 ? "" : "s")")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, conversation.isPinned ? 24 : 0)
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
            Button(conversation.isPinned ? "Unpin" : "Pin") {
                onTogglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}
