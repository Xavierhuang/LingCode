//
//  AIConversation.swift
//  LingCode
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
    /// true when this message is a compressed summary of earlier messages
    var isSummary: Bool = false

    init(id: UUID = UUID(), role: AIMessageRole, content: String, timestamp: Date = Date(), isSummary: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isSummary = isSummary
    }
}

class AIConversation: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var isStreaming: Bool = false
    @Published var isSummarizing: Bool = false

    /// Rough token estimate: 4 chars ≈ 1 token
    var estimatedTokenCount: Int {
        messages.reduce(0) { $0 + $1.content.count / 4 }
    }

    func addMessage(_ message: AIMessage) {
        messages.append(message)
    }

    func clear() {
        messages.removeAll()
    }

    // MARK: - Auto-summarize

    /// Call after each assistant turn. If the estimated context exceeds
    /// `threshold` tokens, summarize the oldest half of messages and replace
    /// them with a single summary message so the window stays manageable.
    func autoSummarizeIfNeeded(threshold: Int = 12_000) async {
        guard estimatedTokenCount > threshold, !isSummarizing else { return }
        // Need at least 6 messages before summarizing
        guard messages.count >= 6 else { return }

        await MainActor.run { isSummarizing = true }

        // Take the oldest half (excluding any existing summary at index 0)
        let startIndex = messages.first?.isSummary == true ? 1 : 0
        let halfCount = (messages.count - startIndex) / 2
        guard halfCount > 0 else {
            await MainActor.run { isSummarizing = false }
            return
        }
        let toCompress = Array(messages[startIndex ..< startIndex + halfCount])
        let remaining  = Array(messages[(startIndex + halfCount)...])

        // Build a transcript for the AI to summarize
        let transcript = toCompress.map { msg -> String in
            let role = msg.role == .user ? "User" : "Assistant"
            return "\(role): \(msg.content.prefix(1000))"
        }.joined(separator: "\n\n")

        let prompt = """
        Summarize the following conversation excerpt in 3–5 concise bullet points. \
        Preserve key decisions, code changes, file paths, and important context. \
        Do not include any preamble — output only the bullet points.

        \(transcript)
        """

        do {
            let summary = try await AIService.shared.sendMessage(prompt, context: nil)
            let summaryMessage = AIMessage(
                role: .system,
                content: "**[Conversation summary — \(toCompress.count) messages compressed]**\n\n\(summary)",
                isSummary: true
            )
            await MainActor.run {
                // Replace compressed messages with the summary + keep the rest
                var newMessages: [AIMessage] = []
                if messages.first?.isSummary == true {
                    newMessages.append(messages[0]) // keep previous summary if any
                }
                newMessages.append(summaryMessage)
                newMessages.append(contentsOf: remaining)
                self.messages = newMessages
                self.isSummarizing = false
            }
        } catch {
            await MainActor.run { isSummarizing = false }
        }
    }
}

