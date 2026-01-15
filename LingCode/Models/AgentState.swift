//
//  AgentState.swift
//  LingCode
//
//  Explicit Agent Mode state enum to prevent blank UI deadlocks
//

import Foundation

/// Explicit Agent Mode state to prevent blank UI
enum AgentState: Equatable {
    case idle
    case streaming
    case validating
    case blocked(reason: String)
    case empty
    case ready(edits: [StreamingFileInfo])
}
