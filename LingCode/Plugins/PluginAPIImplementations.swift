//
//  PluginAPIImplementations.swift
//  LingCode
//
//  Implementations of the Plugin API protocols
//

import Foundation
import SwiftUI

// MARK: - Editor API Implementation

@MainActor
final class EditorAPIImpl: EditorAPI {
    private var codeActionProviders = [CodeActionProvider]()
    private var completionProviders = [CompletionProvider]()
    private var hoverProviders = [HoverProvider]()
    
    // Weak reference to editor - will be set via PluginContext injection
    weak var editorViewModel: EditorViewModel?
    
    var currentDocument: PluginDocument? {
        // Placeholder - will be connected when editor integration is complete
        // For now, return nil to allow compilation
        return nil
    }
    
    var openDocuments: [PluginDocument] {
        // Placeholder - will be connected when editor integration is complete
        return []
    }
    
    var selection: PluginSelection? {
        // Placeholder - will be connected when editor integration is complete
        return nil
    }
    
    func insertText(_ text: String) async {
        // Placeholder - will be connected when editor integration is complete
    }
    
    func replaceSelection(_ text: String) async {
        // Placeholder - will be connected when editor integration is complete
    }
    
    func openFile(at url: URL) async throws {
        // Placeholder - will be connected when editor integration is complete
    }
    
    func saveCurrentDocument() async throws {
        // Placeholder - will be connected when editor integration is complete
    }
    
    func registerCodeActionProvider(_ provider: CodeActionProvider) {
        codeActionProviders.append(provider)
    }
    
    func registerCompletionProvider(_ provider: CompletionProvider) {
        completionProviders.append(provider)
    }
    
    func registerHoverProvider(_ provider: HoverProvider) {
        hoverProviders.append(provider)
    }
}

// MARK: - File System API Implementation

final class FileSystemAPIImpl: FileSystemAPI {
    private var watchers = [UUID: DispatchSourceFileSystemObject]()
    
    var workspaceRoot: URL? {
        // Bridge to current workspace
        return nil // Placeholder - will be connected
    }
    
    func readFile(at url: URL) async throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    func writeFile(_ content: String, to url: URL) async throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func listDirectory(at url: URL) async throws -> [URL] {
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
    
    func watchFile(at url: URL, onChange: @escaping (URL) -> Void) -> FileWatcherHandle {
        let id = UUID()
        let fileDescriptor = open(url.path, O_EVTONLY)
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        
        source.setEventHandler {
            onChange(url)
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        watchers[id] = source
        
        return FileWatcherHandleImpl(id: id, owner: self)
    }
    
    func removeWatcher(_ id: UUID) {
        watchers[id]?.cancel()
        watchers.removeValue(forKey: id)
    }
}

final class FileWatcherHandleImpl: FileWatcherHandle {
    private let id: UUID
    private weak var owner: FileSystemAPIImpl?
    
    init(id: UUID, owner: FileSystemAPIImpl) {
        self.id = id
        self.owner = owner
    }
    
    func cancel() {
        owner?.removeWatcher(id)
    }
}

// MARK: - Terminal API Implementation

final class TerminalAPIImpl: TerminalAPI {
    private let terminalService = TerminalExecutionService.shared
    
    func execute(_ command: String, workingDirectory: URL?) async throws -> TerminalResult {
        let startTime = Date()
        let result = terminalService.executeSync(command, workingDirectory: workingDirectory)
        let duration = Date().timeIntervalSince(startTime)
        
        return TerminalResult(
            output: result.output,
            exitCode: result.exitCode,
            duration: duration
        )
    }
    
    func executeStreaming(
        _ command: String,
        workingDirectory: URL?,
        onOutput: @escaping (String) -> Void
    ) async throws -> Int32 {
        return await withCheckedContinuation { continuation in
            terminalService.execute(
                command,
                workingDirectory: workingDirectory,
                environment: nil,
                onOutput: { output in
                    onOutput(output)
                },
                onError: { error in
                    onOutput(error)
                },
                onComplete: { exitCode in
                    continuation.resume(returning: exitCode)
                }
            )
        }
    }
}

// MARK: - AI API Implementation

final class AIAPIImpl: AIAPI {
    private var registeredTools = [PluginAITool]()
    
    func chat(message: String, systemPrompt: String?) async throws -> String {
        var fullResponse = ""
        
        let stream = AIService.shared.streamMessage(
            message,
            context: nil,
            images: [],
            maxTokens: nil,
            systemPrompt: systemPrompt
        )
        
        for try await chunk in stream {
            fullResponse += chunk
        }
        
        return fullResponse
    }
    
    func chatStream(
        message: String,
        systemPrompt: String?,
        onChunk: @escaping (String) -> Void
    ) async throws {
        let stream = AIService.shared.streamMessage(
            message,
            context: nil,
            images: [],
            maxTokens: nil,
            systemPrompt: systemPrompt
        )
        
        for try await chunk in stream {
            onChunk(chunk)
        }
    }
    
    func registerTool(_ tool: PluginAITool) {
        registeredTools.append(tool)
        // Register with ToolExecutionService
    }
}

// MARK: - Notification API Implementation

@MainActor
final class NotificationAPIImpl: NotificationAPI {
    func showInfo(_ message: String) {
        // Use system notification or in-app notification
        NotificationCenter.default.post(
            name: .pluginNotification,
            object: nil,
            userInfo: ["message": message, "type": "info"]
        )
    }
    
    func showWarning(_ message: String) {
        NotificationCenter.default.post(
            name: .pluginNotification,
            object: nil,
            userInfo: ["message": message, "type": "warning"]
        )
    }
    
    func showError(_ message: String) {
        NotificationCenter.default.post(
            name: .pluginNotification,
            object: nil,
            userInfo: ["message": message, "type": "error"]
        )
    }
    
    func showWithActions(_ message: String, actions: [String]) async -> String? {
        // Show alert with actions and return selected action
        return await withCheckedContinuation { continuation in
            // In production, this would show an alert
            continuation.resume(returning: actions.first)
        }
    }
}

extension Notification.Name {
    static let pluginNotification = Notification.Name("pluginNotification")
}

// MARK: - Command API Implementation

@MainActor
final class CommandAPIImpl: CommandAPI {
    private(set) var commands = [PluginCommand]()
    
    func registerCommand(_ command: PluginCommand) {
        commands.append(command)
        // Register with command palette
    }
    
    func executeCommand(_ commandId: String, args: [String: Any]?) async throws {
        guard let command = commands.first(where: { $0.id == commandId }) else {
            throw PluginError.commandNotFound(commandId)
        }
        try await command.handler()
    }
}

// MARK: - Storage API Implementation

final class StorageAPIImpl: StorageAPI {
    private let pluginId: String
    private let storageURL: URL
    private var cache: [String: Data] = [:]
    
    init(pluginId: String) {
        self.pluginId = pluginId
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pluginsDir = appSupport.appendingPathComponent("LingCode/Plugins/\(pluginId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        self.storageURL = pluginsDir.appendingPathComponent("storage.json")
        
        loadCache()
    }
    
    func get<T: Codable>(_ key: String) -> T? {
        guard let data = cache[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    func set<T: Codable>(_ key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        cache[key] = data
        saveCache()
    }
    
    func remove(_ key: String) {
        cache.removeValue(forKey: key)
        saveCache()
    }
    
    func clear() {
        cache.removeAll()
        saveCache()
    }
    
    private func loadCache() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return
        }
        cache = decoded
    }
    
    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: storageURL)
    }
}

// MARK: - UI API Implementation

@MainActor
final class UIAPIImpl: UIAPI {
    private let pluginId: String
    private var statusBarItems = [String: StatusBarItem]()
    private var sidebarPanels = [SidebarPanel]()
    
    init(pluginId: String) {
        self.pluginId = pluginId
    }
    
    func addStatusBarItem(_ item: StatusBarItem) -> StatusBarItemHandle {
        statusBarItems[item.id] = item
        // Notify UI to update status bar
        NotificationCenter.default.post(
            name: .pluginStatusBarUpdated,
            object: nil,
            userInfo: ["pluginId": pluginId, "item": item]
        )
        return StatusBarItemHandleImpl(id: item.id, owner: self)
    }
    
    func registerSidebarPanel(_ panel: SidebarPanel) {
        sidebarPanels.append(panel)
        NotificationCenter.default.post(
            name: .pluginSidebarPanelRegistered,
            object: nil,
            userInfo: ["pluginId": pluginId, "panel": panel]
        )
    }
    
    func showQuickPick(items: [QuickPickItem], placeholder: String?) async -> QuickPickItem? {
        return await withCheckedContinuation { continuation in
            NotificationCenter.default.post(
                name: .pluginShowQuickPick,
                object: nil,
                userInfo: [
                    "items": items,
                    "placeholder": placeholder as Any,
                    "callback": { (item: QuickPickItem?) in
                        continuation.resume(returning: item)
                    }
                ]
            )
        }
    }
    
    func showInputBox(prompt: String, placeholder: String?, value: String?) async -> String? {
        return await withCheckedContinuation { continuation in
            NotificationCenter.default.post(
                name: .pluginShowInputBox,
                object: nil,
                userInfo: [
                    "prompt": prompt,
                    "placeholder": placeholder as Any,
                    "value": value as Any,
                    "callback": { (result: String?) in
                        continuation.resume(returning: result)
                    }
                ]
            )
        }
    }
    
    func updateStatusBarItem(id: String, text: String?, icon: String?) {
        guard var item = statusBarItems[id] else { return }
        item = StatusBarItem(
            id: id,
            text: text ?? item.text,
            icon: icon ?? item.icon,
            tooltip: item.tooltip,
            action: item.action
        )
        statusBarItems[id] = item
    }
    
    func removeStatusBarItem(id: String) {
        statusBarItems.removeValue(forKey: id)
    }
}

final class StatusBarItemHandleImpl: StatusBarItemHandle {
    private let id: String
    private weak var owner: UIAPIImpl?
    
    init(id: String, owner: UIAPIImpl) {
        self.id = id
        self.owner = owner
    }
    
    @MainActor
    func update(text: String?, icon: String?) {
        owner?.updateStatusBarItem(id: id, text: text, icon: icon)
    }
    
    @MainActor
    func remove() {
        owner?.removeStatusBarItem(id: id)
    }
}

extension Notification.Name {
    static let pluginStatusBarUpdated = Notification.Name("pluginStatusBarUpdated")
    static let pluginSidebarPanelRegistered = Notification.Name("pluginSidebarPanelRegistered")
    static let pluginShowQuickPick = Notification.Name("pluginShowQuickPick")
    static let pluginShowInputBox = Notification.Name("pluginShowInputBox")
}

// MARK: - Plugin Errors

enum PluginError: Error, LocalizedError {
    case commandNotFound(String)
    case activationFailed(String)
    case permissionDenied(PluginPermission)
    case invalidManifest(String)
    case dependencyMissing(String)
    
    var errorDescription: String? {
        switch self {
        case .commandNotFound(let id):
            return "Command not found: \(id)"
        case .activationFailed(let reason):
            return "Plugin activation failed: \(reason)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission.rawValue)"
        case .invalidManifest(let reason):
            return "Invalid plugin manifest: \(reason)"
        case .dependencyMissing(let dep):
            return "Missing dependency: \(dep)"
        }
    }
}
