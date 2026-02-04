//
//  PluginProtocol.swift
//  LingCode
//
//  Native plugin system for LingCode extensibility.
//  Plugins can add commands, tools, themes, language support, and more.
//

import Foundation
import SwiftUI

// MARK: - Plugin Protocol

/// Main protocol that all LingCode plugins must implement
public protocol LingCodePlugin: AnyObject {
    /// Unique identifier for the plugin (reverse domain notation recommended)
    var id: String { get }
    
    /// Display name shown in UI
    var name: String { get }
    
    /// Plugin version (semantic versioning)
    var version: String { get }
    
    /// Plugin author/organization
    var author: String { get }
    
    /// Short description of what the plugin does
    var description: String { get }
    
    /// Plugin icon (SF Symbol name)
    var icon: String { get }
    
    /// Plugin category for organization
    var category: PluginCategory { get }
    
    /// Minimum LingCode version required
    var minimumAppVersion: String { get }
    
    /// Called when the plugin is activated
    func activate(context: PluginContext) async throws
    
    /// Called when the plugin is deactivated
    func deactivate() async
    
    /// Plugin configuration view (optional)
    @MainActor
    func configurationView() -> AnyView?
}

// Default implementations
public extension LingCodePlugin {
    var icon: String { "puzzlepiece.extension" }
    var category: PluginCategory { .other }
    var minimumAppVersion: String { "1.0.0" }
    
    @MainActor
    func configurationView() -> AnyView? { nil }
}

// MARK: - Plugin Category

public enum PluginCategory: String, CaseIterable, Codable {
    case language = "Language"
    case theme = "Theme"
    case git = "Git"
    case formatter = "Formatter"
    case linter = "Linter"
    case ai = "AI"
    case tools = "Tools"
    case integration = "Integration"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .language: return "chevron.left.forwardslash.chevron.right"
        case .theme: return "paintpalette"
        case .git: return "arrow.triangle.branch"
        case .formatter: return "text.alignleft"
        case .linter: return "exclamationmark.triangle"
        case .ai: return "brain"
        case .tools: return "wrench.and.screwdriver"
        case .integration: return "link"
        case .other: return "puzzlepiece"
        }
    }
}

// MARK: - Plugin Context

/// Context provided to plugins for interacting with LingCode
@MainActor
public final class PluginContext {
    /// Access to the editor
    public let editor: EditorAPI
    
    /// Access to the file system
    public let fileSystem: FileSystemAPI
    
    /// Access to the terminal
    public let terminal: TerminalAPI
    
    /// Access to AI services
    public let ai: AIAPI
    
    /// Access to notifications
    public let notifications: NotificationAPI
    
    /// Access to commands
    public let commands: CommandAPI
    
    /// Access to storage (plugin-specific persistent storage)
    public let storage: StorageAPI
    
    /// Access to UI (status bar, panels, etc.)
    public let ui: UIAPI
    
    /// Plugin's own ID (for scoped operations)
    public let pluginId: String
    
    init(pluginId: String) {
        self.pluginId = pluginId
        self.editor = EditorAPIImpl()
        self.fileSystem = FileSystemAPIImpl()
        self.terminal = TerminalAPIImpl()
        self.ai = AIAPIImpl()
        self.notifications = NotificationAPIImpl()
        self.commands = CommandAPIImpl()
        self.storage = StorageAPIImpl(pluginId: pluginId)
        self.ui = UIAPIImpl(pluginId: pluginId)
    }
}

// MARK: - Editor API

public protocol EditorAPI {
    /// Get the current document
    var currentDocument: PluginDocument? { get }
    
    /// Get all open documents
    var openDocuments: [PluginDocument] { get }
    
    /// Get the current selection
    var selection: PluginSelection? { get }
    
    /// Insert text at cursor position
    func insertText(_ text: String) async
    
    /// Replace the current selection
    func replaceSelection(_ text: String) async
    
    /// Open a file
    func openFile(at url: URL) async throws
    
    /// Save the current document
    func saveCurrentDocument() async throws
    
    /// Register a code action provider
    func registerCodeActionProvider(_ provider: CodeActionProvider)
    
    /// Register a completion provider
    func registerCompletionProvider(_ provider: CompletionProvider)
    
    /// Register a hover provider
    func registerHoverProvider(_ provider: HoverProvider)
}

public struct PluginDocument {
    public let url: URL?
    public let content: String
    public let language: String?
    public let isDirty: Bool
}

public struct PluginSelection {
    public let text: String
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
}

// MARK: - File System API

public protocol FileSystemAPI {
    /// Read a file
    func readFile(at url: URL) async throws -> String
    
    /// Write a file
    func writeFile(_ content: String, to url: URL) async throws
    
    /// Check if a file exists
    func fileExists(at url: URL) -> Bool
    
    /// List directory contents
    func listDirectory(at url: URL) async throws -> [URL]
    
    /// Watch for file changes
    func watchFile(at url: URL, onChange: @escaping (URL) -> Void) -> FileWatcherHandle
    
    /// Get the workspace root
    var workspaceRoot: URL? { get }
}

public protocol FileWatcherHandle {
    func cancel()
}

// MARK: - Terminal API

public protocol TerminalAPI {
    /// Execute a command and return the result
    func execute(_ command: String, workingDirectory: URL?) async throws -> TerminalResult
    
    /// Execute a command with streaming output
    func executeStreaming(
        _ command: String,
        workingDirectory: URL?,
        onOutput: @escaping (String) -> Void
    ) async throws -> Int32
}

public struct TerminalResult {
    public let output: String
    public let exitCode: Int32
    public let duration: TimeInterval
}

// MARK: - AI API

public protocol AIAPI {
    /// Send a message to the AI and get a response
    func chat(message: String, systemPrompt: String?) async throws -> String
    
    /// Stream a response from the AI
    func chatStream(
        message: String,
        systemPrompt: String?,
        onChunk: @escaping (String) -> Void
    ) async throws
    
    /// Register a custom AI tool
    func registerTool(_ tool: PluginAITool)
}

public struct PluginAITool {
    public let name: String
    public let description: String
    public let parameters: [PluginToolParameter]
    public let handler: ([String: Any]) async throws -> String
    
    public init(
        name: String,
        description: String,
        parameters: [PluginToolParameter],
        handler: @escaping ([String: Any]) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.handler = handler
    }
}

public struct PluginToolParameter {
    public let name: String
    public let type: String
    public let description: String
    public let required: Bool
    
    public init(name: String, type: String, description: String, required: Bool = true) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

// MARK: - Notification API

public protocol NotificationAPI {
    /// Show an info notification
    func showInfo(_ message: String)
    
    /// Show a warning notification
    func showWarning(_ message: String)
    
    /// Show an error notification
    func showError(_ message: String)
    
    /// Show a notification with actions
    func showWithActions(_ message: String, actions: [String]) async -> String?
}

// MARK: - Command API

public protocol CommandAPI {
    /// Register a command that can be invoked from command palette
    func registerCommand(_ command: PluginCommand)
    
    /// Execute a built-in command
    func executeCommand(_ commandId: String, args: [String: Any]?) async throws
    
    /// Get all registered commands
    var commands: [PluginCommand] { get }
}

public struct PluginCommand {
    public let id: String
    public let title: String
    public let category: String?
    public let keybinding: String?
    public let handler: () async throws -> Void
    
    public init(
        id: String,
        title: String,
        category: String? = nil,
        keybinding: String? = nil,
        handler: @escaping () async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.keybinding = keybinding
        self.handler = handler
    }
}

// MARK: - Storage API

public protocol StorageAPI {
    /// Get a value from plugin storage
    func get<T: Codable>(_ key: String) -> T?
    
    /// Set a value in plugin storage
    func set<T: Codable>(_ key: String, value: T)
    
    /// Remove a value from plugin storage
    func remove(_ key: String)
    
    /// Clear all plugin storage
    func clear()
}

// MARK: - UI API

public protocol UIAPI {
    /// Add an item to the status bar
    func addStatusBarItem(_ item: StatusBarItem) -> StatusBarItemHandle
    
    /// Register a sidebar panel
    func registerSidebarPanel(_ panel: SidebarPanel)
    
    /// Show a quick pick (selection dialog)
    func showQuickPick(items: [QuickPickItem], placeholder: String?) async -> QuickPickItem?
    
    /// Show an input dialog
    func showInputBox(prompt: String, placeholder: String?, value: String?) async -> String?
}

public struct StatusBarItem {
    public let id: String
    public let text: String
    public let icon: String?
    public let tooltip: String?
    public let action: (() -> Void)?
    
    public init(id: String, text: String, icon: String? = nil, tooltip: String? = nil, action: (() -> Void)? = nil) {
        self.id = id
        self.text = text
        self.icon = icon
        self.tooltip = tooltip
        self.action = action
    }
}

public protocol StatusBarItemHandle {
    func update(text: String?, icon: String?)
    func remove()
}

public struct SidebarPanel {
    public let id: String
    public let title: String
    public let icon: String
    public let view: () -> AnyView
    
    public init(id: String, title: String, icon: String, view: @escaping () -> AnyView) {
        self.id = id
        self.title = title
        self.icon = icon
        self.view = view
    }
}

public struct QuickPickItem: Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let icon: String?
    
    public init(id: String, label: String, description: String? = nil, icon: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.icon = icon
    }
}

// MARK: - Provider Protocols

public protocol CodeActionProvider {
    func provideCodeActions(document: PluginDocument, selection: PluginSelection) async -> [CodeAction]
}

public struct CodeAction {
    public let title: String
    public let kind: CodeActionKind
    public let handler: () async throws -> Void
    
    public init(title: String, kind: CodeActionKind, handler: @escaping () async throws -> Void) {
        self.title = title
        self.kind = kind
        self.handler = handler
    }
}

public enum CodeActionKind {
    case quickFix
    case refactor
    case source
}

public protocol CompletionProvider {
    func provideCompletions(document: PluginDocument, position: (line: Int, column: Int)) async -> [CompletionItem]
}

public struct CompletionItem {
    public let label: String
    public let kind: CompletionItemKind
    public let detail: String?
    public let insertText: String
    
    public init(label: String, kind: CompletionItemKind, detail: String? = nil, insertText: String? = nil) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.insertText = insertText ?? label
    }
}

public enum CompletionItemKind {
    case text, method, function, constructor, field, variable
    case `class`, interface, module, property, unit, value
    case `enum`, keyword, snippet, color, file, reference
}

public protocol HoverProvider {
    func provideHover(document: PluginDocument, position: (line: Int, column: Int)) async -> HoverInfo?
}

public struct HoverInfo {
    public let contents: String
    public let range: PluginSelection?
    
    public init(contents: String, range: PluginSelection? = nil) {
        self.contents = contents
        self.range = range
    }
}

// MARK: - Plugin Manifest

/// Manifest file structure for plugin packages
public struct PluginManifest: Codable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let category: PluginCategory
    public let icon: String?
    public let minimumAppVersion: String
    public let main: String  // Entry point Swift file
    public let dependencies: [String]?
    public let permissions: [PluginPermission]?
    public let contributes: PluginContributions?
}

public enum PluginPermission: String, Codable {
    case fileSystem = "fileSystem"
    case terminal = "terminal"
    case network = "network"
    case ai = "ai"
    case clipboard = "clipboard"
}

public struct PluginContributions: Codable {
    public let commands: [CommandContribution]?
    public let languages: [LanguageContribution]?
    public let themes: [ThemeContribution]?
    public let keybindings: [KeybindingContribution]?
}

public struct CommandContribution: Codable {
    public let id: String
    public let title: String
    public let category: String?
    public let icon: String?
}

public struct LanguageContribution: Codable {
    public let id: String
    public let name: String
    public let extensions: [String]
    public let icon: String?
}

public struct ThemeContribution: Codable {
    public let id: String
    public let name: String
    public let type: String  // "light" or "dark"
    public let path: String
}

public struct KeybindingContribution: Codable {
    public let command: String
    public let key: String
    public let when: String?
}
