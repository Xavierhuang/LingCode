//
//  LoadingStateManager.swift
//  LingCode
//
//  Unified loading state management
//  Single source of truth for all loading indicators
//

import Foundation
import Combine
import SwiftUI

/// Represents what operation is currently in progress
enum LoadingOperation: Equatable {
    case idle
    case streaming(progress: Double?)
    case validating
    case applying(fileName: String?)
    case searching(query: String)
    case indexing
    case custom(message: String)
    
    var displayMessage: String {
        switch self {
        case .idle:
            return ""
        case .streaming(let progress):
            if let p = progress {
                return "Generating... \(Int(p * 100))%"
            }
            return "Generating..."
        case .validating:
            return "Validating..."
        case .applying(let fileName):
            if let name = fileName {
                return "Applying \(name)..."
            }
            return "Applying changes..."
        case .searching(let query):
            return "Searching: \(query)"
        case .indexing:
            return "Indexing codebase..."
        case .custom(let message):
            return message
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return ""
        case .streaming: return "sparkle"
        case .validating: return "shield.lefthalf.filled"
        case .applying: return "checkmark.circle"
        case .searching: return "magnifyingglass"
        case .indexing: return "folder.badge.gearshape"
        case .custom: return "gear"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .clear
        case .streaming: return .blue
        case .validating: return .orange
        case .applying: return .green
        case .searching: return .purple
        case .indexing: return .cyan
        case .custom: return .gray
        }
    }
    
    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }
}

/// Centralized loading state manager
@MainActor
class LoadingStateManager: ObservableObject {
    static let shared = LoadingStateManager()
    
    // MARK: - Published State
    
    @Published private(set) var currentOperation: LoadingOperation = .idle
    @Published private(set) var operationStack: [LoadingOperation] = []
    @Published private(set) var errors: [LoadingError] = []
    
    // MARK: - Computed Properties
    
    var isLoading: Bool {
        currentOperation.isActive
    }
    
    var displayMessage: String {
        currentOperation.displayMessage
    }
    
    // MARK: - State Changes
    
    func startOperation(_ operation: LoadingOperation) {
        // Push current to stack if not idle
        if currentOperation.isActive {
            operationStack.append(currentOperation)
        }
        currentOperation = operation
    }
    
    func updateProgress(_ progress: Double) {
        if case .streaming = currentOperation {
            currentOperation = .streaming(progress: progress)
        }
    }
    
    func completeOperation() {
        // Pop from stack or go idle
        if let previous = operationStack.popLast() {
            currentOperation = previous
        } else {
            currentOperation = .idle
        }
    }
    
    func reset() {
        currentOperation = .idle
        operationStack = []
    }
    
    // MARK: - Error Handling
    
    func addError(_ error: LoadingError) {
        errors.append(error)
        
        // Auto-remove after 5 seconds
        let errorId = error.id
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            errors.removeAll { $0.id == errorId }
        }
    }
    
    func clearError(_ id: UUID) {
        errors.removeAll { $0.id == id }
    }
    
    func clearAllErrors() {
        errors = []
    }
}

// MARK: - Loading Error

struct LoadingError: Identifiable {
    let id = UUID()
    let message: String
    let details: String?
    let timestamp: Date
    let severity: Severity
    
    enum Severity {
        case info
        case warning
        case error
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }
    
    init(message: String, details: String? = nil, severity: Severity = .error) {
        self.message = message
        self.details = details
        self.timestamp = Date()
        self.severity = severity
    }
}

// MARK: - Loading Indicator View

struct UnifiedLoadingIndicator: View {
    @StateObject private var loadingManager = LoadingStateManager.shared
    
    var body: some View {
        if loadingManager.isLoading {
            HStack(spacing: 8) {
                // Animated icon
                Image(systemName: loadingManager.currentOperation.icon)
                    .font(.system(size: 12))
                    .foregroundColor(loadingManager.currentOperation.color)
                    .symbolEffect(.pulse)
                
                Text(loadingManager.displayMessage)
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(loadingManager.currentOperation.color.opacity(0.1))
            )
            .transition(.opacity.combined(with: .scale))
        }
    }
}

// MARK: - Error Toast View

struct ErrorToastView: View {
    @StateObject private var loadingManager = LoadingStateManager.shared
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(loadingManager.errors) { error in
                HStack(spacing: 8) {
                    Image(systemName: error.severity.icon)
                        .font(.system(size: 12))
                        .foregroundColor(error.severity.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        if let details = error.details {
                            Text(details)
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { loadingManager.clearError(error.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: loadingManager.errors.count)
    }
}
