//
//  TaskClassifier.swift
//  LingCode
//
//  Fast + Reliable task classification with heuristic overrides
//

import Foundation

enum AITaskType {
    case autocomplete
    case inlineEdit
    case refactor
    case debug
    case generate
    case chat
}

struct ClassificationContext {
    let userInput: String
    let cursorIsMidLine: Bool
    let diagnosticsPresent: Bool
    let selectionExists: Bool
    let activeFile: URL?
    let selectedText: String?
}

class TaskClassifier {
    static let shared = TaskClassifier()
    
    private init() {}
    
    /// Classify task with fast heuristics + model fallback
    func classify(context: ClassificationContext) -> AITaskType {
        // Fast heuristic overrides (CRITICAL - runs before model)
        if context.cursorIsMidLine {
            return .autocomplete
        }
        
        if context.diagnosticsPresent {
            return .debug
        }
        
        if context.selectionExists && !context.selectedText!.isEmpty {
            return .inlineEdit
        }
        
        // Model-based classification (fallback)
        return classifyWithModel(context: context)
    }
    
    /// Model-based classification (runs on small model or locally)
    private func classifyWithModel(context: ClassificationContext) -> AITaskType {
        // Build prompt for future use with model
        _ = buildClassifierPrompt(userInput: context.userInput)
        
        // For now, use heuristic-based classification
        // In production, would call small local model or GPT-4o mini
        return classifyHeuristically(userInput: context.userInput)
    }
    
    /// Heuristic-based classification (fast, no model call)
    private func classifyHeuristically(userInput: String) -> AITaskType {
        let lowercased = userInput.lowercased()
        
        // Refactor keywords
        if lowercased.contains("refactor") ||
           lowercased.contains("restructure") ||
           lowercased.contains("rename") ||
           lowercased.contains("extract") {
            return .refactor
        }
        
        // Debug keywords
        if lowercased.contains("debug") ||
           lowercased.contains("fix error") ||
           lowercased.contains("why is") ||
           lowercased.contains("not working") ||
           lowercased.contains("broken") {
            return .debug
        }
        
        // Generate keywords
        if lowercased.contains("generate") ||
           lowercased.contains("create") ||
           lowercased.contains("make") ||
           lowercased.contains("build") ||
           lowercased.contains("add") {
            return .generate
        }
        
        // Inline edit keywords
        if lowercased.contains("change") ||
           lowercased.contains("modify") ||
           lowercased.contains("update") ||
           lowercased.contains("improve") ||
           lowercased.contains("edit") {
            return .inlineEdit
        }
        
        // Default to chat
        return .chat
    }
    
    /// Build classifier prompt (for model-based classification)
    private func buildClassifierPrompt(userInput: String) -> String {
        return """
        You are a classifier for an IDE assistant.
        
        Classify the user's intent into exactly ONE category:
        
        - autocomplete: continue code at cursor
        - inline_edit: small change to existing code
        - refactor: restructure code or rename symbols
        - debug: fix errors or failing behavior
        - generate: create new code or files
        
        User request:
        "\(userInput)"
        
        Respond with ONLY the category name.
        """
    }
    
    /// Parse model response
    private func parseModelResponse(_ response: String) -> AITaskType {
        let lowercased = response.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch lowercased {
        case "autocomplete", "autocomplete:":
            return .autocomplete
        case "inline_edit", "inlineedit", "inline_edit:", "inlineedit:":
            return .inlineEdit
        case "refactor", "refactor:":
            return .refactor
        case "debug", "debug:":
            return .debug
        case "generate", "generate:":
            return .generate
        default:
            return .chat
        }
    }
}
