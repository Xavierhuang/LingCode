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
        guard let apiKey = AIService.shared.getAPIKey() else {
            errorMessage = "No API key configured. Please set your API key in Settings."
            return
        }
        
        let provider = AIService.shared.getProvider()
        let model = AIService.shared.getAnthropicModel()
        
        isTesting = true
        testResult = ""
        errorMessage = nil
        
        print("🧪 Testing API...")
        print("Provider: \(provider == .anthropic ? "Anthropic" : "OpenAI")")
        if provider == .anthropic {
            print("Model: \(model.rawValue)")
        }
        print("API Key: \(apiKey.prefix(20))...")
        
        AIService.shared.sendMessage(
            "Say 'Hello from LingCode!' if you can read this.",
            context: nil,
            onResponse: { response in
                isTesting = false
                testResult = "✅ API is working!\n\nProvider: \(provider == .anthropic ? "Anthropic" : "OpenAI")\n\(provider == .anthropic ? "Model: \(model.displayName)\n" : "")Response: \(response)"
                print("✅ Test successful!")
            },
            onError: { error in
                isTesting = false
                let nsError = error as NSError
                errorMessage = "❌ API Error: \(error.localizedDescription)\n\nProvider: \(provider == .anthropic ? "Anthropic" : "OpenAI")\n\(provider == .anthropic ? "Model: \(model.displayName)\n" : "")Error Code: \(nsError.code)\n\nMake sure:\n1. Your API key is correct\n2. You have internet connection\n3. The API service is available\n4. Check Console for detailed logs"
                print("❌ Test failed: \(error.localizedDescription)")
            }
        )
    }
}

