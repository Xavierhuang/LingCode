//
//  PluginPanelView.swift
//  LingCode
//
//  Plugin management panel - browse, install, and manage plugins
//

import SwiftUI
import UniformTypeIdentifiers

struct PluginPanelView: View {
    @ObservedObject private var pluginService = PluginService.shared
    
    @State private var selectedTab: PluginTab = .installed
    @State private var searchText: String = ""
    @State private var selectedPlugin: PluginInfo?
    @State private var showInstallSheet: Bool = false
    @State private var selectedCategory: PluginCategory?
    
    enum PluginTab: String, CaseIterable {
        case installed = "Installed"
        case browse = "Browse"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab selector
            tabSelector
            
            Divider()
            
            // Content
            switch selectedTab {
            case .installed:
                installedPluginsView
            case .browse:
                browsePluginsView
            }
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallPluginSheet(onInstall: { url in
                Task {
                    try? await pluginService.installPlugin(from: url)
                }
                showInstallSheet = false
            })
        }
        .onAppear {
            Task {
                await pluginService.fetchAvailablePlugins()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .foregroundColor(.purple)
            
            Text("Plugins")
                .fontWeight(.medium)
            
            Spacer()
            
            // Installed count
            Text("\(pluginService.installedPlugins.count) installed")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Install from file
            Button(action: { showInstallSheet = true }) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(PlainButtonStyle())
            .help("Install plugin from file")
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(PluginTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.caption)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    // MARK: - Installed Plugins
    
    private var installedPluginsView: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search installed plugins...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .padding(12)
            
            // Plugin list
            if filteredInstalledPlugins.isEmpty {
                emptyStateView(
                    icon: "puzzlepiece",
                    title: "No plugins installed",
                    message: "Browse the marketplace to find plugins"
                )
            } else {
                List {
                    ForEach(filteredInstalledPlugins) { plugin in
                        InstalledPluginRow(plugin: plugin) {
                            Task {
                                await pluginService.togglePlugin(plugin.id)
                            }
                        } onUninstall: {
                            Task {
                                try? await pluginService.uninstallPlugin(plugin.id)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    private var filteredInstalledPlugins: [PluginInfo] {
        if searchText.isEmpty {
            return pluginService.installedPlugins
        }
        return pluginService.installedPlugins.filter {
            $0.manifest.name.localizedCaseInsensitiveContains(searchText) ||
            $0.manifest.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - Browse Plugins
    
    private var browsePluginsView: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search marketplace...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .padding(12)
            
            // Category filter
            categoryFilterView
            
            Divider()
            
            // Available plugins
            if pluginService.isLoading {
                ProgressView("Loading plugins...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredAvailablePlugins.isEmpty {
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "No plugins found",
                    message: "Try a different search term"
                )
            } else {
                List {
                    ForEach(filteredAvailablePlugins) { plugin in
                        AvailablePluginRow(plugin: plugin) {
                            // Install action
                            Task {
                                // Would download and install
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    private var categoryFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(nil, title: "All")
                
                ForEach(PluginCategory.allCases, id: \.self) { category in
                    categoryButton(category, title: category.rawValue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    private func categoryButton(_ category: PluginCategory?, title: String) -> some View {
        Button(action: { selectedCategory = category }) {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(selectedCategory == category ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(selectedCategory == category ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var filteredAvailablePlugins: [PluginRegistryEntry] {
        var plugins = pluginService.availablePlugins
        
        // Filter by category
        if let category = selectedCategory {
            plugins = plugins.filter { $0.category == category }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            plugins = plugins.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return plugins
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Installed Plugin Row

struct InstalledPluginRow: View {
    let plugin: PluginInfo
    let onToggle: () -> Void
    let onUninstall: () -> Void
    
    @State private var showConfig: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: plugin.manifest.icon ?? plugin.manifest.category.icon)
                .font(.title2)
                .foregroundColor(plugin.isEnabled ? categoryColor : .secondary)
                .frame(width: 32, height: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(plugin.manifest.name)
                        .fontWeight(.medium)
                    
                    Text("v\(plugin.manifest.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if plugin.manifest.main == "built-in" {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(2)
                    }
                }
                
                Text(plugin.manifest.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Status
                if let error = plugin.loadError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                    }
                    .font(.caption2)
                } else if plugin.isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Active")
                    }
                    .font(.caption2)
                    .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Config button (if plugin has config)
                // Button(action: { showConfig = true }) {
                //     Image(systemName: "gear")
                // }
                // .buttonStyle(PlainButtonStyle())
                
                // Toggle
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                
                // Uninstall (not for built-in)
                if plugin.manifest.main != "built-in" {
                    Button(action: onUninstall) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var categoryColor: Color {
        switch plugin.manifest.category {
        case .language: return .blue
        case .theme: return .purple
        case .git: return .orange
        case .formatter: return .green
        case .linter: return .yellow
        case .ai: return .pink
        case .tools: return .cyan
        case .integration: return .indigo
        case .other: return .gray
        }
    }
}

// MARK: - Available Plugin Row

struct AvailablePluginRow: View {
    let plugin: PluginRegistryEntry
    let onInstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: plugin.category.icon)
                .font(.title2)
                .foregroundColor(categoryColor)
                .frame(width: 32, height: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(plugin.name)
                        .fontWeight(.medium)
                    
                    Text("v\(plugin.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(plugin.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label("\(plugin.stars)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    
                    Label("\(formatDownloads(plugin.downloads))", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(plugin.author)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Install button
            if plugin.isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                Button(action: onInstall) {
                    Text("Install")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var categoryColor: Color {
        switch plugin.category {
        case .language: return .blue
        case .theme: return .purple
        case .git: return .orange
        case .formatter: return .green
        case .linter: return .yellow
        case .ai: return .pink
        case .tools: return .cyan
        case .integration: return .indigo
        case .other: return .gray
        }
    }
    
    private func formatDownloads(_ count: Int) -> String {
        if count >= 1000000 {
            return "\(count / 1000000)M"
        } else if count >= 1000 {
            return "\(count / 1000)K"
        }
        return "\(count)"
    }
}

// MARK: - Install Plugin Sheet

struct InstallPluginSheet: View {
    let onInstall: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: URL?
    @State private var isDragging: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Install Plugin")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            // Drop zone
            VStack(spacing: 16) {
                if let url = selectedURL {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        
                        Text(url.lastPathComponent)
                            .fontWeight(.medium)
                        
                        Button("Choose Different File") {
                            selectFile()
                        }
                        .font(.caption)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.largeTitle)
                            .foregroundColor(isDragging ? .accentColor : .secondary)
                        
                        Text("Drop plugin folder or .zip here")
                            .font(.headline)
                        
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Choose File") {
                            selectFile()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isDragging ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding()
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                guard let provider = providers.first else { return false }
                
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            selectedURL = url
                        }
                    }
                }
                return true
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Install") {
                    if let url = selectedURL {
                        onInstall(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedURL == nil)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .zip]
        
        if panel.runModal() == .OK {
            selectedURL = panel.url
        }
    }
}

#Preview {
    PluginPanelView()
        .frame(width: 400, height: 600)
}
