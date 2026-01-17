//
//  APITestView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct APITestView: View {
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("API Connection Test")
                .font(.title2)
                .fontWeight(.bold)
            
            if isTesting {
                ProgressView()
                Text("Testing API connection...")
                    .foregroundColor(.secondary)
            } else if !testResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result:")
                        .font(.headline)
                    Text(testResult)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error:")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Button(action: {
                testAPI()
            }) {
                Text("Test API Connection")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTesting)
        }
        .padding()
        .frame(width: 400, height: 300)
    }
    
    private func testAPI() {
        // FIX: Use ModernAIService directly to ensure we're using the same service as the app
        let modernAIService = ServiceContainer.shared.modernAIService
        
        guard let apiKey = modernAIService.getAPIKey() else {
            errorMessage = "No API key configured. Please set your API key in Settings."
            return
        }
        
        let provider = modernAIService.getProvider()
        let model = modernAIService.getAnthropicModel()
        
        isTesting = true
        testResult = ""
        errorMessage = nil
        
        print("🧪 Testing API...")
        print("Provider: \(provider == .anthropic ? "Anthropic" : "OpenAI")")
        if provider == .anthropic {
            print("Model from enum: \(model.rawValue)")
            print("Model display name: \(model.displayName)")
        }
        print("API Key: \(apiKey.prefix(20))...")
        
        Task { @MainActor in
            do {
                let aiService: AIProviderProtocol = ServiceContainer.shared.ai
                let response = try await aiService.sendMessage("Say 'Hello from LingCode!' if you can read this.", context: nil, images: [], tools: nil)
                
                isTesting = false
                testResult = "✅ API is working!\n\nProvider: \(provider == .anthropic ? "Anthropic" : "OpenAI")\n\(provider == .anthropic ? "Model: \(model.displayName)\n" : "")Response: \(response)"
                print("✅ Test successful!")
            } catch {
                isTesting = false
                let nsError = error as NSError
                errorMessage = "❌ API Error: \(error.localizedDescription)\n\nProvider: \(provider == .anthropic ? "Anthropic" : "OpenAI")\n\(provider == .anthropic ? "Model: \(model.displayName)\n" : "")Error Code: \(nsError.code)\n\nMake sure:\n1. Your API key is correct\n2. You have internet connection\n3. The API service is available\n4. Check Console for detailed logs"
                print("❌ Test failed: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
            }
        }
    }
}

