//
//  ConversationHistoryService.swift
//  LingCode
//
//  Persistent storage for conversation history
//  Enables multiple conversations, search, and history management
//

import Foundation
import Combine

/// Represents a saved conversation
struct ConversationHistoryItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let projectURL: URL?
    let messages: [AIMessageHistory]
    let createdAt: Date
    var updatedAt: Date
    var fileCount: Int
    var isPinned: Bool
    
    init(id: UUID = UUID(), title: String, projectURL: URL?, messages: [AIMessageHistory], createdAt: Date = Date(), updatedAt: Date = Date(), fileCount: Int = 0, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.projectURL = projectURL
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileCount = fileCount
        self.isPinned = isPinned
    }
}

struct AIMessageHistory: Codable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
    
    init(from message: AIMessage) {
        self.id = message.id
        self.role = String(describing: message.role)
        self.content = message.content
        self.timestamp = message.timestamp
    }
    
    func toAIMessage() -> AIMessage {
        let role: AIMessageRole
        switch self.role {
        case "user": role = .user
        case "assistant": role = .assistant
        case "system": role = .system
        default: role = .user
        }
        return AIMessage(id: id, role: role, content: content, timestamp: timestamp)
    }
}

/// Service for managing conversation history
@MainActor
class ConversationHistoryService: ObservableObject {
    static let shared = ConversationHistoryService()
    
    @Published var conversations: [ConversationHistoryItem] = []
    @Published var searchQuery: String = ""
    @Published var selectedConversationId: UUID?
    
    private let historyFileURL: URL
    private let fileManager = FileManager.default
    
    private init() {
        // Store history in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingCodeDir = appSupport.appendingPathComponent("LingCode")
        
        // Create directory if needed
        try? fileManager.createDirectory(at: lingCodeDir, withIntermediateDirectories: true)
        
        historyFileURL = lingCodeDir.appendingPathComponent("conversation_history.json")
        loadHistory()
    }
    
    /// Save a conversation
    func saveConversation(_ conversation: AIConversation, title: String? = nil, projectURL: URL?, fileCount: Int = 0) {
        let messageHistory = conversation.messages.map { AIMessageHistory(from: $0) }
        
        // Generate title from first user message if not provided
        let finalTitle = title ?? conversation.messages.first(where: { 
            if case .user = $0.role { return true }
            return false
        })?.content.prefix(50).description ?? "New Conversation"
        
        let historyItem = ConversationHistoryItem(
            title: String(finalTitle),
            projectURL: projectURL,
            messages: messageHistory,
            updatedAt: Date(),
            fileCount: fileCount
        )
        
        // Update or add item
        if let index = conversations.firstIndex(where: { $0.id == historyItem.id }) {
            conversations[index] = ConversationHistoryItem(
                id: historyItem.id,
                title: historyItem.title,
                projectURL: historyItem.projectURL,
                messages: historyItem.messages,
                createdAt: conversations[index].createdAt,
                updatedAt: Date(),
                fileCount: fileCount,
                isPinned: conversations[index].isPinned
            )
        } else {
            conversations.insert(historyItem, at: 0) // Most recent first
        }
        
        saveHistory()
    }
    
    /// Load a conversation by ID
    func loadConversation(by id: UUID) -> AIConversation? {
        guard let item = conversations.first(where: { $0.id == id }) else { return nil }
        
        let conversation = AIConversation()
        conversation.messages = item.messages.map { $0.toAIMessage() }
        return conversation
    }
    
    /// Delete a conversation
    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = nil
        }
        saveHistory()
    }
    
    /// Pin/unpin a conversation
    func togglePin(_ id: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            let item = conversations[index]
            conversations[index] = ConversationHistoryItem(
                id: item.id,
                title: item.title,
                projectURL: item.projectURL,
                messages: item.messages,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                fileCount: item.fileCount,
                isPinned: !item.isPinned
            )
            saveHistory()
        }
    }
    
    /// Get filtered conversations based on search query
    var filteredConversations: [ConversationHistoryItem] {
        var filtered = conversations
        
        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            filtered = filtered.filter { item in
                item.title.lowercased().contains(query) ||
                item.messages.contains(where: { $0.content.lowercased().contains(query) })
            }
        }
        
        // Sort: pinned first, then by updated date
        return filtered.sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned
            }
            return first.updatedAt > second.updatedAt
        }
    }
    
    /// Clear all conversations
    func clearHistory() {
        conversations.removeAll()
        selectedConversationId = nil
        saveHistory()
    }
    
    // MARK: - Private Methods
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path),
              let data = try? Data(contentsOf: historyFileURL),
              let decoded = try? JSONDecoder().decode([ConversationHistoryItem].self, from: data) else {
            conversations = []
            return
        }
        
        conversations = decoded.sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned
            }
            return first.updatedAt > second.updatedAt
        }
    }
    
    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: historyFileURL)
    }
}
