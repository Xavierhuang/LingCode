//
//  TestHelpers.swift
//  EditorCoreTests
//
//  Test helpers for deterministic testing
//

import Foundation
import XCTest
@testable import EditorCore

/// Helper to wait for status changes deterministically
extension EditSessionHandle {
    /// Wait for status to reach target (synchronous polling on main thread)
    func waitForStatus(_ target: EditSessionStatus, timeout: TimeInterval = 0.5) -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if model.status == target {
                return true
            }
            // Run main thread runloop briefly
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return false
    }
    
    /// Wait for status to be ready
    func waitForReady(timeout: TimeInterval = 0.5) -> Bool {
        return waitForStatus(.ready, timeout: timeout)
    }
}

/// Helper to collect status updates
class StatusCollector {
    private(set) var statuses: [EditSessionStatus] = []
    
    func collect(from model: EditSessionModel) {
        statuses.append(model.status)
    }
    
    func clear() {
        statuses.removeAll()
    }
}
