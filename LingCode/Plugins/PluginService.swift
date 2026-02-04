//
//  PluginService.swift
//  LingCode
//
//  Plugin management service - discovers, loads, and manages plugins
//

import Foundation
import Combine
import SwiftUI

// MARK: - Plugin Info

struct PluginInfo: Identifiable, Codable {
    var id: String { manifest.id }
    let manifest: PluginManifest
    let url: URL
    var isEnabled: Bool
    var isLoaded: Bool
    var loadError: String?
    
    init(manifest: PluginManifest, url: URL, isEnabled: Bool = true) {
        self.manifest = manifest
        self.url = url
        self.isEnabled = isEnabled
        self.isLoaded = false
        self.loadError = nil
    }
}

// MARK: - Plugin Registry Entry

struct PluginRegistryEntry: Codable, Identifiable {
    var id: String { pluginId }
    let pluginId: String
    let name: String
    let version: String
    let author: String
    let description: String
    let category: PluginCategory
    let downloadURL: String
    let iconURL: String?
    let stars: Int
    let downloads: Int
    
    var isInstalled: Bool = false
}

// MARK: - Plugin Service

@MainActor
class PluginService: ObservableObject {
    static let shared = PluginService()
    
    // MARK: - Published State
    
    @Published var installedPlugins = [PluginInfo]()
    @Published var loadedPlugins = [String: LingCodePlugin]()
    @Published var availablePlugins = [PluginRegistryEntry]()
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    // MARK: - Private
    
    private let pluginsDirectory: URL
    private let configURL: URL
    private var pluginContexts = [String: PluginContext]()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        pluginsDirectory = lingcodeDir.appendingPathComponent("Plugins", isDirectory: true)
        configURL = lingcodeDir.appendingPathComponent("plugins_config.json")
        
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        
        loadConfig()
        discoverPlugins()
        loadBuiltInPlugins()
    }
    
    // MARK: - Plugin Discovery
    
    func discoverPlugins() {
        isLoading = true
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: pluginsDirectory,
                includingPropertiesForKeys: nil
            )
            
            for pluginURL in contents where pluginURL.hasDirectoryPath {
                let manifestURL = pluginURL.appendingPathComponent("plugin.json")
                
                if FileManager.default.fileExists(atPath: manifestURL.path),
                   let data = try? Data(contentsOf: manifestURL),
                   let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) {
                    
                    let info = PluginInfo(manifest: manifest, url: pluginURL)
                    
                    if !installedPlugins.contains(where: { $0.id == info.id }) {
                        installedPlugins.append(info)
                    }
                }
            }
        } catch {
            lastError = "Failed to discover plugins: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Built-in Plugins
    
    private func loadBuiltInPlugins() {
        // Register built-in plugins
        let builtInPlugins: [LingCodePlugin] = [
            GitStatusPlugin(),
            WordCountPlugin(),
            TodoHighlighterPlugin()
        ]
        
        for plugin in builtInPlugins {
            let manifest = PluginManifest(
                id: plugin.id,
                name: plugin.name,
                version: plugin.version,
                author: plugin.author,
                description: plugin.description,
                category: plugin.category,
                icon: plugin.icon,
                minimumAppVersion: plugin.minimumAppVersion,
                main: "built-in",
                dependencies: nil,
                permissions: nil,
                contributes: nil
            )
            
            let info = PluginInfo(manifest: manifest, url: URL(fileURLWithPath: "/built-in"))
            installedPlugins.append(info)
            
            Task {
                await activatePlugin(plugin.id)
            }
        }
    }
    
    // MARK: - Plugin Lifecycle
    
    func activatePlugin(_ pluginId: String) async {
        guard let index = installedPlugins.firstIndex(where: { $0.id == pluginId }) else {
            lastError = "Plugin not found: \(pluginId)"
            return
        }
        
        let info = installedPlugins[index]
        
        // Check if already loaded
        if loadedPlugins[pluginId] != nil {
            return
        }
        
        do {
            // Create plugin instance
            let plugin: LingCodePlugin
            
            if info.url.path == "/built-in" {
                // Built-in plugin
                plugin = getBuiltInPlugin(pluginId)!
            } else {
                // External plugin - would load from bundle
                throw PluginError.activationFailed("External plugin loading not yet implemented")
            }
            
            // Create context
            let context = PluginContext(pluginId: pluginId)
            pluginContexts[pluginId] = context
            
            // Activate
            try await plugin.activate(context: context)
            
            // Store
            loadedPlugins[pluginId] = plugin
            installedPlugins[index].isLoaded = true
            installedPlugins[index].loadError = nil
            
        } catch {
            installedPlugins[index].isLoaded = false
            installedPlugins[index].loadError = error.localizedDescription
            lastError = "Failed to activate \(pluginId): \(error.localizedDescription)"
        }
    }
    
    func deactivatePlugin(_ pluginId: String) async {
        guard let plugin = loadedPlugins[pluginId] else { return }
        
        await plugin.deactivate()
        
        loadedPlugins.removeValue(forKey: pluginId)
        pluginContexts.removeValue(forKey: pluginId)
        
        if let index = installedPlugins.firstIndex(where: { $0.id == pluginId }) {
            installedPlugins[index].isLoaded = false
        }
    }
    
    func togglePlugin(_ pluginId: String) async {
        guard let index = installedPlugins.firstIndex(where: { $0.id == pluginId }) else { return }
        
        installedPlugins[index].isEnabled.toggle()
        
        if installedPlugins[index].isEnabled {
            await activatePlugin(pluginId)
        } else {
            await deactivatePlugin(pluginId)
        }
        
        saveConfig()
    }
    
    private func getBuiltInPlugin(_ pluginId: String) -> LingCodePlugin? {
        switch pluginId {
        case "com.lingcode.git-status": return GitStatusPlugin()
        case "com.lingcode.word-count": return WordCountPlugin()
        case "com.lingcode.todo-highlighter": return TodoHighlighterPlugin()
        default: return nil
        }
    }
    
    // MARK: - Plugin Installation
    
    func installPlugin(from url: URL) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Create plugin directory
        let pluginName = url.deletingPathExtension().lastPathComponent
        let pluginDir = pluginsDirectory.appendingPathComponent(pluginName, isDirectory: true)
        
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        
        // If it's a zip, extract it
        if url.pathExtension == "zip" {
            try await extractZip(url, to: pluginDir)
        } else {
            // Copy directory contents
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for item in contents {
                let dest = pluginDir.appendingPathComponent(item.lastPathComponent)
                try FileManager.default.copyItem(at: item, to: dest)
            }
        }
        
        // Validate manifest
        let manifestURL = pluginDir.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            try? FileManager.default.removeItem(at: pluginDir)
            throw PluginError.invalidManifest("Missing or invalid plugin.json")
        }
        
        // Add to installed plugins
        let info = PluginInfo(manifest: manifest, url: pluginDir)
        installedPlugins.append(info)
        saveConfig()
        
        // Auto-activate
        await activatePlugin(manifest.id)
    }
    
    func uninstallPlugin(_ pluginId: String) async throws {
        // Deactivate first
        await deactivatePlugin(pluginId)
        
        // Find and remove
        guard let index = installedPlugins.firstIndex(where: { $0.id == pluginId }) else {
            return
        }
        
        let info = installedPlugins[index]
        
        // Don't remove built-in plugins
        if info.url.path != "/built-in" {
            try FileManager.default.removeItem(at: info.url)
        }
        
        installedPlugins.remove(at: index)
        saveConfig()
    }
    
    private func extractZip(_ zipURL: URL, to destination: URL) async throws {
        // Use Process to run unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destination.path]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw PluginError.activationFailed("Failed to extract plugin archive")
        }
    }
    
    // MARK: - Plugin Registry (Marketplace)
    
    func fetchAvailablePlugins() async {
        isLoading = true
        defer { isLoading = false }
        
        // In production, this would fetch from a remote registry
        // For now, provide some example entries
        availablePlugins = [
            PluginRegistryEntry(
                pluginId: "com.example.docker-tools",
                name: "Docker Tools",
                version: "1.2.0",
                author: "Example Dev",
                description: "Docker container management and Dockerfile support",
                category: .tools,
                downloadURL: "https://plugins.lingcode.dev/docker-tools-1.2.0.zip",
                iconURL: nil,
                stars: 245,
                downloads: 15000
            ),
            PluginRegistryEntry(
                pluginId: "com.example.prettier",
                name: "Prettier Formatter",
                version: "2.0.1",
                author: "Format Team",
                description: "Code formatting with Prettier",
                category: .formatter,
                downloadURL: "https://plugins.lingcode.dev/prettier-2.0.1.zip",
                iconURL: nil,
                stars: 892,
                downloads: 85000
            ),
            PluginRegistryEntry(
                pluginId: "com.example.rust-analyzer",
                name: "Rust Analyzer",
                version: "0.3.0",
                author: "Rust Tools",
                description: "Rust language support with rust-analyzer",
                category: .language,
                downloadURL: "https://plugins.lingcode.dev/rust-analyzer-0.3.0.zip",
                iconURL: nil,
                stars: 567,
                downloads: 42000
            )
        ]
        
        // Mark installed plugins
        for i in availablePlugins.indices {
            availablePlugins[i].isInstalled = installedPlugins.contains { $0.id == availablePlugins[i].pluginId }
        }
    }
    
    // MARK: - Configuration
    
    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(PluginConfig.self, from: data) else {
            return
        }
        
        // Apply enabled/disabled states
        for pluginId in config.disabledPlugins {
            if let index = installedPlugins.firstIndex(where: { $0.id == pluginId }) {
                installedPlugins[index].isEnabled = false
            }
        }
    }
    
    private func saveConfig() {
        let disabledPlugins = installedPlugins.filter { !$0.isEnabled }.map { $0.id }
        let config = PluginConfig(disabledPlugins: disabledPlugins)
        
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL)
    }
}

struct PluginConfig: Codable {
    let disabledPlugins: [String]
}

// MARK: - Built-in Plugins

/// Git status plugin - shows current branch and changes in status bar
final class GitStatusPlugin: LingCodePlugin {
    let id = "com.lingcode.git-status"
    let name = "Git Status"
    let version = "1.0.0"
    let author = "LingCode"
    let description = "Shows git branch and status in the status bar"
    let icon = "arrow.triangle.branch"
    let category: PluginCategory = .git
    
    private var statusBarHandle: StatusBarItemHandle?
    private var timer: Timer?
    
    func activate(context: PluginContext) async throws {
        // Add status bar item
        statusBarHandle = context.ui.addStatusBarItem(StatusBarItem(
            id: "git-status",
            text: "main",
            icon: "arrow.triangle.branch",
            tooltip: "Current git branch"
        ))
        
        // Update periodically
        await updateStatus(context: context)
    }
    
    func deactivate() async {
        timer?.invalidate()
        timer = nil
        await MainActor.run {
            statusBarHandle?.remove()
        }
    }
    
    @MainActor
    private func updateStatus(context: PluginContext) async {
        guard let workspace = context.fileSystem.workspaceRoot else { return }
        
        do {
            let result = try await context.terminal.execute("git branch --show-current", workingDirectory: workspace)
            let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !branch.isEmpty {
                statusBarHandle?.update(text: branch, icon: nil)
            }
        } catch {
            // Not a git repo or git not available
        }
    }
    
    func configurationView() -> AnyView? { nil }
}

/// Word count plugin - shows word/character count for current document
final class WordCountPlugin: LingCodePlugin {
    let id = "com.lingcode.word-count"
    let name = "Word Count"
    let version = "1.0.0"
    let author = "LingCode"
    let description = "Shows word and character count in status bar"
    let icon = "textformat.123"
    let category: PluginCategory = .tools
    
    private var statusBarHandle: StatusBarItemHandle?
    
    func activate(context: PluginContext) async throws {
        statusBarHandle = context.ui.addStatusBarItem(StatusBarItem(
            id: "word-count",
            text: "0 words",
            icon: "textformat.123",
            tooltip: "Word count"
        ))
        
        await updateCount(context: context)
    }
    
    func deactivate() async {
        await MainActor.run {
            statusBarHandle?.remove()
        }
    }
    
    @MainActor
    private func updateCount(context: PluginContext) async {
        guard let doc = context.editor.currentDocument else {
            statusBarHandle?.update(text: "0 words", icon: nil)
            return
        }
        
        let words = doc.content.split { $0.isWhitespace || $0.isNewline }.count
        let chars = doc.content.count
        
        statusBarHandle?.update(text: "\(words) words, \(chars) chars", icon: nil)
    }
    
    func configurationView() -> AnyView? { nil }
}

/// TODO highlighter plugin - registers TODO/FIXME as problems
final class TodoHighlighterPlugin: LingCodePlugin {
    let id = "com.lingcode.todo-highlighter"
    let name = "TODO Highlighter"
    let version = "1.0.0"
    let author = "LingCode"
    let description = "Highlights TODO, FIXME, and HACK comments"
    let icon = "checklist"
    let category: PluginCategory = .tools
    
    func activate(context: PluginContext) async throws {
        // Register a command to list all TODOs
        context.commands.registerCommand(PluginCommand(
            id: "todo-highlighter.listAll",
            title: "List All TODOs",
            category: "TODO",
            keybinding: "Cmd+Shift+T"
        ) {
            // Would search codebase for TODOs
            context.notifications.showInfo("Scanning for TODOs...")
        })
    }
    
    func deactivate() async {
        // Cleanup
    }
    
    func configurationView() -> AnyView? { nil }
}
