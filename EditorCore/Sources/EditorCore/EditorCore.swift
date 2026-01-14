//
//  EditorCore.swift
//  EditorCore
//
//  Core AI Edit Session engine - pure Swift, no UI dependencies
//

import Foundation

// MARK: - FileSnapshot

/// Immutable snapshot of a file at a point in time
public struct FileSnapshot: Equatable, Hashable {
    public let path: String
    public let content: String
    public let language: String?
    public let timestamp: Date
    
    public init(path: String, content: String, language: String? = nil, timestamp: Date = Date()) {
        self.path = path
        self.content = content
        self.language = language
        self.timestamp = timestamp
    }
}

// MARK: - EditSessionState

/// State machine for edit session lifecycle
public enum EditSessionState: Equatable {
    case idle
    case streaming
    case parsing
    case proposed([ProposedEdit])
    case transactionReady(EditTransaction)
    case committed(EditTransaction)
    case rolledBack(EditTransaction)
    case rejected([ProposedEdit])
    case error(String)
    
    public var isTerminal: Bool {
        switch self {
        case .committed, .rolledBack, .rejected, .error:
            return true
        default:
            return false
        }
    }
    
    public var canTransition: Bool {
        !isTerminal
    }
    
    public var proposedEdits: [ProposedEdit]? {
        switch self {
        case .proposed(let edits):
            return edits
        case .transactionReady(let transaction):
            return transaction.edits
        default:
            return nil
        }
    }
}

// MARK: - ProposedEdit

/// Represents a single proposed edit for a file
public struct ProposedEdit: Equatable, Identifiable {
    public let id: UUID
    public let filePath: String
    public let originalContent: String
    public let proposedContent: String
    public let diff: DiffResult
    public let metadata: EditMetadata
    
    public init(
        id: UUID = UUID(),
        filePath: String,
        originalContent: String,
        proposedContent: String,
        diff: DiffResult,
        metadata: EditMetadata = EditMetadata()
    ) {
        self.id = id
        self.filePath = filePath
        self.originalContent = originalContent
        self.proposedContent = proposedContent
        self.diff = diff
        self.metadata = metadata
    }
}

// MARK: - EditMetadata

/// Metadata about an edit proposal
public struct EditMetadata: Equatable {
    public let editType: EditType
    public let confidence: Double
    public let source: String
    public let timestamp: Date
    
    public init(
        editType: EditType = .modification,
        confidence: Double = 1.0,
        source: String = "ai",
        timestamp: Date = Date()
    ) {
        self.editType = editType
        self.confidence = confidence
        self.source = source
        self.timestamp = timestamp
    }
}

public enum EditType: Equatable {
    case creation
    case modification
    case deletion
}

// MARK: - DiffResult

/// Result of diff computation
public struct DiffResult: Equatable {
    public let hunks: [DiffHunk]
    public let addedLines: Int
    public let removedLines: Int
    public let unchangedLines: Int
    
    public init(hunks: [DiffHunk], addedLines: Int, removedLines: Int, unchangedLines: Int) {
        self.hunks = hunks
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.unchangedLines = unchangedLines
    }
    
    public var hasChanges: Bool {
        addedLines > 0 || removedLines > 0
    }
}

// MARK: - DiffHunk

/// A contiguous block of changes in a diff
public struct DiffHunk: Equatable {
    public let oldStartLine: Int
    public let oldLineCount: Int
    public let newStartLine: Int
    public let newLineCount: Int
    public let lines: [DiffLine]
    
    public init(
        oldStartLine: Int,
        oldLineCount: Int,
        newStartLine: Int,
        newLineCount: Int,
        lines: [DiffLine]
    ) {
        self.oldStartLine = oldStartLine
        self.oldLineCount = oldLineCount
        self.newStartLine = newStartLine
        self.newLineCount = newLineCount
        self.lines = lines
    }
}

// MARK: - DiffLine

/// A single line in a diff
public enum DiffLine: Equatable {
    case unchanged(String, lineNumber: Int)
    case added(String, lineNumber: Int)
    case removed(String, lineNumber: Int)
    
    public var content: String {
        switch self {
        case .unchanged(let text, _), .added(let text, _), .removed(let text, _):
            return text
        }
    }
    
    public var lineNumber: Int {
        switch self {
        case .unchanged(_, let num), .added(_, let num), .removed(_, let num):
            return num
        }
    }
}

// MARK: - EditInstruction

/// Instruction for an AI edit session
public struct EditInstruction: Equatable {
    public let text: String
    public let context: [String: String]?
    
    public init(text: String, context: [String: String]? = nil) {
        self.text = text
        self.context = context
    }
}
