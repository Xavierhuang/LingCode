//
//  APISetupHelper.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

class APISetupHelper {
    static func setupDefaultAPIKeyIfNeeded() {
        // Only set up if no API key is currently configured
        guard AIService.shared.getAPIKey() == nil else {
            return
        }
        
        // Note: For production, users should set their own API key via Settings
        // This function can be used to set a default key for development/testing
        // but should NOT contain hardcoded keys in the repository
        
        // To set a default API key for development, uncomment and add your key:
        // let defaultAPIKey = "your-api-key-here"
        // AIService.shared.setAPIKey(defaultAPIKey, provider: .anthropic)
        // AIService.shared.setAnthropicModel(.sonnet45)
        
        print("ℹ️  Please configure your API key in Settings (⌘,)")
    }
}








