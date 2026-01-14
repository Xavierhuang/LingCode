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
    @ObservedObject private var localService = LocalOnlyService.shared
    @ObservedObject private var themeService = ThemeService.shared
    @State private var apiKey: String = ""
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedAnthropicModel: AnthropicModel = .sonnet45
    @State private var showAPIKey: Bool = false
    @State private var showAPITest: Bool = false
    @State private var isTestingLocalModel: Bool = false
    @State private var localModelTestResult: String? = nil
    
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
                    // Local Models Section
                    Toggle("Use Local Models (Ollama)", isOn: Binding(
                        get: { localService.isLocalModeEnabled },
                        set: { enabled in
                            if enabled {
                                localService.enableLocalMode()
                                localService.refreshAvailableModels()
                            } else {
                                localService.disableLocalMode()
                            }
                        }
                    ))
                    
                    if localService.isLocalModeEnabled {
                        if localService.availableLocalModels.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No local models detected")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("Make sure Ollama is running and you have downloaded models")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Button("Refresh") {
                                        localService.refreshAvailableModels()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Button("Test Connection") {
                                        testLocalModel()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isTestingLocalModel)
                                    
                                    if isTestingLocalModel {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                                
                                if let result = localModelTestResult {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(result.contains("✅") ? .green : .orange)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Available Models:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(localService.availableLocalModels, id: \.id) { model in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text(model.name)
                                            .font(.caption)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    Button("Refresh") {
                                        localService.refreshAvailableModels()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Button("Test Connection") {
                                        testLocalModel()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isTestingLocalModel)
                                    
                                    if isTestingLocalModel {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                                .padding(.top, 4)
                                
                                if let result = localModelTestResult {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(result.contains("✅") ? .green : .orange)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Divider()
                    }
                    
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Anthropic Claude").tag(AIProvider.anthropic)
                        Text("OpenAI GPT").tag(AIProvider.openAI)
                    }
                    .disabled(localService.isLocalModeEnabled)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Appearance")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Picker("", selection: Binding(
                            get: { themeService.forcedTheme ?? .system },
                            set: { themeService.setTheme($0) }
                        )) {
                            ForEach(ThemeService.ThemePreference.allCases, id: \.self) { preference in
                                Text(preference.rawValue).tag(preference)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                        
                        Text(themeService.forcedTheme == .system ? "Theme follows system appearance" : "Theme is manually set")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
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
        .frame(minWidth: 500, minHeight: 400)
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
    
    private func testLocalModel() {
        isTestingLocalModel = true
        localModelTestResult = nil
        
        LocalOnlyService.shared.testOllamaConnection { result in
            DispatchQueue.main.async {
                isTestingLocalModel = false
                switch result {
                case .success(let response):
                    localModelTestResult = "✅ Connection successful!\nModel response: \(response.prefix(100))..."
                case .failure(let error):
                    localModelTestResult = "❌ \(error.localizedDescription)"
                }
            }
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

