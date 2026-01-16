//
//  StreamingUpdateThrottle.swift
//  LingCode
//
//  CPU Optimization: Throttles streaming updates to ~60-100ms intervals
//  Prevents excessive MainActor updates and re-renders during AI streaming
//

import Foundation
import Combine

/// Throttles streaming text updates to reduce CPU usage
/// 
/// PROBLEM: Without throttling, every character chunk triggers:
/// - Multiple @Published property updates
/// - SwiftUI view re-renders
/// - Combine pipeline re-executions
/// - Intent derivation for all proposals
/// 
/// SOLUTION: Coalesce updates into a single pipeline that fires at most every 60-100ms
@MainActor
final class StreamingUpdateThrottle {
    private var pendingText: String = ""
    private var lastUpdateTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 0.08 // 80ms (between 60-100ms)
    private var updateTimer: Timer?
    private var updateHandler: ((String) -> Void)?
    
    /// Set the handler that will receive throttled updates
    func setUpdateHandler(_ handler: @escaping (String) -> Void) {
        self.updateHandler = handler
    }
    
    /// Queue a streaming text update (will be throttled)
    func queueUpdate(_ text: String) {
        pendingText = text
        
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        // If enough time has passed, update immediately
        if timeSinceLastUpdate >= throttleInterval {
            flushUpdate()
        } else {
            // Schedule update for when throttle interval expires
            scheduleDelayedUpdate()
        }
    }
    
    /// Force immediate update (e.g., when streaming completes)
    func flushUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        guard !pendingText.isEmpty else { return }
        
        let textToUpdate = pendingText
        pendingText = ""
        lastUpdateTime = Date()
        
        updateHandler?(textToUpdate)
    }
    
    private func scheduleDelayedUpdate() {
        // Cancel existing timer
        updateTimer?.invalidate()
        
        // Schedule new timer
        let delay = throttleInterval - Date().timeIntervalSince(lastUpdateTime)
        updateTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushUpdate()
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}
