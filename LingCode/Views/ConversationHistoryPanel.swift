//
//  ConversationHistoryPanel.swift
//  LingCode
//
//  Shows conversation history with search and selection
//

import SwiftUI

struct ConversationHistoryPanel: View {
    @StateObject private var historyService = ConversationHistoryService.shared
    @ObservedObject var viewModel: AIViewModel
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var hoveredId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.secondaryBackground)
            
            Divider()
            
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                TextField("Search conversations...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Conversation list
            if filteredConversations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredConversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isHovered: hoveredId == conversation.id,
                                onSelect: { selectConversation(conversation) },
                                onDelete: { deleteConversation(conversation) },
                                onPin: { togglePin(conversation) }
                            )
                            .onHover { hoveredId = $0 ? conversation.id : nil }
                        }
                    }
                    .padding(8)
                }
            }
            
            Divider()
            
            // Footer with new conversation button
            HStack {
                Button(action: newConversation) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("New Chat")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Text("\(historyService.conversations.count) conversations")
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.secondaryBackground)
        }
        .frame(width: 280)
        .background(DesignSystem.Colors.primaryBackground)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
    }
    
    // MARK: - Filtered Conversations
    
    private var filteredConversations: [ConversationHistoryItem] {
        let sorted = historyService.conversations.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        
        if searchText.isEmpty {
            return sorted
        }
        
        let query = searchText.lowercased()
        return sorted.filter { conversation in
            conversation.title.lowercased().contains(query) ||
            conversation.messages.contains { $0.content.lowercased().contains(query) }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            
            Text(searchText.isEmpty ? "No conversations yet" : "No matching conversations")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            if searchText.isEmpty {
                Text("Start a new chat to begin")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Actions
    
    private func selectConversation(_ conversation: ConversationHistoryItem) {
        // Load conversation into viewModel
        viewModel.loadConversation(conversation)
        isPresented = false
    }
    
    private func deleteConversation(_ conversation: ConversationHistoryItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            historyService.deleteConversation(conversation.id)
        }
    }
    
    private func togglePin(_ conversation: ConversationHistoryItem) {
        historyService.togglePin(conversation.id)
    }
    
    private func newConversation() {
        viewModel.clearConversation()
        isPresented = false
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: ConversationHistoryItem
    let isHovered: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: conversation.isPinned ? "pin.fill" : "bubble.left")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(formatDate(conversation.updatedAt))
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        if conversation.fileCount > 0 {
                            Text("-")
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            Text("\(conversation.fileCount) files")
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                // Actions (show on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onPin) {
                            Image(systemName: conversation.isPinned ? "pin.slash" : "pin")
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(conversation.isPinned ? "Unpin" : "Pin")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Delete")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
