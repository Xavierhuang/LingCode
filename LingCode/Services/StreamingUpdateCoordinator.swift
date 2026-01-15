//
//  StreamingUpdateCoordinator.swift
//  LingCode
//
//  CPU Optimization: Coordinates streaming text updates, parsing, and UI updates
//  Prevents 100% CPU usage during AI streaming by throttling expensive operations
//

import Foundation
import Combine

/// Coordinates streaming text updates, parsing, and UI state updates
///
/// PROBLEM: Without coordination, every token/character chunk triggers:
/// - Immediate @Published property updates → SwiftUI re-renders
/// - Parsing on every character → 100% CPU usage
/// - Multiple onChange handlers → re-entrant update loops
/// - Auto-scroll on every character → excessive layout calculations
///
/// SOLUTION: Single coordinator that:
/// - Accepts streaming text at full speed (no blocking)
/// - Throttles updates to ~80-120ms intervals
/// - Ensures parsing happens at most once per tick
/// - Only updates MainActor state when parsed output meaningfully changes
/// - Provides single source of truth for scroll triggers
@MainActor
final class StreamingUpdateCoordinator: ObservableObject {
    // MARK: - Published Properties
    
    /// Throttled streaming text for display (updates at ~80-120ms intervals)
    /// ARCHITECTURE: This is the displayed buffer, separate from rawStreamingText
    /// PROBLEM 1 FIX: Separating streaming buffer from displayed buffer preserves user selection
    /// Streaming updates do NOT reset user selection because we only update when content meaningfully changes
    @Published private(set) var throttledStreamingText: String = ""
    
    /// Parsed files (only updated when parsing produces new/changed results)
    /// ARCHITECTURE: Only validated, executable output is shown to users
    /// PROBLEM 2 FIX: Raw streaming text is never displayed - only parsed, validated files are shown
    @Published var parsedFiles: [StreamingFileInfo] = []
    
    /// Parsed commands (only updated when parsing produces new/changed results)
    @Published var parsedCommands: [ParsedCommand] = []
    
    /// Tick counter - increments on each throttled update (for scroll triggers)
    @Published private(set) var updateTick: Int = 0
    
    /// Agent Mode state (explicit state to prevent blank UI)
    @Published private(set) var agentState: AgentState = .idle
    
    // MARK: - Private State
    
    /// Raw streaming text (accumulated at full speed, no throttling)
    /// ARCHITECTURE: Internal buffer - never displayed directly to users
    /// PROBLEM 2 FIX: Raw streams are buffered internally but never rendered
    /// This prevents users from seeing internal reasoning, thinking, or raw tokens
    private var rawStreamingText: String = ""
    
    /// Last throttled update time
    private var lastUpdateTime: Date = .distantPast
    
    /// Throttle interval (80-120ms range, using 100ms as default)
    private let throttleInterval: TimeInterval = 0.1 // 100ms
    
    /// Timer for scheduled updates
    private var updateTimer: Timer?
    
    /// Last parsed content hash (to detect meaningful changes)
    private var lastParsedContentHash: Int = 0
    
    /// Whether parsing is currently in progress (prevents re-entrant parsing)
    private var isParsing: Bool = false
    
    /// Pending parse task (cancelled if new text arrives)
    private var pendingParseTask: Task<Void, Never>?

    /// Force a parse on the next throttled update (used when streaming completes).
    /// Fixes a hang where `lastParsedContentHash` is already up-to-date from streaming, so
    /// transitioning to `.validating` would not trigger parsing, leaving UI stuck on "Validating...".
    private var forceParseOnNextUpdate: Bool = false
    
    // MARK: - Dependencies
    
    private let contentParser = StreamingContentParser.shared
    private let terminalService = TerminalExecutionService.shared
    private let editIntentCoordinator = EditIntentCoordinator.shared
    
    // MARK: - Callbacks
    
    /// Called when coordinator needs context for parsing
    var getContext: (() -> (isLoading: Bool, projectURL: URL?, actions: [AIAction], userPrompt: String?))?
    
    /// Called when files should be auto-expanded (e.g., when they start streaming)
    var onFilesUpdated: (([StreamingFileInfo]) -> Void)?
    
    /// Called when validation errors occur
    var onValidationError: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Coordinator is ready to receive updates
    }
    
    // MARK: - Public Interface
    
    /// Accept streaming text update (called at full speed, no blocking)
    /// This method is safe to call from any thread
    func updateStreamingText(_ text: String) {
        // Update raw text immediately (no throttling here - we want to capture all text)
        rawStreamingText = text
        
        // AGENT STATE: Set to streaming while receiving chunks
        Task { @MainActor in
            await Task.yield()
            // IMPORTANT: A new request must always leave terminal states (.empty/.blocked/.ready)
            // and re-enter the streaming pipeline. Otherwise, parsing may never run again.
            agentState = .streaming
        }
        
        // Schedule throttled update if needed
        scheduleThrottledUpdate()
    }
    
    /// Force immediate update (e.g., when streaming completes)
    func flushUpdates(forceParse: Bool = false) {
        updateTimer?.invalidate()
        updateTimer = nil

        // Force at least one parse pass after streaming completes.
        // This guarantees `.validating` is transient and always resolves to a terminal state.
        forceParseOnNextUpdate = true

        // AGENT STATE: Transition to validating when streaming completes.
        // Defer to avoid "Publishing changes from within view updates".
        Task { @MainActor in
            await Task.yield()
            // IMPORTANT: Validation must run regardless of the previous state.
            // If we only transition from .streaming, a prior terminal state can prevent validation.
            self.agentState = .validating
            self.performThrottledUpdate()
        }
    }
    
    /// Reset coordinator state (e.g., when starting new conversation)
    func reset() {
        rawStreamingText = ""
        throttledStreamingText = ""
        parsedFiles = []
        parsedCommands = []
        lastParsedContentHash = 0
        isParsing = false
        pendingParseTask?.cancel()
        pendingParseTask = nil
        updateTimer?.invalidate()
        updateTimer = nil
        updateTick = 0
        agentState = .idle
        editIntentCoordinator.reset()
    }
    
    /// Safe state update methods (ARCHITECTURE: Views should use these instead of direct mutation)
    
    /// Remove a file from parsed files (safe state update)
    func removeFile(_ fileId: String) {
        // ARCHITECTURE: State updates happen asynchronously AFTER view updates
        Task { @MainActor in
            self.parsedFiles.removeAll { $0.id == fileId }
        }
    }
    
    /// Clear all parsed files (safe state update)
    func clearAllFiles() {
        // ARCHITECTURE: State updates happen asynchronously AFTER view updates
        Task { @MainActor in
            self.parsedFiles = []
            self.parsedCommands = []
        }
    }
    
    /// Update files (safe state update, used for final state)
    func updateFiles(_ files: [StreamingFileInfo]) {
        // ARCHITECTURE: State updates happen asynchronously AFTER view updates
        Task { @MainActor in
            self.parsedFiles = files
        }
    }
    
    // MARK: - Private Implementation
    
    /// Schedule a throttled update (if enough time has passed, update immediately)
    private func scheduleThrottledUpdate() {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        // If enough time has passed, update immediately
        if timeSinceLastUpdate >= throttleInterval {
            // Defer to avoid publishing during SwiftUI view updates (e.g. from .onChange).
            Task { @MainActor in
                await Task.yield()
                self.performThrottledUpdate()
            }
        } else {
            // Schedule update for when throttle interval expires
            scheduleDelayedUpdate()
        }
    }
    
    /// Schedule a delayed update (when throttle interval hasn't expired yet)
    private func scheduleDelayedUpdate() {
        // Cancel existing timer
        updateTimer?.invalidate()
        
        // Schedule new timer
        let delay = throttleInterval - Date().timeIntervalSince(lastUpdateTime)
        updateTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performThrottledUpdate()
            }
        }
    }
    
    /// Perform throttled update (updates UI and triggers parsing)
    private func performThrottledUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Update throttled streaming text for display
        throttledStreamingText = rawStreamingText
        lastUpdateTime = Date()
        updateTick += 1
        
        // Trigger parsing (will be throttled internally to prevent re-entrant calls)
        triggerParsingIfNeeded()
    }
    
    /// Trigger parsing if content has changed meaningfully
    /// Ensures parsing happens at most once per tick
    private func triggerParsingIfNeeded() {
        // Prevent re-entrant parsing
        guard !isParsing else { return }
        
        // Check if content has changed meaningfully
        let contentHash = rawStreamingText.hashValue
        if !forceParseOnNextUpdate {
            guard contentHash != lastParsedContentHash else { return }
        }
        
        // Get context for parsing
        guard let context = getContext?() else { return }

        // Clear force flag only once we know we'll actually schedule a parse.
        forceParseOnNextUpdate = false
        
        // Cancel any pending parse task
        pendingParseTask?.cancel()
        
        // Mark as parsing
        isParsing = true
        lastParsedContentHash = contentHash
        
        // Parse and validate using EditIntentCoordinator (ARCHITECTURE: All parsing/validation outside views)
        pendingParseTask = Task(priority: .userInitiated) {
            // Capture context values
            let isLoading = context.isLoading
            let projectURL = context.projectURL
            let actions = context.actions
            let content = rawStreamingText
            let userPrompt = context.userPrompt ?? ""
            
            // AGENT STATE: Only parse in validating state (after streaming completes)
            // Do NOT parse during streaming/blocked/empty states
            // Check agentState on MainActor since we're in a Task
            let shouldParse = await MainActor.run {
                agentState == .validating || agentState == .ready(edits: [])
            }
            
            guard shouldParse else {
                await MainActor.run {
                    self.isParsing = false
                    // SAFETY: If we're not parsing but still in .validating, exit to terminal state
                    if case .validating = self.agentState {
                        self.agentState = .empty
                    }
                }
                return
            }
            
            // ARCHITECTURE: Use EditIntentCoordinator for all parsing/validation
            // This ensures state mutations happen asynchronously AFTER view updates
            // Note: httpStatus is not available in streaming context, will be checked at completion
            let editResult = await editIntentCoordinator.parseAndValidate(
                content: content,
                userPrompt: userPrompt,
                isLoading: isLoading,
                projectURL: projectURL,
                actions: actions,
                httpStatus: await MainActor.run { AIService.shared.lastHTTPStatusCode } // Completion gate requires real HTTP status
            )
            
            // AGENT STATE: Update state based on validation result
            // REQUIREMENT: Validation MUST always resolve to a terminal state
            // Terminal states: .ready(edits), .empty, .blocked(reason)
            await MainActor.run {
                self.isParsing = false
                
                // Handle validation errors - ALWAYS set terminal state
                if !editResult.isValid {
                    let errorMessage = editResult.errorMessage ?? "Validation failed"
                    
                    // SURFACE ERROR: Show validation error to user
                    self.onValidationError?(errorMessage)
                    
                    // AGENT STATE: Set blocked or empty based on error type
                    // This ensures we ALWAYS exit .validating state
                    if errorMessage.contains("non-executable output") || errorMessage.contains("forbidden") {
                        self.agentState = .blocked(reason: errorMessage)
                    } else if errorMessage.contains("empty response") || errorMessage.contains("empty") {
                        self.agentState = .empty
                    } else if errorMessage.lowercased().contains("no files") || errorMessage.lowercased().contains("parsed") {
                        // Parse failure / no-op-like result: show as empty, not "blocked"
                        self.agentState = .empty
                    } else {
                        self.agentState = .blocked(reason: errorMessage)
                    }
                    
                    // Don't update parsed files if validation failed
                    // This prevents unsafe edits from being shown
                    return
                }
                
                // AGENT STATE: Update based on parse result
                // REQUIREMENT: Always set terminal state, never leave in .validating
                if editResult.files.isEmpty {
                    // No files parsed - terminal state: .empty
                    self.agentState = .empty
                } else {
                    // Files parsed successfully - terminal state: .ready
                    self.agentState = .ready(edits: editResult.files)
                }
                
                // SAFETY FALLBACK: Ensure we never stay in .validating
                // If for any reason agentState is still .validating, force to .empty
                if case .validating = self.agentState {
                    self.agentState = .empty
                }
                
                // Check if files actually changed before updating state
                let currentFileIds = Set(self.parsedFiles.map { $0.id })
                let newFileIds = Set(editResult.files.map { $0.id })
                
                // Check if commands changed
                let commandsChanged = self.parsedCommands.count != editResult.commands.count
                
                // PARSER ROBUSTNESS: Merge files to ensure complete blocks replace streaming blocks
                // Only update if output meaningfully changed
                if currentFileIds != newFileIds || commandsChanged {
                    // Merge files to prefer complete blocks over streaming blocks
                    let mergedFiles = ParserRobustnessGuard.shared.mergeFiles(
                        existingFiles: self.parsedFiles,
                        newFiles: editResult.files,
                        isLoading: isLoading
                    )
                    
                    // Update commands if changed
                    if !editResult.commands.isEmpty {
                        self.parsedCommands = editResult.commands
                    }
                    
                    // Update files with merged result (complete blocks preferred)
                    // Use safe state update method
                    self.updateFiles(mergedFiles)
                    
                    // LOGGING: Track file updates for debugging
                    print("📊 FILE UPDATE:")
                    print("   Files in context: \(isLoading ? "streaming" : "complete")")
                    print("   Files parsed: \(mergedFiles.count)")
                    print("   File names: \(mergedFiles.map { $0.name }.joined(separator: ", "))")
                    
                    // Notify that files were updated
                    self.onFilesUpdated?(mergedFiles)
                } else if !isLoading && !editResult.files.isEmpty {
                    // PARSER ROBUSTNESS: When streaming completes, ensure we have complete blocks
                    // Even if IDs didn't change, content might have (streaming -> complete)
                    let mergedFiles = ParserRobustnessGuard.shared.mergeFiles(
                        existingFiles: self.parsedFiles,
                        newFiles: editResult.files,
                        isLoading: false // Force complete blocks only
                    )
                    
                    // Update if merged result differs
                    if mergedFiles.count != self.parsedFiles.count ||
                       mergedFiles.contains(where: { file in
                           guard let existing = self.parsedFiles.first(where: { $0.id == file.id }) else { return true }
                           return file.content != existing.content || file.isStreaming != existing.isStreaming
                       }) {
                        self.updateFiles(mergedFiles)
                        print("📊 FILE UPDATE (completion): Replaced streaming blocks with complete blocks")
                        
                        // Notify that files were updated
                        self.onFilesUpdated?(mergedFiles)
                    }
                } else if self.parsedFiles.isEmpty {
                    // Only clear if we have no existing files AND no new files
                    self.parsedFiles = []
                }
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
        pendingParseTask?.cancel()
    }
}
