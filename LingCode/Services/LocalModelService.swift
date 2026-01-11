//
//  LocalModelService.swift
//  LingCode
//
//  Offline-first local model stack (Cursor killer feature)
//

import Foundation

enum LocalModel {
    case deepSeekCoder67B    // Autocomplete
    case phi3                // Rename validation
    case qwen7B              // Retry loop
    case starcoder2          // Lightweight fallback
    
    var identifier: String {
        switch self {
        case .deepSeekCoder67B: return "deepseek-coder-6.7b"
        case .phi3: return "phi-3"
        case .qwen7B: return "qwen-7b"
        case .starcoder2: return "starcoder2"
        }
    }
    
    var displayName: String {
        switch self {
        case .deepSeekCoder67B: return "DeepSeek Coder 6.7B"
        case .phi3: return "Phi-3"
        case .qwen7B: return "Qwen 7B"
        case .starcoder2: return "StarCoder2"
        }
    }
}

enum ModelTier {
    case tier1Local      // Always local
    case tier2Hybrid     // Cloud with local fallback
    case tier3Offline    // Offline mode only
}

class LocalModelService {
    static let shared = LocalModelService()
    
    private var isOffline: Bool = false
    private var isLowBattery: Bool = false
    private var localModelsAvailable: Set<LocalModel> = []
    
    private init() {
        checkLocalModelsAvailability()
    }
    
    /// Check which local models are available
    private func checkLocalModelsAvailability() {
        // Placeholder - would check for local model installations
        // For now, assume all are available
        localModelsAvailable = [.deepSeekCoder67B, .phi3, .qwen7B, .starcoder2]
    }
    
    /// Select model based on task and availability
    func selectModel(
        for task: AITask,
        requiresReasoning: Bool = false
    ) -> (model: String, isLocal: Bool) {
        // Offline mode or low battery → use local
        if isOffline || isLowBattery {
            return selectLocalModel(for: task)
        }
        
        // Requires reasoning → use cloud
        if requiresReasoning {
            return selectCloudModel(for: task)
        }
        
        // Tier 1 tasks → always local
        switch task {
        case .autocomplete:
            return (LocalModel.deepSeekCoder67B.identifier, true)
        default:
            // Hybrid: try cloud, fallback to local
            return selectHybridModel(for: task)
        }
    }
    
    /// Select local model for task
    private func selectLocalModel(for task: AITask) -> (String, Bool) {
        switch task {
        case .autocomplete:
            if localModelsAvailable.contains(.deepSeekCoder67B) {
                return (LocalModel.deepSeekCoder67B.identifier, true)
            }
            return (LocalModel.starcoder2.identifier, true)
            
        case .inlineEdit:
            // Use Qwen for edits
            return (LocalModel.qwen7B.identifier, true)
            
        case .refactor:
            // Use Qwen for refactors
            return (LocalModel.qwen7B.identifier, true)
            
        case .debug:
            // Use Phi-3 for validation
            return (LocalModel.phi3.identifier, true)
            
        default:
            return (LocalModel.qwen7B.identifier, true)
        }
    }
    
    /// Select cloud model for task
    private func selectCloudModel(for task: AITask) -> (String, Bool) {
        let modelSelection = ModelSelectionService.shared
        let selectedModel = modelSelection.selectModel(for: task)
        return (modelSelection.getModelIdentifier(selectedModel), false)
    }
    
    /// Select hybrid model (cloud with local fallback)
    private func selectHybridModel(for task: AITask) -> (String, Bool) {
        // Prefer cloud, but have local ready
        return selectCloudModel(for: task)
    }
    
    /// Set offline mode
    func setOfflineMode(_ enabled: Bool) {
        isOffline = enabled
    }
    
    /// Set low battery mode
    func setLowBatteryMode(_ enabled: Bool) {
        isLowBattery = enabled
    }
    
    /// Check if offline mode is active
    var isOfflineModeActive: Bool {
        return isOffline || isLowBattery
    }
    
    /// Get offline mode badge text
    var offlineModeBadge: String? {
        if isOfflineModeActive {
            return "⚡ Offline mode active"
        }
        return nil
    }
}

// MARK: - Model Routing Logic

extension LocalModelService {
    /// Route request to appropriate model
    func routeRequest(
        task: AITask,
        requiresReasoning: Bool = false,
        onLocal: @escaping (String) -> Void,
        onCloud: @escaping (String) -> Void
    ) {
        let (model, isLocal) = selectModel(for: task, requiresReasoning: requiresReasoning)
        
        if isLocal {
            onLocal(model)
        } else {
            onCloud(model)
        }
    }
}

// MARK: - Offline Mode Integration

extension PerformanceOptimizer {
    /// Check if should use offline mode
    func shouldUseOfflineMode() -> Bool {
        return isPowerSavingMode || LocalModelService.shared.isOfflineModeActive
    }
}
