//
//  ToolCallProgress.swift
//  LingCode
//
//  Progress indicators for tool calls
//

import Foundation
import SwiftUI

/// Represents a tool call in progress
struct ToolCallProgress: Identifiable {
    let id: String
    let toolName: String
    let status: ToolCallStatus
    let message: String
    let startTime: Date
    
    enum ToolCallStatus {
        case pending
        case executing
        case completed
        case failed
        case approved
        case rejected
    }
    
    var icon: String {
        switch status {
        case .pending: return "clock"
        case .executing: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .approved: return "checkmark.shield.fill"
        case .rejected: return "xmark.shield.fill"
        }
    }
    
    var color: Color {
        switch status {
        case .pending: return .orange
        case .executing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .approved: return .green
        case .rejected: return .red
        }
    }
    
    var displayMessage: String {
        switch toolName {
        case "codebase_search":
            return "🔍 Searching codebase..."
        case "read_file":
            return "📖 Reading file..."
        case "write_file":
            return "✏️ Writing file..."
        case "run_terminal_command":
            return "⚡ Running command..."
        case "search_web":
            return "🌐 Searching web..."
        case "read_directory":
            return "📁 Reading directory..."
        default:
            return "🔧 Executing \(toolName)..."
        }
    }
}

/// Tool permission settings
struct ToolPermission: Identifiable {
    let id: String
    let toolName: String
    var requiresApproval: Bool
    var autoApprove: Bool
    
    static let defaultPermissions: [ToolPermission] = [
        ToolPermission(id: "read_file", toolName: "read_file", requiresApproval: false, autoApprove: true),
        ToolPermission(id: "codebase_search", toolName: "codebase_search", requiresApproval: false, autoApprove: true),
        ToolPermission(id: "read_directory", toolName: "read_directory", requiresApproval: false, autoApprove: true),
        ToolPermission(id: "write_file", toolName: "write_file", requiresApproval: true, autoApprove: false),
        ToolPermission(id: "run_terminal_command", toolName: "run_terminal_command", requiresApproval: true, autoApprove: false),
        ToolPermission(id: "search_web", toolName: "search_web", requiresApproval: false, autoApprove: true)
    ]
}
