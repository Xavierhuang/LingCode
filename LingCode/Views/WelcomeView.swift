//
//  WelcomeView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    @State private var apiKey: String = ""
    @State private var selectedProvider: AIProvider = .anthropic
    @State private var showAPIKey: Bool = false
    @State private var isSettingUp: Bool = false
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Welcome to LingCode")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("An AI-powered code editor")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Get started in 2 steps:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("1.")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Choose your AI provider")
                            .font(.body)
                    }
                    
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Anthropic Claude").tag(AIProvider.anthropic)
                        Text("OpenAI GPT").tag(AIProvider.openAI)
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("2.")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Enter your API key")
                            .font(.body)
                    }
                    
                    HStack {
                        if showAPIKey {
                            TextField("Enter API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: {
                            showAPIKey.toggle()
                        }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                    }
                    
                    Text(getAPIKeyInstructions())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 500)
            
            HStack(spacing: 16) {
                Button("Skip for now") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Get Started") {
                    setupAPI()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty || isSettingUp)
            }
        }
        .padding(40)
        .frame(width: 600, height: 500)
    }
    
    private func getAPIKeyInstructions() -> String {
        switch selectedProvider {
        case .anthropic:
            return "Get your API key from: https://console.anthropic.com/\n\nYour key starts with 'sk-ant-api03-'"
        case .openAI:
            return "Get your API key from: https://platform.openai.com/api-keys\n\nYour key starts with 'sk-'"
        }
    }
    
    private func setupAPI() {
        guard !apiKey.isEmpty else { return }
        
        isSettingUp = true
        viewModel.aiViewModel.setAPIKey(apiKey, provider: selectedProvider)
        
        // Test the API key
        Task { @MainActor in
            do {
                let aiService: AIProviderProtocol = ServiceContainer.shared.ai
                _ = try await aiService.sendMessage("Hello", context: nil, images: [], tools: nil)
                isSettingUp = false
                isPresented = false
            } catch {
                isSettingUp = false
                // Show error but still allow to proceed
                isPresented = false
            }
        }
    }
}








