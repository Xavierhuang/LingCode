//
//  ModelSelectionService.swift
//  LingCode
//
//  Task-based model selection for optimal AI performance
//

import Foundation

enum AITask {
    case autocomplete
    case inlineEdit
    case refactor
    case debug
    case generate
    case chat
    case documentation
}

enum SelectedModel {
    case claudeSonnet
    case claudeOpus
    case claudeHaiku
    case gpt4
    case gpt4Turbo
    case local
}

class ModelSelectionService {
    static let shared = ModelSelectionService()
    
    private init() {}
    
    /// Select the best model for a given task
    func selectModel(for task: AITask) -> SelectedModel {
        switch task {
        case .autocomplete:
            // Fast, cheap, local models for autocomplete
            return .local
            
        case .inlineEdit:
            // Claude Sonnet has best diff discipline
            return .claudeSonnet
            
        case .refactor:
            // GPT-4 for strong reasoning
            return .gpt4
            
        case .debug:
            // Claude Opus reads large context well
            return .claudeOpus
            
        case .generate:
            // Claude Sonnet for balanced generation
            return .claudeSonnet
            
        case .chat:
            // Claude Sonnet for general chat
            return .claudeSonnet
            
        case .documentation:
            // Claude Haiku for fast documentation
            return .claudeHaiku
        }
    }
    
    /// Get model identifier for API calls
    func getModelIdentifier(_ model: SelectedModel) -> String {
        switch model {
        case .claudeSonnet:
            return "claude-sonnet-4-5-20250929"
        case .claudeOpus:
            return "claude-opus-4-1-20250805"
        case .claudeHaiku:
            return "claude-haiku-4-5-20251001"
        case .gpt4:
            return "gpt-4"
        case .gpt4Turbo:
            return "gpt-4-turbo"
        case .local:
            return "local" // Placeholder for local models
        }
    }
    
    /// Detect task type from user input
    func detectTask(from input: String) -> AITask {
        let lowercased = input.lowercased()
        
        if lowercased.contains("refactor") || lowercased.contains("restructure") {
            return .refactor
        }
        
        if lowercased.contains("debug") || lowercased.contains("fix error") || lowercased.contains("why is") {
            return .debug
        }
        
        if lowercased.contains("document") || lowercased.contains("add comments") {
            return .documentation
        }
        
        if lowercased.contains("generate") || lowercased.contains("create") || lowercased.contains("make") {
            return .generate
        }
        
        // Default to chat
        return .chat
    }
}
