//
//  DeploymentPanelView.swift
//  LingCode
//
//  One-click deployment panel with platform selection, validation, and history
//

import SwiftUI

struct DeploymentPanelView: View {
    @ObservedObject private var deploymentService = DeploymentService.shared
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var showConfigSheet: Bool = false
    @State private var showHistorySheet: Bool = false
    @State private var editingConfig: DeploymentConfig?
    @State private var showPlatformPicker: Bool = false
    @State private var isDeploying: Bool = false
    @State private var showLogs: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Status & Quick Deploy
            statusSection
            
            Divider()
            
            // Configuration
            configurationSection
            
            if showLogs && !deploymentService.deploymentLogs.isEmpty {
                Divider()
                logsSection
            }
            
            Divider()
            
            // Actions
            actionsBar
        }
        .onAppear {
            if let url = editorViewModel.rootFolderURL {
                deploymentService.setProject(url)
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            DeploymentConfigSheet(
                config: editingConfig ?? deploymentService.createConfig(for: .vercel),
                isNew: editingConfig == nil,
                onSave: { config in
                    deploymentService.saveConfig(config)
                    deploymentService.currentConfig = config
                    showConfigSheet = false
                    editingConfig = nil
                },
                onCancel: {
                    showConfigSheet = false
                    editingConfig = nil
                }
            )
        }
        .sheet(isPresented: $showHistorySheet) {
            DeploymentHistorySheet(history: deploymentService.history)
        }
        .sheet(isPresented: $showPlatformPicker) {
            PlatformPickerSheet(
                availablePlatforms: deploymentService.availablePlatforms,
                recommendedPlatforms: deploymentService.detectedProjectType.recommendedPlatforms,
                onSelect: { platform in
                    let config = deploymentService.createConfig(for: platform)
                    deploymentService.currentConfig = config
                    editingConfig = config
                    showPlatformPicker = false
                    showConfigSheet = true
                }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .foregroundColor(.blue)
            
            Text("Deploy")
                .fontWeight(.medium)
            
            Spacer()
            
            // Project type badge
            if deploymentService.detectedProjectType != .unknown {
                Text(deploymentService.detectedProjectType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // History button
            Button(action: { showHistorySheet = true }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(PlainButtonStyle())
            .help("Deployment History")
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 8) {
                statusIcon
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deploymentService.status.displayText)
                        .font(.headline)
                    
                    if let url = deploymentService.lastDeploymentURL {
                        Link(url, destination: URL(string: url)!)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                // Cancel button during deployment
                if deploymentService.status.isInProgress {
                    Button(action: { deploymentService.cancelDeployment() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Validation results
            if deploymentService.validationResult.errors.isEmpty == false ||
               deploymentService.validationResult.warnings.isEmpty == false {
                validationResultsView
            }
            
            // Quick deploy button
            Button(action: quickDeploy) {
                HStack {
                    if isDeploying {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text(isDeploying ? "Deploying..." : "Deploy Now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDeploying || deploymentService.availablePlatforms.isEmpty)
        }
        .padding(12)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch deploymentService.status {
        case .idle:
            Image(systemName: "cloud.fill")
                .foregroundColor(.secondary)
        case .validating, .runningTests, .building, .deploying:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .foregroundColor(.orange)
        }
    }
    
    private var validationResultsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(deploymentService.validationResult.errors, id: \.self) { error in
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            ForEach(deploymentService.validationResult.warnings, id: \.self) { warning in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    // MARK: - Configuration Section
    
    private var configurationSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Configuration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                Button("Add Platform...") {
                    showPlatformPicker = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            if deploymentService.configs.isEmpty {
                // No configs yet
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No deployment configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !deploymentService.availablePlatforms.isEmpty {
                        Text("Available: \(deploymentService.availablePlatforms.map(\.rawValue).joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Config list
                ForEach(deploymentService.configs) { config in
                    configRow(config)
                }
            }
        }
        .padding(12)
    }
    
    private func configRow(_ config: DeploymentConfig) -> some View {
        HStack(spacing: 8) {
            // Platform icon
            Image(systemName: config.platform.icon)
                .foregroundColor(deploymentService.currentConfig?.id == config.id ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.caption)
                    .fontWeight(deploymentService.currentConfig?.id == config.id ? .semibold : .regular)
                
                HStack(spacing: 4) {
                    Text(config.branch)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(config.environment.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(environmentColor(config.environment).opacity(0.2))
                        .cornerRadius(2)
                }
            }
            
            Spacer()
            
            // Actions
            Button(action: {
                editingConfig = config
                showConfigSheet = true
            }) {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                deploymentService.currentConfig = config
            }) {
                Image(systemName: deploymentService.currentConfig?.id == config.id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(deploymentService.currentConfig?.id == config.id ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(8)
        .background(deploymentService.currentConfig?.id == config.id ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    
    private func environmentColor(_ env: DeploymentEnvironment) -> Color {
        switch env {
        case .development: return .gray
        case .staging: return .orange
        case .preview: return .blue
        case .production: return .green
        }
    }
    
    // MARK: - Logs Section
    
    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { deploymentService.deploymentLogs = "" }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            ScrollView {
                Text(deploymentService.deploymentLogs)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 120)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
    }
    
    // MARK: - Actions Bar
    
    private var actionsBar: some View {
        HStack(spacing: 12) {
            // Toggle logs
            Button(action: { showLogs.toggle() }) {
                Label(showLogs ? "Hide Logs" : "Show Logs", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            // Validate only
            Button(action: validateOnly) {
                Label("Validate", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .disabled(deploymentService.currentConfig == nil || deploymentService.status.isInProgress)
            
            // Open deployed URL
            if let url = deploymentService.lastDeploymentURL, let nsURL = URL(string: url) {
                Link(destination: nsURL) {
                    Label("Open", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func quickDeploy() {
        isDeploying = true
        showLogs = true
        
        Task {
            _ = await deploymentService.quickDeploy()
            await MainActor.run {
                isDeploying = false
            }
        }
    }
    
    private func validateOnly() {
        guard let config = deploymentService.currentConfig else { return }
        
        Task {
            _ = await deploymentService.validate(config: config)
        }
    }
}

// MARK: - Config Sheet

struct DeploymentConfigSheet: View {
    @State var config: DeploymentConfig
    let isNew: Bool
    let onSave: (DeploymentConfig) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Deployment Config" : "Edit Config")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("General") {
                    TextField("Name", text: $config.name)
                    
                    Picker("Platform", selection: $config.platform) {
                        ForEach(DeploymentPlatform.allCases) { platform in
                            Label(platform.rawValue, systemImage: platform.icon)
                                .tag(platform)
                        }
                    }
                    
                    TextField("Branch", text: $config.branch)
                    
                    Picker("Environment", selection: $config.environment) {
                        ForEach(DeploymentEnvironment.allCases, id: \.self) { env in
                            Text(env.displayName).tag(env)
                        }
                    }
                }
                
                Section("Build") {
                    TextField("Build Command", text: Binding(
                        get: { config.buildCommand ?? "" },
                        set: { config.buildCommand = $0.isEmpty ? nil : $0 }
                    ))
                    .help("e.g., npm run build")
                    
                    TextField("Output Directory", text: Binding(
                        get: { config.outputDirectory ?? "" },
                        set: { config.outputDirectory = $0.isEmpty ? nil : $0 }
                    ))
                    .help("e.g., dist, build, .next")
                }
                
                Section("Custom Command") {
                    TextField("Deploy Command (optional)", text: Binding(
                        get: { config.customDeployCommand ?? "" },
                        set: { config.customDeployCommand = $0.isEmpty ? nil : $0 }
                    ))
                    .help("Override default deploy command")
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        DeploymentService.shared.deleteConfig(config.id)
                        onCancel()
                    }
                }
                
                Spacer()
                
                Button("Save") {
                    onSave(config)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(config.name.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }
}

// MARK: - Platform Picker Sheet

struct PlatformPickerSheet: View {
    let availablePlatforms: [DeploymentPlatform]
    let recommendedPlatforms: [DeploymentPlatform]
    let onSelect: (DeploymentPlatform) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Platform")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            List {
                if !availablePlatforms.isEmpty {
                    Section("Installed") {
                        ForEach(availablePlatforms) { platform in
                            platformRow(platform, installed: true)
                        }
                    }
                }
                
                let notInstalled = DeploymentPlatform.allCases.filter { !availablePlatforms.contains($0) && $0 != .custom }
                if !notInstalled.isEmpty {
                    Section("Not Installed") {
                        ForEach(notInstalled) { platform in
                            platformRow(platform, installed: false)
                        }
                    }
                }
            }
        }
        .frame(width: 350, height: 400)
    }
    
    private func platformRow(_ platform: DeploymentPlatform, installed: Bool) -> some View {
        Button(action: { onSelect(platform) }) {
            HStack(spacing: 12) {
                Image(systemName: platform.icon)
                    .font(.title2)
                    .foregroundColor(installed ? .blue : .secondary)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(platform.rawValue)
                            .fontWeight(.medium)
                        
                        if recommendedPlatforms.contains(platform) {
                            Text("Recommended")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(2)
                        }
                    }
                    
                    if !installed {
                        Text(platform.installInstructions)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if installed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!installed)
    }
}

// MARK: - History Sheet

struct DeploymentHistorySheet: View {
    let history: [DeploymentHistoryEntry]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Deployment History")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            
            Divider()
            
            if history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No deployments yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(history) { entry in
                    historyRow(entry)
                }
            }
        }
        .frame(width: 450, height: 400)
    }
    
    private func historyRow(_ entry: DeploymentHistoryEntry) -> some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(entry.success ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.platform.rawValue)
                        .fontWeight(.medium)
                    
                    Text(entry.environment.displayName)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(2)
                }
                
                if let commit = entry.commitMessage {
                    Text(commit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let duration = entry.duration {
                        Text("\(Int(duration))s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if let url = entry.url, let nsURL = URL(string: url) {
                Link(destination: nsURL) {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DeploymentPanelView(editorViewModel: EditorViewModel())
        .frame(width: 350, height: 600)
}
