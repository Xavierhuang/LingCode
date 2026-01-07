//
//  AIConversation.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

enum AIMessageRole {
    case user
    case assistant
    case system
}

struct AIMessage: Identifiable {
    let id: UUID
    let role: AIMessageRole
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: AIMessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

class AIConversation: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var isStreaming: Bool = false
    
    func addMessage(_ message: AIMessage) {
        messages.append(message)
    }
    
    func clear() {
        messages.removeAll()
    }
}

