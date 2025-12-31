//
//  LocalOnlyService.swift
//  LingCode
//
//  Local-only mode for privacy and enterprise security
//  Addresses Cursor's privacy concerns
//

import Foundation

/// Service for local-only AI processing
/// Addresses enterprise privacy and security concerns
class LocalOnlyService {
    static let shared = LocalOnlyService()
    
    var isLocalModeEnabled: Bool = false
    var availableLocalModels: [LocalModel] = []
    
    private init() {
        loadSettings()
        detectLocalModels()
    }
    
    /// Check if local model is available
    func isLocalModelAvailable() -> Bool {
        return !availableLocalModels.isEmpty
    }
    
    /// Enable local-only mode
    func enableLocalMode() {
        isLocalModeEnabled = true
        saveSettings()
    }
    
    /// Disable local-only mode
    func disableLocalMode() {
        isLocalModeEnabled = false
        saveSettings()
    }
    
    /// Detect available local models
    private func detectLocalModels() {
        // Check for common local AI model installations
        // This is a placeholder - real implementation would check for:
        // - Ollama
        // - LM Studio
        // - Local LLM servers
        // - etc.
        
        // For now, return empty - would be implemented based on actual local model setup
        availableLocalModels = []
    }
    
    /// Process request locally
    func processLocally(
        prompt: String,
        context: String? = nil,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard isLocalModeEnabled else {
            onError(NSError(domain: "LocalOnlyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local mode not enabled"]))
            return
        }
        
        guard let model = availableLocalModels.first else {
            onError(NSError(domain: "LocalOnlyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No local models available"]))
            return
        }
        
        // Process with local model
        // This would integrate with actual local model API
        processWithLocalModel(model: model, prompt: prompt, context: context, onResponse: onResponse, onError: onError)
    }
    
    private func processWithLocalModel(
        model: LocalModel,
        prompt: String,
        context: String?,
        onResponse: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Placeholder - would integrate with actual local model
        // For example: Ollama, LM Studio, etc.
        onError(NSError(domain: "LocalOnlyService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Local model processing not yet implemented"]))
    }
    
    /// Encrypt code before sending to API (when local mode is off)
    func encryptCode(_ code: String) -> String {
        // Simple base64 encoding for now
        // In production, would use proper encryption
        if let data = code.data(using: .utf8) {
            return data.base64EncodedString()
        }
        return code
    }
    
    /// Decrypt code after receiving from API
    func decryptCode(_ encrypted: String) -> String {
        // Simple base64 decoding for now
        if let data = Data(base64Encoded: encrypted),
           let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return encrypted
    }
    
    /// Log security action for audit
    func logAction(_ action: SecurityAction) {
        // Log to audit trail
        let logEntry = AuditLogEntry(
            action: action,
            timestamp: Date(),
            user: NSUserName()
        )
        
        // Save to audit log
        saveAuditLog(logEntry)
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isLocalModeEnabled, forKey: "local_mode_enabled")
    }
    
    private func loadSettings() {
        isLocalModeEnabled = UserDefaults.standard.bool(forKey: "local_mode_enabled")
    }
    
    private func saveAuditLog(_ entry: AuditLogEntry) {
        // Save to audit log file
        // In production, would use proper logging system
    }
}

// MARK: - Models

struct LocalModel {
    let id: String
    let name: String
    let provider: String // "ollama", "lmstudio", etc.
    let isAvailable: Bool
}

enum SecurityAction {
    case codeApplied
    case codeRejected
    case fileOpened(path: String)
    case apiRequest(provider: String)
    case localRequest
    case settingsChanged
}

struct AuditLogEntry {
    let action: SecurityAction
    let timestamp: Date
    let user: String
}

