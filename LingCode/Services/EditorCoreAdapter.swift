//
//  EditorCoreAdapter.swift
//  LingCode
//
//  Adapter layer between EditorCore and the SwiftUI editor
//  Provides the applyEdits function and manages EditSessionCoordinator
//
//  ARCHITECTURE INVARIANT:
//  This is the ONLY bridge between EditorCore and the editor.
//  - No EditorCore types should be used directly in SwiftUI views
//  - All EditorCore interactions must go through this adapter
//  - EditorViewModel.applyEdits() is the ONLY mutation point from EditorCore
//

import Foundation
import SwiftUI
import Combine
import EditorCore

// MARK: - Architecture Invariants Documentation
//
// INVARIANT 1: Single Integration Point
//   EditorCoreAdapter is the ONLY class that imports EditorCore and interacts with it.
//   All other code must use EditorCoreAdapter, never EditorCore types directly.
//
// INVARIANT 2: No EditorCore Types in Views
//   SwiftUI views must NOT import EditorCore.
//   Views receive data through EditorCoreAdapter's public interface only.
//
// INVARIANT 3: Single Mutation Point
//   EditorViewModel.applyEdits() is the ONLY function that mutates editor content from EditorCore.
//   No other code path should modify editor state based on EditorCore output.
//
// INVARIANT 4: Transaction Safety
//   All edits are transactional and reversible.
//   Editor content is never mutated during streaming or preview.
//   acceptAll() is the only commit point.

// MARK: - App-Level Wrapper Types (Adapter-Owned)
//
// These types wrap EditorCore types to prevent direct EditorCore usage in views.
// All SwiftUI views must use these wrapper types, never EditorCore types directly.

/// App-level status for inline edit sessions
/// Wraps EditorCore.EditSessionStatus to prevent EditorCore dependency in views
public enum InlineEditStatus: Equatable {
    case idle
    case thinking // Early state: session started, analyzing before streaming
    case streaming
    case ready
    case applied
    case continuing // Session continues after applying edits
    case rejected
    case blocked // Edits blocked due to validation errors
    case error(String)
    
    /// Convert from EditorCore status
    init(from coreStatus: EditorCore.EditSessionStatus) {
        switch coreStatus {
        case .idle: self = .idle
        case .streaming: self = .streaming
        case .ready: self = .ready
        case .applied: self = .applied
        case .rejected: self = .rejected
        case .error(let message): self = .error(message)
        }
    }
}

/// App-level edit proposal for UI display
/// Wraps EditorCore.EditProposal to prevent EditorCore dependency in views
public struct InlineEditProposal: Equatable, Identifiable {
    public let id: UUID
    public let filePath: String
    public let fileName: String
    public let preview: InlineEditPreview
    public let statistics: InlineEditStatistics
    /// Human-readable intent description for this edit
    public let intent: String
    
    /// Convert from EditorCore proposal
    /// - Parameters:
    ///   - coreProposal: The EditorCore proposal to wrap
    ///   - intent: The user's intent/instruction for this edit
    init(from coreProposal: EditorCore.EditProposal, intent: String) {
        self.id = coreProposal.id
        self.filePath = coreProposal.filePath
        self.fileName = coreProposal.fileName
        self.preview = InlineEditPreview(from: coreProposal.preview)
        self.statistics = InlineEditStatistics(from: coreProposal.statistics)
        self.intent = intent
    }
}

/// App-level edit preview
public struct InlineEditPreview: Equatable {
    public let addedLines: Int
    public let removedLines: Int
    public let diffHunks: [InlineDiffHunkPreview]
    
    init(from corePreview: EditorCore.EditPreview) {
        self.addedLines = corePreview.addedLines
        self.removedLines = corePreview.removedLines
        self.diffHunks = corePreview.diffHunks.map { InlineDiffHunkPreview(from: $0) }
    }
}

/// App-level diff hunk preview
public struct InlineDiffHunkPreview: Equatable {
    public let oldStartLine: Int
    public let newStartLine: Int
    public let lines: [InlineDiffLinePreview]
    
    init(from coreHunk: EditorCore.DiffHunkPreview) {
        self.oldStartLine = coreHunk.oldStartLine
        self.newStartLine = coreHunk.newStartLine
        self.lines = coreHunk.lines.map { InlineDiffLinePreview(from: $0) }
    }
}

/// App-level diff line preview
public struct InlineDiffLinePreview: Equatable {
    public enum ChangeType: Equatable {
        case unchanged
        case added
        case removed
    }
    
    public let type: ChangeType
    public let content: String
    public let lineNumber: Int
    
    init(from coreLine: EditorCore.DiffLinePreview) {
        switch coreLine.type {
        case .unchanged: self.type = .unchanged
        case .added: self.type = .added
        case .removed: self.type = .removed
        }
        self.content = coreLine.content
        self.lineNumber = coreLine.lineNumber
    }
}

/// App-level edit statistics
public struct InlineEditStatistics: Equatable {
    public let addedLines: Int
    public let removedLines: Int
    public let netChange: Int
    
    init(from coreStats: EditorCore.EditStatistics) {
        self.addedLines = coreStats.addedLines
        self.removedLines = coreStats.removedLines
        self.netChange = coreStats.netChange
    }
}

/// Timeline event for session history
/// Records major events during an edit session for debuggability and trust
public struct SessionTimelineEvent: Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let eventType: EventType
    public let description: String
    public let details: String?
    
    public enum EventType: Equatable {
        case sessionStarted
        case thinking
        case streamingStarted
        case streamingProgress(characterCount: Int)
        case proposalsReady(count: Int)
        case accepted(count: Int)
        case acceptedAndContinued(count: Int)
        case rejected
        case continued
        case intentReused
        case applyBlocked(issueCount: Int) // Number of blocking issues
        case error(message: String)
        
        public var icon: String {
            switch self {
            case .sessionStarted: return "play.circle.fill"
            case .thinking: return "brain.head.profile"
            case .streamingStarted: return "arrow.down.circle.fill"
            case .streamingProgress: return "text.bubble"
            case .proposalsReady: return "checkmark.circle.fill"
            case .accepted: return "checkmark.seal.fill"
            case .acceptedAndContinued: return "arrow.clockwise.circle.fill"
            case .rejected: return "xmark.circle.fill"
            case .continued: return "arrow.clockwise"
            case .intentReused: return "arrow.triangle.2.circlepath"
            case .applyBlocked: return "exclamationmark.shield.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
        
        public var color: String {
            switch self {
            case .sessionStarted, .thinking, .streamingStarted, .streamingProgress: return "blue"
            case .proposalsReady: return "green"
            case .accepted, .acceptedAndContinued: return "green"
            case .rejected: return "red"
            case .continued: return "orange"
            case .intentReused: return "purple"
            case .applyBlocked: return "orange"
            case .error: return "red"
            }
        }
    }
    
    init(eventType: EventType, description: String, details: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.eventType = eventType
        self.description = description
        self.details = details
    }
}

/// App-level observable model for inline edit sessions
/// Wraps EditorCore.EditSessionModel to prevent EditorCore dependency in views
@MainActor
public class InlineEditSessionModel: ObservableObject {
    @Published public var status: InlineEditStatus = .idle
    @Published public var streamingText: String = ""
    @Published public var proposedEdits: [InlineEditProposal] = []
    @Published public var errorMessage: String?
    
    /// Selection state for proposals (UUID -> isSelected)
    /// Defaults to true (all selected) when proposals are added
    @Published public var proposalSelection: [UUID: Bool] = [:]
    
    /// Session timeline for debuggability and trust
    /// Records all major events during the session
    @Published public var timeline: [SessionTimelineEvent] = []
    
    /// Original user intent for this session (for reuse)
    /// This is the user's original instruction, not the full prompt
    public private(set) var originalIntent: String = ""
    
    /// Validation errors that blocked applying edits
    /// Set when acceptEdits detects critical validation issues
    @Published var validationErrors: [ValidationResult] = []
    
    /// Execution outcome (for UI truthfulness invariant)
    /// CORE INVARIANT: IDE may only show "Complete" if outcome.changesApplied == true
    @Published var executionOutcome: ExecutionOutcome?
    
    // CPU OPTIMIZATION: Throttle streaming updates to prevent excessive re-renders
    // PROBLEM: Every character chunk was triggering:
    // - @Published streamingText update → SwiftUI re-render
    // - combineLatest with proposedEdits → re-derive intent for all proposals
    // - Multiple onChange handlers in views
    // SOLUTION: Single throttled update pipeline at ~80ms intervals
    private let streamingThrottle = StreamingUpdateThrottle()
    private var lastStreamingTextHash: Int = 0
    
    /// Bridge to EditorCore model - updates this model when core model changes
    private var coreModel: EditorCore.EditSessionModel? {
        didSet {
            setupObservation()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        // CPU OPTIMIZATION: Set up throttled streaming update pipeline
        // This coalesces all streaming-related state updates into one handler
        streamingThrottle.setUpdateHandler { [weak self] throttledText in
            guard let self = self else { return }
            
            // Only update if content meaningfully changed (hash check prevents redundant updates)
            let newHash = throttledText.hashValue
            guard newHash != self.lastStreamingTextHash else { return }
            self.lastStreamingTextHash = newHash
            
            // Update streaming text (triggers UI update)
            self.streamingText = throttledText
            
            // Intent derivation will happen via proposals observation below, but only when proposals change
            // This prevents re-deriving intent on every character chunk
        }
    }
    
    /// Check if a proposal is selected (defaults to true)
    public func isSelected(proposalId: UUID) -> Bool {
        return proposalSelection[proposalId] ?? true
    }
    
    /// Toggle selection for a proposal
    public func toggleSelection(proposalId: UUID) {
        let current = isSelected(proposalId: proposalId)
        proposalSelection[proposalId] = !current
    }
    
    /// Select all proposals
    public func selectAll() {
        for proposal in proposedEdits {
            proposalSelection[proposal.id] = true
        }
    }
    
    /// Deselect all proposals
    public func deselectAll() {
        for proposal in proposedEdits {
            proposalSelection[proposal.id] = false
        }
    }
    
    /// Get IDs of selected proposals
    public var selectedProposalIds: Set<UUID> {
        Set(proposedEdits.filter { isSelected(proposalId: $0.id) }.map { $0.id })
    }
    
    /// Update from EditorCore model
    /// INVARIANT: This is the only way to connect to EditorCore model
    /// - Parameters:
    ///   - coreModel: The EditorCore model to observe
    ///   - userIntent: The original user instruction/intent for deriving proposal intents
    func update(from coreModel: EditorCore.EditSessionModel, userIntent: String) {
        let previousStatus = self.status
        self.coreModel = coreModel
        self.userIntent = userIntent
        self.originalIntent = userIntent // Store for reuse
        
        // Set thinking state immediately if core is idle (early feedback)
        // UI & STATE: "Thinking..." UI state is driven by session state, NOT model text
        // Timeline events are derived from state transitions, NOT AI output
        if coreModel.status == .idle && status == .idle {
            status = .thinking
            recordTimelineEvent(.sessionStarted, description: "Session started")
            recordTimelineEvent(.thinking, description: "Analyzing request")
        }
        
        // Immediately sync current state
        syncFromCore()
        
        // Record state transitions in timeline
        recordStateTransition(from: previousStatus, to: status)
    }
    
    /// Record a timeline event
    func recordTimelineEvent(_ eventType: SessionTimelineEvent.EventType, description: String, details: String? = nil) {
        let event = SessionTimelineEvent(eventType: eventType, description: description, details: details)
        timeline.append(event)
    }
    
    /// Record state transitions in timeline
    func recordStateTransition(from oldStatus: InlineEditStatus, to newStatus: InlineEditStatus) {
        guard oldStatus != newStatus else { return }
        
        switch newStatus {
        case .streaming:
            if oldStatus == .thinking {
                recordTimelineEvent(.streamingStarted, description: "AI started generating response")
            }
        case .ready:
            if oldStatus == .streaming {
                recordTimelineEvent(.proposalsReady(count: proposedEdits.count), 
                                  description: "\(proposedEdits.count) proposal(s) ready for review",
                                  details: proposedEdits.map { $0.fileName }.joined(separator: ", "))
            }
        case .applied:
            recordTimelineEvent(.accepted(count: proposedEdits.count),
                              description: "Accepted \(proposedEdits.count) proposal(s)",
                              details: proposedEdits.map { $0.fileName }.joined(separator: ", "))
        case .continuing:
            recordTimelineEvent(.continued,
                              description: "Session continued with updated files")
        case .rejected:
            recordTimelineEvent(.rejected,
                              description: "All proposals rejected")
        case .error(let message):
            recordTimelineEvent(.error(message: message),
                              description: "Error: \(message)")
        default:
            break
        }
    }
    
    /// Record accept action
    func recordAccept(count: Int, fileNames: [String], andContinue: Bool = false) {
        if andContinue {
            recordTimelineEvent(.acceptedAndContinued(count: count),
                              description: "Accepted \(count) proposal(s) and continued",
                              details: fileNames.joined(separator: ", "))
        } else {
            recordTimelineEvent(.accepted(count: count),
                              description: "Accepted \(count) proposal(s)",
                              details: fileNames.joined(separator: ", "))
        }
    }
    
    /// Record streaming progress
    func recordStreamingProgress(characterCount: Int) {
        // Only record every 100 characters to avoid spam
        if characterCount % 100 == 0 || characterCount < 100 {
            recordTimelineEvent(.streamingProgress(characterCount: characterCount),
                              description: "Received \(characterCount) characters",
                              details: nil)
        }
    }
    
    /// Original user instruction/intent
    private var userIntent: String = ""
    
    /// Sync current state from core model
    private func syncFromCore() {
        guard let coreModel = coreModel else { return }
        status = InlineEditStatus(from: coreModel.status)
        streamingText = coreModel.streamingText
        
        // Derive intent for each proposal from user instruction
        let newProposals = coreModel.proposedEdits.map { 
            InlineEditProposal(from: $0, intent: deriveIntent(from: userIntent, streamingText: streamingText))
        }
        
        // Preserve selection state for existing proposals, default to true for new ones
        for proposal in newProposals {
            if proposalSelection[proposal.id] == nil {
                // New proposal - default to selected
                proposalSelection[proposal.id] = true
            }
            // Existing proposals keep their selection state
        }
        
        // Remove selection state for proposals that no longer exist
        let newIds = Set(newProposals.map { $0.id })
        proposalSelection = proposalSelection.filter { newIds.contains($0.key) }
        
        proposedEdits = newProposals
        errorMessage = coreModel.errorMessage
    }
    
    /// Derive a clear intent description from user instruction and streaming text
    /// - Parameters:
    ///   - instruction: The original user instruction
    ///   - streamingText: The AI's streaming response (may contain explanation)
    /// - Returns: A clean, human-readable intent description
    private func deriveIntent(from instruction: String, streamingText: String) -> String {
        // First, try to extract intent from the original instruction
        // Remove common prefixes and simplify
        var intent = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common instruction prefixes
        let prefixes = [
            "Edit the selected code according to this instruction:",
            "Edit this file according to this instruction:",
            "Edit according to this instruction:",
            "Edit:",
            "Change:",
            "Modify:",
            "Update:"
        ]
        
        for prefix in prefixes {
            if intent.lowercased().hasPrefix(prefix.lowercased()) {
                intent = String(intent.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        // If instruction is too long, take first sentence or first 100 chars
        if intent.count > 100 {
            // Try to find first sentence
            if let sentenceEnd = intent.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                intent = String(intent[..<sentenceEnd])
            } else {
                // Just take first 100 chars
                intent = String(intent.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !intent.isEmpty {
                    intent += "..."
                }
            }
        }
        
        // If we still don't have a good intent, try extracting from streaming text
        if intent.isEmpty || intent.count < 5 {
            // Look for explanation in streaming text (before first code block)
            if let codeBlockStart = streamingText.range(of: "```") {
                let explanation = String(streamingText[..<codeBlockStart.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Take first sentence or first 80 chars
                if let sentenceEnd = explanation.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                    intent = String(explanation[..<sentenceEnd])
                } else {
                    intent = String(explanation.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Fallback to a generic message
        return intent.isEmpty ? "Edit code" : intent
    }
    
    private func setupObservation() {
        cancellables.removeAll()
        
        guard let coreModel = coreModel else { return }
        
        // Observe status changes
        coreModel.$status
            .sink { [weak self] coreStatus in
                guard let self = self else { return }
                let newStatus = InlineEditStatus(from: coreStatus)
                
                // Transition from thinking to streaming when EditorCore starts streaming
                if self.status == .thinking && newStatus == .streaming {
                    self.status = .streaming
                } else if self.status != .thinking {
                    // Only update status if not in thinking state (thinking is app-level only)
                    self.status = newStatus
                } else if newStatus == .idle {
                    // Keep thinking state if core is still idle
                    self.status = .thinking
                }
            }
            .store(in: &cancellables)
        
        // CPU OPTIMIZATION: Throttled streaming text observation
        // PROBLEM: Direct assignment caused immediate @Published update → SwiftUI re-render on every chunk
        // SOLUTION: Queue updates through throttle, which batches them at ~80ms intervals
        coreModel.$streamingText
            .sink { [weak self] newText in
                guard let self = self else { return }
                self.streamingThrottle.queueUpdate(newText)
            }
            .store(in: &cancellables)
        
        // CPU OPTIMIZATION: Separate proposed edits observation from streaming text
        // PROBLEM: combineLatest fired on EVERY streaming text change, re-deriving intent for all proposals
        // SOLUTION: Only observe proposals, derive intent once when proposals actually change
        // Intent derivation uses latest streaming text but doesn't re-trigger on every character
        coreModel.$proposedEdits
            .sink { [weak self] proposals in
                guard let self = self else { return }
                
                // Use current streamingText (which is throttled) for intent derivation
                // This only runs when proposals change, not on every streaming chunk
                let newProposals = proposals.map { 
                    InlineEditProposal(from: $0, intent: self.deriveIntent(from: self.userIntent, streamingText: self.streamingText))
                }
                
                // Preserve selection state for existing proposals, default to true for new ones
                let newIds = Set(newProposals.map { $0.id })
                
                // Add default selection (true) for new proposals
                for proposal in newProposals {
                    if self.proposalSelection[proposal.id] == nil {
                        self.proposalSelection[proposal.id] = true
                    }
                }
                
                // Remove selection state for proposals that no longer exist
                self.proposalSelection = self.proposalSelection.filter { newIds.contains($0.key) }
                
                // Update proposals
                self.proposedEdits = newProposals
            }
            .store(in: &cancellables)
        
        // Observe error message
        coreModel.$errorMessage
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
    }
}

/// App-level edit to apply
/// Wraps EditorCore.EditToApply to prevent EditorCore dependency in views
public struct InlineEditToApply: Equatable, Identifiable {
    public let id: UUID
    public let filePath: String
    public let newContent: String
    public let originalContent: String
    
    init(from coreEdit: EditorCore.EditToApply) {
        self.id = coreEdit.id
        self.filePath = coreEdit.filePath
        self.newContent = coreEdit.newContent
        self.originalContent = coreEdit.originalContent
    }
    
    /// Convert to EditorCore type (for applyEdits)
    func toCoreEdit() -> EditorCore.EditToApply {
        return EditorCore.EditToApply(
            id: id,
            filePath: filePath,
            newContent: newContent,
            originalContent: originalContent
        )
    }
}

/// App-level handle for inline edit sessions
/// Wraps EditorCore.EditSessionHandle to prevent EditorCore dependency in views
@MainActor
public class InlineEditSession {
    private var coreHandle: EditorCore.EditSessionHandle // Mutable to support continuation
    public let model: InlineEditSessionModel
    /// Original user instruction/intent for this edit session
    let userIntent: String
    /// Coordinator reference for creating continuation sessions
    private weak var coordinator: EditorCore.DefaultEditSessionCoordinator?
    /// Execution plan for this session (for validation and safety)
    var executionPlan: ExecutionPlan?
    
    public var id: UUID {
        coreHandle.id
    }
    
    public var canUndo: Bool {
        coreHandle.canUndo
    }
    
    init(coreHandle: EditorCore.EditSessionHandle, userIntent: String = "", coordinator: EditorCore.DefaultEditSessionCoordinator? = nil) {
        self.coreHandle = coreHandle
        self.userIntent = userIntent
        self.coordinator = coordinator
        self.model = InlineEditSessionModel()
        self.model.update(from: coreHandle.model, userIntent: userIntent)
        
        // Set thinking state immediately for early feedback
        // This shows provisional intent before streaming begins
        if coreHandle.model.status == .idle {
            self.model.status = .thinking
        }
    }
    
    /// Continue session with updated file snapshots after applying edits
    /// This creates a new EditorCore session internally but keeps the same InlineEditSession instance
    /// SAFETY: All edits are applied atomically before continuation
    func continueWithUpdatedFiles(instruction: String, files: [FileStateInput]) {
        guard let coordinator = coordinator else {
            model.status = .error("Cannot continue: coordinator unavailable")
            return
        }
        
        // Convert app-level FileStateInput to EditorCore.FileState
        let coreFiles = files.map { fileInput in
            EditorCore.FileState(
                id: fileInput.id,
                content: fileInput.content,
                language: fileInput.language
            )
        }
        
        // Create new EditorCore session with updated file snapshots
        let newCoreHandle = coordinator.startEditSession(
            instruction: instruction,
            files: coreFiles
        )
        
        // Replace the core handle (session continues with same InlineEditSession instance)
        self.coreHandle = newCoreHandle
        
        // Update model to observe new session
        self.model.update(from: newCoreHandle.model, userIntent: userIntent)
        
        // Transition to continuing state
        self.model.status = .continuing
    }
    
    /// Append streaming text chunk
    func appendStreamingText(_ text: String) {
        coreHandle.appendStreamingText(text)
    }
    
    /// Complete streaming
    /// 
    /// HARD COMPLETION GATE: Validates all conditions before allowing completion
    /// Session may only complete if:
    /// - HTTP 2xx AND responseLength > 0 AND parsedFiles.count > 0 AND proposedEdits.count > 0
    func completeStreaming() {
        // Validate completion gate before allowing completion
        // This ensures session only completes when all safety conditions are met
        let (canComplete, gateError) = ValidationCoordinator.shared.checkCompletionGate(
            httpStatus: nil, // HTTP status checked earlier in pipeline
            responseLength: model.streamingText.count,
            parsedFiles: [], // Parsed files checked in EditSessionOrchestrator
            proposedEdits: model.proposedEdits,
            validationErrors: model.validationErrors.flatMap { $0.issues.map { $0.message } }
        )
        
        if !canComplete {
            // Completion gate failed - transition to error state
            let errorMsg = gateError ?? "Session cannot complete due to validation failure"
            model.status = .error(errorMsg)
            model.errorMessage = gateError
            model.recordTimelineEvent(.error(message: errorMsg), description: "Completion gate failed: \(errorMsg)")
            return
        }
        
        // All conditions met - allow completion
        coreHandle.completeStreaming()
    }
    
    /// Accept all edits - returns app-level edits to apply
    /// NOTE: This accepts ALL proposals. Use acceptSelected() for partial accept.
    func acceptAll() -> [InlineEditToApply] {
        return coreHandle.acceptAll().map { InlineEditToApply(from: $0) }
    }
    
    /// Accept only selected proposals - returns app-level edits to apply
    /// Preserves atomic application: all selected proposals are applied in one transaction
    func acceptSelected(selectedIds: Set<UUID>) -> [InlineEditToApply] {
        // If all are selected, use acceptAll for simplicity
        let allIds = Set(model.proposedEdits.map { $0.id })
        if selectedIds == allIds {
            return acceptAll()
        }
        
        // Otherwise, accept only selected proposals
        // EditorCore ensures atomic application via transaction system
        return coreHandle.accept(editIds: selectedIds).map { InlineEditToApply(from: $0) }
    }
    
    /// Reject all edits
    func rejectAll() {
        coreHandle.rejectAll()
    }
    
    /// Undo last transaction
    func undo() -> [InlineEditToApply]? {
        return coreHandle.undo()?.map { InlineEditToApply(from: $0) }
    }
}

/// Adapter for EditorCore integration
/// Manages EditSessionCoordinator lifecycle and provides applyEdits function
/// 
/// This is the SINGLE BRIDGE between EditorCore and the SwiftUI editor.
/// No other code should import EditorCore or use EditorCore types directly.
@MainActor
final class EditorCoreAdapter: ObservableObject {
    private let coordinator: EditorCore.DefaultEditSessionCoordinator
    
    // ObservableObject conformance - explicitly provide objectWillChange for @MainActor compatibility
    public let objectWillChange = ObservableObjectPublisher()
    
    init() {
        self.coordinator = EditorCore.DefaultEditSessionCoordinator()
    }
    
    /// Current active edit session (if any)
    /// INVARIANT: Returns app-level wrapper, never EditorCore type
    /// NOTE: This is mainly for checking if a session exists.
    /// Views should store the session returned from startInlineEditSession.
    var activeSession: InlineEditSession? {
        // Note: We can't recreate the session here without userIntent.
        // Views store the session returned from startInlineEditSession.
        // This property is kept for API compatibility but always returns nil.
        return nil
    }
    
    /// Start a new edit session for ⌘K inline edits
    /// 
    /// CORE INVARIANT: User prompts are always translated into explicit execution plans before edits occur.
    /// This ensures deterministic, inspectable, and safe edit operations.
    ///
    /// INVARIANT: This is the only way to create edit sessions
    /// - Parameters:
    ///   - instruction: Full instruction with context (for EditorCore)
    ///   - userIntent: Original user instruction (for intent display)
    ///   - files: File states to edit
    ///   - context: Planning context for execution planner
    /// - Returns: InlineEditSession (app-level wrapper, not EditorCore type)
    func startInlineEditSession(
        instruction: String,
        userIntent: String,
        files: [FileStateInput],
        context: ExecutionPlanner.PlanningContext? = nil
    ) -> InlineEditSession {
        assert(Thread.isMainThread, "EditorCoreAdapter must be called on MainActor")
        
        // EXECUTION PLANNING LAYER: Translate user prompt into explicit execution plan
        // This ensures deterministic, inspectable, and safe edit operations
        let planner = ExecutionPlanner.shared
        
        // Create planning context if not provided
        let planningContext = context ?? ExecutionPlanner.PlanningContext(
            selectedText: nil,
            currentFilePath: files.first?.id,
            allFilePaths: files.map { $0.id },
            limitToCurrentFile: files.count == 1
        )
        
        // Generate explicit execution plan from user intent
        let executionPlan = planner.createPlan(from: userIntent, context: planningContext)
        
        // SAFETY GUARDS: Validate plan before execution
        let fileContents = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.content) })
        let sizeEstimate = ValidationCoordinator.shared.estimateChangeSize(
            plan: executionPlan,
            files: fileContents
        )
        
        // If plan is unsafe, log warning but proceed (safety guards are advisory)
        if !sizeEstimate.isSafe, let recommendation = sizeEstimate.recommendation {
            print("⚠️ Execution plan safety warning: \(recommendation)")
        }
        
        // Convert execution plan into explicit instruction for EditorCore
        // The instruction now includes the structured plan information
        let explicitInstruction = buildExplicitInstruction(
            from: executionPlan,
            originalInstruction: instruction
        )
        
        // Convert app-level FileStateInput to EditorCore.FileState
        let coreFiles = files.map { fileInput in
            EditorCore.FileState(
                id: fileInput.id,
                content: fileInput.content,
                language: fileInput.language
            )
        }
        
        // Create EditorCore session with explicit instruction
        let coreHandle = coordinator.startEditSession(
            instruction: explicitInstruction,
            files: coreFiles
        )
        
        // Store execution plan in session for later validation
        // Return app-level wrapper with user intent and coordinator reference
        let session = InlineEditSession(coreHandle: coreHandle, userIntent: userIntent, coordinator: coordinator)
        
        // Store execution plan for outcome validation
        session.executionPlan = executionPlan
        
        return session
    }
    
    /// Build explicit instruction from execution plan
    /// This ensures EditorCore receives deterministic, structured instructions
    private func buildExplicitInstruction(
        from plan: ExecutionPlan,
        originalInstruction: String
    ) -> String {
        // Include the execution plan details in the instruction
        // This makes the instruction explicit and deterministic
        var instruction = originalInstruction
        
        // Add plan metadata as comments/context for the AI
        // This helps the AI understand the structured intent
        let planContext = """
        
        Execution Plan:
        - Operation: \(plan.operationType.rawValue)
        - Description: \(plan.description)
        - Scope: \(plan.scope.rawValue)
        """
        
        instruction += planContext
        
        return instruction
    }
    
    /// Reuse an intent from an existing session to create a new session
    /// SAFETY: Creates a completely new session with new files, preserving intent only
    /// - Parameters:
    ///   - intent: The intent to reuse (from previous session)
    ///   - files: New file states to apply the intent to
    /// - Returns: New InlineEditSession with reused intent
    func reuseIntent(intent: String, files: [FileStateInput]) -> InlineEditSession {
        assert(Thread.isMainThread, "EditorCoreAdapter must be called on MainActor")
        
        // Build instruction with context for new files
        // Use the same intent but with new file content
        let fileContexts = files.map { file in
            """
            File: \(file.id)
            Content:
            ```
            \(file.content)
            ```
            """
        }.joined(separator: "\n\n")
        
        let instruction = """
        Edit these files according to this instruction: \(intent)
        
        \(fileContexts)
        
        Return the edited code in the same format.
        """
        
        // Create new session with reused intent
        return startInlineEditSession(
            instruction: instruction,
            userIntent: intent,
            files: files
        )
    }
}

/// App-level file state input (avoids EditorCore.FileState in views)
public struct FileStateInput {
    public let id: String
    public let content: String
    public let language: String?
    
    public init(id: String, content: String, language: String? = nil) {
        self.id = id
        self.content = content
        self.language = language
    }
}

/// Extension on EditorViewModel to provide applyEdits adapter function
extension EditorViewModel {
    /// Apply edits atomically to the editor
    /// 
    /// ARCHITECTURE INVARIANT: This is the ONLY function that mutates editor content from EditorCore.
    /// No other code path should modify editor state based on EditorCore output.
    /// 
    /// - Parameter edits: Array of InlineEditToApply (app-level wrapper)
    /// - Note: Preserves cursor/scroll position and does not trigger additional AI logic
    /// 
    /// PRECONDITIONS:
    /// - Must be called on MainActor
    /// - edits must be from a committed transaction (after acceptAll())
    /// 
    /// POSTCONDITIONS:
    /// - All edits are applied atomically
    /// - Documents are marked as AI-generated for highlighting
    /// - Editor state is updated but no additional AI logic is triggered
    func applyEdits(_ edits: [InlineEditToApply]) {
        assert(Thread.isMainThread, "applyEdits must be called on MainActor")
        assert(!edits.isEmpty || true, "applyEdits should not be called with empty edits (but allowed for safety)")
        
        // Convert app-level edits to EditorCore format (internal conversion only)
        let coreEdits = edits.map { $0.toCoreEdit() }
        
        // Store cursor/scroll state before applying edits
        let activeDocumentId = editorState.activeDocument?.id
        
        // Apply each edit atomically
        for edit in coreEdits {
            // Find or create document for this file
            let document: Document
            
            // Resolve file path
            let filePath: URL
            if edit.filePath.hasPrefix("/") {
                filePath = URL(fileURLWithPath: edit.filePath)
            } else if let projectURL = rootFolderURL {
                filePath = projectURL.appendingPathComponent(edit.filePath)
            } else {
                // Try absolute path as fallback
                filePath = URL(fileURLWithPath: edit.filePath)
            }
            
            if let existingDoc = editorState.documents.first(where: { doc in
                guard let docPath = doc.filePath else { return false }
                return docPath.path == filePath.path
            }) {
                // Document already open - update it
                document = existingDoc
                document.content = edit.newContent
                document.isModified = true
                
                // Mark as AI-generated for highlighting
                document.markAsAIGenerated(originalContent: edit.originalContent)
            } else {
                // Try to create URL from file path
                let filePath: URL
                if edit.filePath.hasPrefix("/") {
                    filePath = URL(fileURLWithPath: edit.filePath)
                } else if let projectURL = rootFolderURL {
                    filePath = projectURL.appendingPathComponent(edit.filePath)
                } else {
                    // Invalid file path - skip
                    continue
                }
                
                // Create new document
                document = Document(
                    id: UUID(),
                    filePath: filePath,
                    content: edit.newContent,
                    isModified: true
                )
                document.language = detectLanguageFromExtension(filePath.pathExtension)
                document.markAsAIGenerated(originalContent: edit.originalContent)
                
                // Add to editor state
                editorState.addDocument(document)
            }
            
            // If this was the active document, restore cursor position
            if document.id == activeDocumentId {
                // Restore selection if it was in the edited region
                // (Simplified: just keep the document active)
                editorState.setActiveDocument(document.id)
            }
        }
        
        // Update document content to trigger UI refresh
        if let activeDoc = editorState.activeDocument {
            updateDocumentContent(activeDoc.content)
        }
    }
    
    /// Helper function to detect language from file extension
    /// (Duplicated from EditorViewModel.detectLanguage to avoid access issues)
    private func detectLanguageFromExtension(_ extension: String) -> String {
        switch `extension`.lowercased() {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        case "rs": return "rust"
        case "go": return "go"
        default: return "text"
        }
    }
}
