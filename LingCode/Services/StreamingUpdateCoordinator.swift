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
    @Published private(set) var throttledStreamingText: String = ""
    
    /// Parsed files (only updated when parsing produces new/changed results)
    @Published var parsedFiles: [StreamingFileInfo] = []
    
    /// Parsed commands (only updated when parsing produces new/changed results)
    @Published var parsedCommands: [ParsedCommand] = []
    
    /// Tick counter - increments on each throttled update (for scroll triggers)
    @Published private(set) var updateTick: Int = 0
    
    // MARK: - Private State
    
    /// Raw streaming text (accumulated at full speed, no throttling)
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
        
        // Schedule throttled update if needed
        scheduleThrottledUpdate()
    }
    
    /// Force immediate update (e.g., when streaming completes)
    func flushUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
        performThrottledUpdate()
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
            performThrottledUpdate()
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
        guard contentHash != lastParsedContentHash else { return }
        
        // Get context for parsing
        guard let context = getContext?() else { return }
        
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
            
            // ARCHITECTURE: Use EditIntentCoordinator for all parsing/validation
            // This ensures state mutations happen asynchronously AFTER view updates
            // Note: httpStatus is not available in streaming context, will be checked at completion
            let editResult = await editIntentCoordinator.parseAndValidate(
                content: content,
                userPrompt: userPrompt,
                isLoading: isLoading,
                projectURL: projectURL,
                actions: actions,
                httpStatus: nil // Will be validated at completion gate
            )
            
            // Update MainActor state asynchronously (AFTER view updates)
            await MainActor.run {
                self.isParsing = false
                
                // Handle validation errors
                if !editResult.isValid, let errorMessage = editResult.errorMessage {
                    // SURFACE ERROR: Show validation error to user
                    self.onValidationError?(errorMessage)
                    
                    // Don't update parsed files if validation failed
                    // This prevents unsafe edits from being shown
                    return
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
