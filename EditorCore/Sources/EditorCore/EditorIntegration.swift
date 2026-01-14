//
//  EditorIntegration.swift
//  EditorCore
//
//  Clean integration boundary between EditorCore and SwiftUI Editor
//

import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - Integration Protocol

/// Single protocol for editor to interact with EditorCore
/// Editor does not need to know about AI internals, transactions, or state machines
@MainActor
public protocol EditSessionCoordinator {
    /// Start a new edit session with instruction and current file states
    func startEditSession(
        instruction: String,
        files: [FileState]
    ) -> EditSessionHandle
    
    /// Get current active session (if any)
    var activeSession: EditSessionHandle? { get }
}

// MARK: - File State (Editor-facing)

/// Simplified file state representation for editor
public struct FileState: Equatable, Identifiable {
    public let id: String // File path
    public let content: String
    public let language: String?
    
    public init(id: String, content: String, language: String? = nil) {
        self.id = id
        self.content = content
        self.language = language
    }
}

// MARK: - Edit Session Handle

/// Handle to an active edit session - editor uses this to interact
public protocol EditSessionHandle: AnyObject {
    /// Unique session identifier
    var id: UUID { get }
    
    /// Observable model for UI updates
    var model: EditSessionModel { get }
    
    /// Append streaming text chunk from AI
    func appendStreamingText(_ text: String)
    
    /// Complete streaming (call when AI finishes)
    func completeStreaming()
    
    /// Accept all proposed edits
    func acceptAll() -> [EditToApply]
    
    /// Accept specific edits by ID
    func accept(editIds: Set<UUID>) -> [EditToApply]
    
    /// Reject all proposed edits
    func rejectAll()
    
    /// Reject specific edits by ID
    func reject(editIds: Set<UUID>)
    
    /// Undo last accepted edit (if supported)
    func undo() -> [EditToApply]?
    
    /// Check if undo is available
    var canUndo: Bool { get }
}

// MARK: - Edit Session Model (UI-facing)

/// Observable model for SwiftUI - contains all UI state
@MainActor
public class EditSessionModel: ObservableObject {
    @Published public var status: EditSessionStatus = .idle
    @Published public var streamingText: String = ""
    @Published public var proposedEdits: [EditProposal] = []
    @Published public var errorMessage: String?
    
    public init() {}
}

// MARK: - Edit Session Status

/// Simple status enum for UI
public enum EditSessionStatus: Equatable {
    case idle
    case streaming
    case ready // Edits are ready for review
    case applied // Edits have been applied
    case rejected
    case error(String)
}

// MARK: - Edit Proposal (UI-facing)

/// Simplified edit proposal for UI display
public struct EditProposal: Equatable, Identifiable {
    public let id: UUID
    public let filePath: String
    public let fileName: String
    public let preview: EditPreview
    public let statistics: EditStatistics
    
    public init(
        id: UUID,
        filePath: String,
        fileName: String,
        preview: EditPreview,
        statistics: EditStatistics
    ) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.preview = preview
        self.statistics = statistics
    }
}

// MARK: - Edit Preview

/// Preview information for UI
public struct EditPreview: Equatable {
    public let addedLines: Int
    public let removedLines: Int
    public let diffHunks: [DiffHunkPreview]
    
    public init(addedLines: Int, removedLines: Int, diffHunks: [DiffHunkPreview]) {
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.diffHunks = diffHunks
    }
}

// MARK: - Diff Hunk Preview

/// Simplified diff hunk for UI display
public struct DiffHunkPreview: Equatable {
    public let oldStartLine: Int
    public let newStartLine: Int
    public let lines: [DiffLinePreview]
    
    public init(oldStartLine: Int, newStartLine: Int, lines: [DiffLinePreview]) {
        self.oldStartLine = oldStartLine
        self.newStartLine = newStartLine
        self.lines = lines
    }
}

// MARK: - Diff Line Preview

/// Simplified diff line for UI
public struct DiffLinePreview: Equatable {
    public enum ChangeType: Equatable {
        case unchanged
        case added
        case removed
    }
    
    public let type: ChangeType
    public let content: String
    public let lineNumber: Int
    
    public init(type: ChangeType, content: String, lineNumber: Int) {
        self.type = type
        self.content = content
        self.lineNumber = lineNumber
    }
}

// MARK: - Edit Statistics

/// Statistics about an edit
public struct EditStatistics: Equatable {
    public let addedLines: Int
    public let removedLines: Int
    public let netChange: Int
    
    public init(addedLines: Int, removedLines: Int) {
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.netChange = addedLines - removedLines
    }
}

// MARK: - Edit To Apply (Editor-facing)

/// Final edit instruction for editor to apply
/// Editor receives this and applies it to actual files
public struct EditToApply: Equatable, Identifiable {
    public let id: UUID
    public let filePath: String
    public let newContent: String
    public let originalContent: String
    
    public init(id: UUID, filePath: String, newContent: String, originalContent: String) {
        self.id = id
        self.filePath = filePath
        self.newContent = newContent
        self.originalContent = originalContent
    }
}
