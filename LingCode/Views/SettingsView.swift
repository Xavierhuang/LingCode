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
    @State private var showRulesManagement: Bool = false
    
    var body: some View {
        NavigationView {
            List {
                editorSection
                aiConfigurationSection
                rulesSection
                codeGenSection
                themeSection
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
        .sheet(isPresented: $showRulesManagement) {
            RulesManagementView(projectURL: viewModel.rootFolderURL)
        }
        .onAppear {
            LingCodeRulesService.shared.loadRules(for: viewModel.rootFolderURL)
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
    
    @ViewBuilder private var editorSection: some View {
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
            
            // AI Autocomplete (Tab completion)
            Toggle("AI Autocomplete (Tab)", isOn: Binding(
                get: { InlineAutocompleteService.shared.isEnabled() },
                set: { InlineAutocompleteService.shared.setEnabled($0) }
            ))
            .help("Show AI-powered code suggestions as ghost text. Press Tab to accept.")
        }
    }
    
    @ViewBuilder private var aiConfigurationSection: some View {
        Section("AI Configuration") {
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
            ollamaStatusBlock
            localModelsBlock
            providerPickerBlock
            apiKeyBlock
        }
    }
    
    @ViewBuilder private var ollamaStatusBlock: some View {
        if !localService.isOllamaRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Ollama is not running")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Install Ollama to use local AI models. This allows you to run AI completely offline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { installOllama() }) {
                    HStack {
                        if localService.isInstallingOllama {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text("Install Local AI")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localService.isInstallingOllama)
                if !localService.installationProgress.isEmpty {
                    Text(localService.installationProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder private var localModelsBlock: some View {
        if localService.isLocalModeEnabled {
            if localService.availableLocalModels.isEmpty {
                localModelsEmptyView
            } else {
                localModelsListView
            }
            Divider()
        }
    }
    
    @ViewBuilder private var localModelsEmptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if localService.isOllamaRunning {
                Text("No local models detected")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Download models to use local AI")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button(action: { prepareOfflineMode() }) {
                    HStack {
                        if localService.isPullingModels {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text("Prepare Offline Mode")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localService.isPullingModels)
                modelPullProgressView
            } else {
                Text("Ollama is not running")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Please install and start Ollama first")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            localModelsActionRow
            if let result = localModelTestResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.lowercased().contains("success") ? .green : .orange)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder private var modelPullProgressView: some View {
        if !localService.modelPullProgress.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(localService.modelPullProgress.keys.sorted()), id: \.self) { model in
                    HStack {
                        if let progress = localService.modelPullProgress[model] {
                            if progress.lowercased().contains("success") || progress.contains("100") {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else if progress.lowercased().contains("fail") || progress.contains("error") {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            } else {
                                ProgressView().scaleEffect(0.6)
                            }
                            Text(progress)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
    
    private var localModelsActionRow: some View {
        HStack(spacing: 8) {
            Button("Refresh") {
                localService.refreshAvailableModels()
                localService.checkOllamaStatus()
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
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder private var localModelsListView: some View {
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
            localModelsActionRow
            if let result = localModelTestResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.lowercased().contains("success") ? .green : .orange)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var modelPicker: some View {
        Picker(selection: $selectedAnthropicModel, label: Text("Model")) {
            ForEach(AnthropicModel.allCases, id: \.self) { model in
                Text(model.displayName).tag(model)
            }
        }
        .pickerStyle(.menu)
    }
    
    @ViewBuilder private var providerPickerBlock: some View {
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
            modelPicker
        }
    }
    
    @ViewBuilder private var apiKeyBlock: some View {
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
            Button(action: { showAPIKey.toggle() }) {
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
            Button(action: { showAPITest = true }) {
                Text("Test Connection")
            }
            .buttonStyle(.bordered)
        }
    }
    
    @ViewBuilder private var rulesSection: some View {
        Section("Rules & Workspace") {
            Button(action: { showRulesManagement = true }) {
                HStack {
                    Label("Manage Rules", systemImage: "doc.text")
                    Spacer()
                    if LingCodeRulesService.shared.hasProjectRules {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .help("Create or edit WORKSPACE.md, .cursorrules, or .lingcode files")
            if let projectURL = viewModel.rootFolderURL {
                Text("Project: \(projectURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Open a project to manage rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder private var codeGenSection: some View {
        Section("Code Generation") {
            Toggle("Auto-imports", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "autoImportsEnabled") },
                set: { UserDefaults.standard.set($0, forKey: "autoImportsEnabled") }
            ))
            .help("Automatically add missing import statements when applying code (Cursor feature)")
        }
    }
    
    @ViewBuilder private var themeSection: some View {
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
    
    private func installOllama() {
        LocalOnlyService.shared.installOllama { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Installation successful, check status
                    LocalOnlyService.shared.checkOllamaStatus()
                    if LocalOnlyService.shared.isOllamaRunning {
                        LocalOnlyService.shared.refreshAvailableModels()
                    }
                case .failure(let error):
                    localModelTestResult = "❌ Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func prepareOfflineMode() {
        LocalOnlyService.shared.pullModels { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Models pulled successfully, refresh list
                    LocalOnlyService.shared.refreshAvailableModels()
                    localModelTestResult = "✅ Models downloaded successfully!"
                case .failure(let error):
                    localModelTestResult = "❌ Failed to download models: \(error.localizedDescription)"
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

