//
//  SettingsPersistenceService.swift
//  LingCode
//
//  Settings persistence using UserDefaults
//

import Foundation
import Combine

/// Service for persisting and loading application settings
class SettingsPersistenceService: ObservableObject {
    static let shared = SettingsPersistenceService()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Editor Settings Keys
    private let fontSizeKey = "editor_font_size"
    private let fontNameKey = "editor_font_name"
    private let wordWrapKey = "editor_word_wrap"
    private let includeRelatedFilesKey = "ai_include_related_files"
    private let showThinkingProcessKey = "ai_show_thinking_process"
    private let autoExecuteCodeKey = "ai_auto_execute_code"
    
    private init() {}
    
    // MARK: - Editor Settings
    
    func saveFontSize(_ size: CGFloat) {
        defaults.set(size, forKey: fontSizeKey)
    }
    
    func loadFontSize() -> CGFloat {
        if defaults.object(forKey: fontSizeKey) != nil {
            return CGFloat(defaults.double(forKey: fontSizeKey))
        }
        return EditorConstants.defaultFontSize
    }
    
    func saveFontName(_ name: String) {
        defaults.set(name, forKey: fontNameKey)
    }
    
    func loadFontName() -> String {
        return defaults.string(forKey: fontNameKey) ?? EditorConstants.defaultFontName
    }
    
    func saveWordWrap(_ enabled: Bool) {
        defaults.set(enabled, forKey: wordWrapKey)
    }
    
    func loadWordWrap() -> Bool {
        if defaults.object(forKey: wordWrapKey) != nil {
            return defaults.bool(forKey: wordWrapKey)
        }
        return false
    }
    
    // MARK: - AI Settings
    
    func saveIncludeRelatedFiles(_ enabled: Bool) {
        defaults.set(enabled, forKey: includeRelatedFilesKey)
    }
    
    func loadIncludeRelatedFiles() -> Bool {
        if defaults.object(forKey: includeRelatedFilesKey) != nil {
            return defaults.bool(forKey: includeRelatedFilesKey)
        }
        return true // Default to true
    }
    
    func saveShowThinkingProcess(_ enabled: Bool) {
        defaults.set(enabled, forKey: showThinkingProcessKey)
    }
    
    func loadShowThinkingProcess() -> Bool {
        if defaults.object(forKey: showThinkingProcessKey) != nil {
            return defaults.bool(forKey: showThinkingProcessKey)
        }
        return true // Default to true
    }
    
    func saveAutoExecuteCode(_ enabled: Bool) {
        defaults.set(enabled, forKey: autoExecuteCodeKey)
    }
    
    func loadAutoExecuteCode() -> Bool {
        if defaults.object(forKey: autoExecuteCodeKey) != nil {
            return defaults.bool(forKey: autoExecuteCodeKey)
        }
        return false // Default to false
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        defaults.removeObject(forKey: fontSizeKey)
        defaults.removeObject(forKey: fontNameKey)
        defaults.removeObject(forKey: wordWrapKey)
        defaults.removeObject(forKey: includeRelatedFilesKey)
        defaults.removeObject(forKey: showThinkingProcessKey)
        defaults.removeObject(forKey: autoExecuteCodeKey)
    }
}







