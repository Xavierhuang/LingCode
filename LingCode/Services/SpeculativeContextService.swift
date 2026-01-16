//
//  SpeculativeContextService.swift
//  LingCode
//
//  Created for Latency Optimization
//  Beats Cursor by preparing context BEFORE the user hits enter.
//

import Foundation
import Combine

class SpeculativeContextService: ObservableObject {
    static let shared = SpeculativeContextService()
    
    // The "Hot" context ready to be used instantly
    @Published var preparedContext: String?
    @Published var isPreparing: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let textSubject = PassthroughSubject<String, Never>()
    var lastQuery: String = "" // Made internal so AIViewModel can check if prepared context matches
    
    private init() {
        setupPipeline()
    }
    
    /// Call this whenever the user types in the chat box
    func onUserTyping(text: String) {
        textSubject.send(text)
    }
    
    /// Consumes the speculative context if ready, or waits for it
    func consumeContext(
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?,
        fallbackQuery: String
    ) async -> String {
        // 1. If we have a "hot" context that matches the query roughly, use it!
        if let readyContext = preparedContext, 
           lastQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == fallbackQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            print("🚀 Using Speculative Context (Saved ~500ms)")
            // Clear prepared context after use
            preparedContext = nil
            return readyContext
        }
        
        // 2. Cold start (User typed too fast), build it now
        print("❄️ Speculative miss - Building Cold Context")
        return ContextRankingService.shared.buildContext(
            activeFile: activeFile,
            selectedRange: selectedRange,
            diagnostics: diagnostics,
            projectURL: projectURL,
            query: fallbackQuery
        )
    }
    
    private func setupPipeline() {
        textSubject
            // 1. Debounce: Wait for user to pause typing for 300ms
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.global(qos: .userInitiated))
            .removeDuplicates()
            .filter { $0.count > 5 } // Don't speculate on "Hi"
            .sink { [weak self] query in
                self?.prepareContextInBackground(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func prepareContextInBackground(query: String) {
        // Get editor state from a shared instance or pass it in
        // For now, we'll use a simplified approach that gets editor state when needed
        // This will be called from the view model which has access to editor state
        
        // Store the query we're preparing for
        lastQuery = query
        
        DispatchQueue.main.async {
            self.isPreparing = true
        }
        
        // We need to get editor state - this will be called from AIViewModel which has editorViewModel
        // For now, we'll prepare a simplified context that can be enhanced later
        // The actual integration will happen in AIViewModel where we have access to editor state
        
        // Clear old context
        DispatchQueue.main.async {
            self.preparedContext = nil
        }
        
        // Note: Full context preparation requires editor state, which we'll handle in AIViewModel
        // This service just manages the pipeline and state
    }
    
    /// Prepare context with full editor state (called from AIViewModel)
    func prepareContext(
        query: String,
        activeFile: URL?,
        selectedRange: String?,
        diagnostics: [String]?,
        projectURL: URL?
    ) {
        lastQuery = query
        
        DispatchQueue.main.async {
            self.isPreparing = true
        }
        
        // Build context in background
        DispatchQueue.global(qos: .userInitiated).async {
            let context = ContextRankingService.shared.buildContext(
                activeFile: activeFile,
                selectedRange: selectedRange,
                diagnostics: diagnostics,
                projectURL: projectURL,
                query: query
            )
            
            DispatchQueue.main.async {
                self.preparedContext = context
                self.isPreparing = false
            }
        }
    }
    
    /// Clear prepared context (call when user sends message or changes focus)
    func clearPreparedContext() {
        preparedContext = nil
        lastQuery = ""
    }
}
