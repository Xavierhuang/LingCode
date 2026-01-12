//
//  SettingsView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    @State private var apiKey: String = ""
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedAnthropicModel: AnthropicModel = .sonnet45
    @State private var showAPIKey: Bool = false
    @State private var showAPITest: Bool = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Editor") {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Stepper(value: $viewModel.fontSize, in: 8...32, step: 1) {
                            Text("\(Int(viewModel.fontSize))")
                                .frame(width: 40)
                        }
                    }
                    
                    HStack {
                        Text("Font Family")
                        Spacer()
                        TextField("Font Name", text: $viewModel.fontName)
                            .frame(width: 150)
                    }
                    
                    Toggle("Word Wrap", isOn: $viewModel.wordWrap)
                }
                
                Section("AI Configuration") {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Anthropic Claude").tag(AIProvider.anthropic)
                        Text("OpenAI GPT").tag(AIProvider.openAI)
                    }
                    .onChange(of: selectedProvider) { oldValue, newValue in
                        if newValue == .anthropic {
                            selectedAnthropicModel = AIService.shared.getAnthropicModel()
                        }
                    }
                    
                    if selectedProvider == .anthropic {
                        Picker("Model", selection: $selectedAnthropicModel) {
                            ForEach(AnthropicModel.allCases, id: \.self) { model in
                                VStack(alignment: .leading) {
                                    Text(model.displayName)
                                    Text(model.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    HStack {
                        Text("API Key")
                        Spacer()
                        if showAPIKey {
                            TextField("Enter API Key", text: $apiKey)
                                .frame(width: 200)
                        } else {
                            SecureField("Enter API Key", text: $apiKey)
                                .frame(width: 200)
                        }
                        
                        Button(action: {
                            showAPIKey.toggle()
                        }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                    }
                    
                    Text(getAPIKeyHelpText())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        viewModel.aiViewModel.setAPIKey(apiKey, provider: selectedProvider)
                        if selectedProvider == .anthropic {
                            AIService.shared.setAnthropicModel(selectedAnthropicModel)
                        }
                    }) {
                        Text("Save API Key")
                    }
                    .disabled(apiKey.isEmpty)
                    
                    if viewModel.aiViewModel.hasAPIKey() {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API key configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            showAPITest = true
                        }) {
                            Text("Test Connection")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Section("Theme") {
                    Text("Theme automatically adapts to system appearance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            if let key = AIService.shared.getAPIKey() {
                apiKey = key
            }
            selectedProvider = AIService.shared.getProvider()
            if selectedProvider == .anthropic {
                selectedAnthropicModel = AIService.shared.getAnthropicModel()
            }
        }
        .sheet(isPresented: $showAPITest) {
            APITestView()
        }
    }
    
    private func getAPIKeyHelpText() -> String {
        switch selectedProvider {
        case .anthropic:
            return "Get your key from console.anthropic.com\nKey format: sk-ant-api03-..."
        case .openAI:
            return "Get your key from platform.openai.com\nKey format: sk-..."
        }
    }
}

