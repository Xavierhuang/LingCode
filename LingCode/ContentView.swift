//
//  ContentView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = EditorViewModel()
    @EnvironmentObject var themeService: ThemeService
    @State private var showSearch: Bool = false
    @State private var showSettings: Bool = false
    @State private var showGoToLine: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var showGlobalSearch: Bool = false
    @State private var showInlineEdit: Bool = false
    @State private var showTerminal: Bool = false
    @State private var showWelcome: Bool = false
    @State private var showRefactoring: Bool = false
    @State private var showQuickOpen: Bool = false
    @State private var showDefinition: Bool = false
    @State private var showReferences: Bool = false
    @State private var showQuickActions: Bool = false
    
    // Activity Bar
    @State private var selectedActivity: ActivityItem = .ai
    
    // Split Editor
    @State private var splitDirection: SplitDirection = .none
    
    // AI Panel Toggle (Cursor-style)
    @State private var showAIPanel: Bool = true
    @State private var aiPanelWidth: CGFloat = 400  // Increased from 320 for wider chat view
    
    // Bottom Panel
    @State private var showBottomPanel: Bool = false
    @State private var bottomPanelHeight: CGFloat = 200
    @State private var selectedBottomTab: BottomPanelTab = .problems
    
    // Definition/References
    @State private var definitions: [Definition] = []
    @State private var references: [Reference] = []
    @State private var currentSymbol: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // Activity Bar
            ActivityBarView(selectedItem: $selectedActivity)
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(width: 1)
            
            // Sidebar content
            sidebarContent
                .frame(width: 250)
                .background(DesignSystem.Colors.sidebarBackground)
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(width: 1)
            
            // Main content area
            VStack(spacing: 0) {
                BreadcrumbView(
                    filePath: viewModel.editorState.activeDocument?.filePath,
                    content: viewModel.editorState.activeDocument?.content,
                    language: viewModel.editorState.activeDocument?.language,
                    cursorLine: cursorLine(from: viewModel.editorState.cursorPosition, in: viewModel.editorState.activeDocument?.content ?? "")
                )
                
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Editor area
                        VStack(spacing: 0) {
                            TabBarView(
                                editorState: viewModel.editorState,
                                onClose: { documentId in
                                    viewModel.closeDocument(documentId)
                                }
                            )
                            
                            // Main editor with optional minimap
                            Group {
                                if viewModel.editorState.activeDocument == nil {
                                    // Empty state - only show when no document
                                    emptyStateView
                                } else {
                                    // Editor content - only show when document exists
                                    HStack(spacing: 0) {
                                        SplitEditorView(viewModel: viewModel, splitDirection: $splitDirection)
                                        
                                        // Minimap
                                        if let document = viewModel.editorState.activeDocument {
                                            Rectangle()
                                                .fill(DesignSystem.Colors.borderSubtle)
                                                .frame(width: 1)
                                            
                                            MinimapView(
                                                content: document.content,
                                                language: document.language,
                                                visibleRange: nil,
                                                onScrollTo: { _ in }
                                            )
                                            .frame(width: 80)
                                            .background(DesignSystem.Colors.secondaryBackground)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: showAIPanel ? geometry.size.width - aiPanelWidth : geometry.size.width)
                        
                        // Resizable divider
                        if showAIPanel {
                            ResizableDivider(
                                isVertical: true,
                                onResize: { delta in
                                    let newWidth = aiPanelWidth - delta
                                    aiPanelWidth = max(200, min(geometry.size.width - 300, newWidth))
                                }
                            )
                            
                            // Right sidebar - AI Chat
                            rightSidebarContent
                                .frame(width: aiPanelWidth)
                                .background(DesignSystem.Colors.primaryBackground)
                        }
                    }
                }
                
                // Bottom Panel
                if showBottomPanel {
                    Rectangle()
                        .fill(DesignSystem.Colors.borderSubtle)
                        .frame(height: 1)
                    bottomPanelContent
                        .frame(height: bottomPanelHeight)
                }
                
                StatusBarView(
                    editorState: viewModel.editorState,
                    fontSize: viewModel.fontSize,
                    editorViewModel: viewModel
                )
            }
            .background(DesignSystem.Colors.primaryBackground)
        }
        .background(DesignSystem.Colors.primaryBackground)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Split view controls
                Menu {
                    Button(action: { splitDirection = .none }) {
                        Label("No Split", systemImage: "rectangle")
                    }
                    Button(action: { splitDirection = .horizontal }) {
                        Label("Split Right", systemImage: "rectangle.split.2x1")
                    }
                    Button(action: { splitDirection = .vertical }) {
                        Label("Split Down", systemImage: "rectangle.split.1x2")
                    }
                } label: {
                    Image(systemName: splitDirection == .none ? "rectangle" : "rectangle.split.2x1")
                }
                .help("Split Editor")
                
                Divider()
                
                Button(action: {
                    viewModel.openFolder()
                }) {
                    Label("Open Folder", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Open a folder as project")
                
                Button(action: {
                    viewModel.createNewDocument()
                }) {
                    Label("New", systemImage: "doc")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Create New File")
                
                Button(action: {
                    showQuickOpen = true
                }) {
                    Label("Quick Open", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("p", modifiers: .command)
                .help("Quick Open File (⌘P)")
                
                Button(action: {
                    viewModel.saveCurrentDocument()
                }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(viewModel.editorState.activeDocument == nil)
                .help("Save File (⌘S)")
                
                Button(action: {
                    showSearch.toggle()
                }) {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(viewModel.editorState.activeDocument == nil)
                .help("Find in File (⌘F)")
                
                Button(action: {
                    showGlobalSearch.toggle()
                }) {
                    Label("Search in Files", systemImage: "doc.text.magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("Search in Files (⌘⇧F)")
                
                Button(action: {
                    goToDefinition()
                }) {
                    Label("Go to Definition", systemImage: "arrow.right.square")
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(viewModel.editorState.activeDocument == nil)
                .help("Go to Definition (⌘D)")
                
                Button(action: {
                    findReferences()
                }) {
                    Label("Find References", systemImage: "link")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.editorState.activeDocument == nil)
                .help("Find References (⌘⇧R)")
                
                Button(action: {
                    // Post notification for inline edit in editor
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TriggerInlineEdit"),
                        object: nil
                    )
                }) {
                    Label("AI Edit", systemImage: "sparkles")
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(viewModel.editorState.activeDocument == nil)
                .help("AI Edit (⌘K)")
                
                Button(action: {
                    showRefactoring.toggle()
                }) {
                    Label("Refactor", systemImage: "wand.and.stars")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(viewModel.editorState.activeDocument == nil)
                .help("Refactor Code (⌘⇧E)")
                
                Button(action: {
                    showBottomPanel.toggle()
                }) {
                    Label("Panel", systemImage: showBottomPanel ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset.fill")
                }
                .keyboardShortcut("j", modifiers: .command)
                .help("Toggle Bottom Panel (⌘J)")
                
                Divider()
                
                // AI Panel Toggle (Cursor-style)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAIPanel.toggle()
                    }
                }) {
                    Label("AI", systemImage: showAIPanel ? "sidebar.trailing" : "sidebar.trailing")
                        .foregroundColor(showAIPanel ? .accentColor : .secondary)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .help(showAIPanel ? "Hide AI Panel (⌘⇧L)" : "Show AI Panel (⌘⇧L)")
                
                Button(action: {
                    showSettings.toggle()
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(viewModel: viewModel, isPresented: $showSearch)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel, isPresented: $showSettings)
        }
        .sheet(isPresented: $showGoToLine) {
            if let document = viewModel.editorState.activeDocument {
                GoToLineView(
                    isPresented: $showGoToLine,
                    maxLines: document.content.components(separatedBy: .newlines).count,
                    onGoToLine: { line in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("GoToLine"),
                            object: nil,
                            userInfo: ["line": line]
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                isPresented: $showCommandPalette,
                commands: buildCommands()
            )
        }
        .sheet(isPresented: $showQuickOpen) {
            QuickOpenView(isPresented: $showQuickOpen, viewModel: viewModel)
        }
        .sheet(isPresented: $showDefinition) {
            DefinitionPopupView(
                symbol: currentSymbol,
                definitions: definitions,
                onSelect: { def in
                    viewModel.openFile(at: def.file)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GoToLine"),
                        object: nil,
                        userInfo: ["line": def.line]
                    )
                    showDefinition = false
                },
                onClose: { showDefinition = false }
            )
        }
        .sheet(isPresented: $showReferences) {
            ReferencesPopupView(
                symbol: currentSymbol,
                references: references,
                projectURL: viewModel.rootFolderURL,
                onSelect: { ref in
                    viewModel.openFile(at: ref.file)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GoToLine"),
                        object: nil,
                        userInfo: ["line": ref.line]
                    )
                    showReferences = false
                },
                onClose: { showReferences = false }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCommandPalette"))) { _ in
            showCommandPalette = true
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView(viewModel: viewModel, isPresented: $showGlobalSearch)
        }
        .sheet(isPresented: $showQuickActions) {
            QuickActionsView(
                viewModel: viewModel.aiViewModel,
                editorViewModel: viewModel
            )
        }
        .sheet(isPresented: $showInlineEdit) {
            InlineAIEditView(isPresented: $showInlineEdit, viewModel: viewModel)
        }
        .sheet(isPresented: $showTerminal) {
            PTYTerminalViewWrapper(isVisible: $showTerminal, workingDirectory: viewModel.rootFolderURL)
                .frame(width: 800, height: 400)
        }
        .sheet(isPresented: $showRefactoring) {
            RefactoringView(isPresented: $showRefactoring, viewModel: viewModel)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView(viewModel: viewModel, isPresented: $showWelcome)
        }
        .onAppear {
            APISetupHelper.setupDefaultAPIKeyIfNeeded()
            
            if !viewModel.aiViewModel.hasAPIKey() {
                showWelcome = true
            }
        }
        .frame(minWidth: EditorConstants.minWindowWidth, minHeight: EditorConstants.minWindowHeight)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No file open")
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Open a file to start editing")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            HStack(spacing: DesignSystem.Spacing.md) {
                Button(action: {
                    viewModel.openFolder()
                }) {
                    Label("Open Folder", systemImage: "folder")
                        .font(DesignSystem.Typography.body)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    viewModel.createNewDocument()
                }) {
                    Label("New File", systemImage: "doc.badge.plus")
                        .font(DesignSystem.Typography.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.primaryBackground)
    }
    
    @ViewBuilder
    var sidebarContent: some View {
        switch selectedActivity {
        case .files, .ai:
            // File explorer - also show when AI is selected (AI goes to right panel)
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Explorer")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                    Spacer()
                    Button(action: {
                        viewModel.openFolder()
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .help("Open Folder")
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.secondaryBackground)
                
                Rectangle()
                    .fill(DesignSystem.Colors.borderSubtle)
                    .frame(height: 1)

                ZStack {
                    // Always show FileTreeView so it doesn't need to be recreated
                    FileTreeView(
                        rootURL: Binding(
                            get: { viewModel.rootFolderURL },
                            set: { viewModel.rootFolderURL = $0 }
                        ),
                        refreshTrigger: $viewModel.fileTreeRefreshTrigger,
                        onFileSelect: { url in
                            viewModel.openFile(at: url)
                            RecentFilesService.shared.addRecentFile(url)
                        }
                    )

                    // Show empty state overlay when no folder is open
                    if viewModel.rootFolderURL == nil {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            Spacer()
                            
                            Image(systemName: "folder")
                                .font(.system(size: 48))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            
                            VStack(spacing: DesignSystem.Spacing.xs) {
                                Text("Open a folder to browse files")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                
                                Text("Select a project folder to get started")
                                    .font(DesignSystem.Typography.caption1)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            
                            Button(action: {
                                viewModel.openFolder()
                            }) {
                                Label("Open Folder", systemImage: "folder.badge.plus")
                                    .font(DesignSystem.Typography.body)
                                    .padding(.horizontal, DesignSystem.Spacing.xl)
                                    .padding(.vertical, DesignSystem.Spacing.md)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DesignSystem.Colors.sidebarBackground)
                    }
                }
            }
            
        case .search:
            GlobalSearchView(viewModel: viewModel, isPresented: .constant(true))
            
        case .git:
            GitPanelView(editorViewModel: viewModel)
            
        case .outline:
            SymbolOutlineView(viewModel: viewModel)
            
        case .settings:
            SettingsView(viewModel: viewModel, isPresented: .constant(true))
        }
    }
    
    @ViewBuilder
    var rightSidebarContent: some View {
        // AI chat always on the right when AI activity is selected
        AIChatView(viewModel: viewModel.aiViewModel, editorViewModel: viewModel)
    }
    
    @ViewBuilder
    var bottomPanelContent: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(BottomPanelTab.allCases, id: \.self) { tab in
                    Button(action: { selectedBottomTab = tab }) {
                        Text(tab.rawValue)
                            .font(DesignSystem.Typography.caption1)
                            .foregroundColor(selectedBottomTab == tab ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(
                        Group {
                            if selectedBottomTab == tab {
                                DesignSystem.Colors.sidebarSelected
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                
                Spacer()
                
                Button(action: { showBottomPanel = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, DesignSystem.Spacing.md)
                .help("Close Panel")
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.secondaryBackground)
            
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 1)
            
            // Panel content
            switch selectedBottomTab {
            case .problems:
                ProblemsView(viewModel: viewModel)
            case .output:
                ScrollView {
                    Text("Output panel")
                        .foregroundColor(.secondary)
                }
            case .terminal:
                PTYTerminalViewWrapper(isVisible: $showBottomPanel, workingDirectory: viewModel.rootFolderURL)
            case .debug:
                ScrollView {
                    Text("Debug console")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func buildCommands() -> [Command] {
        return [
            Command(title: "New File", subtitle: "Create a new file", icon: "doc", keywords: ["new", "file", "create"]) {
                viewModel.createNewDocument()
            },
            Command(title: "Quick Open", subtitle: "Open file by name", icon: "magnifyingglass", keywords: ["open", "quick", "file"]) {
                showQuickOpen = true
            },
            Command(title: "Open Folder", subtitle: "Open a folder", icon: "folder.fill", keywords: ["open", "folder", "project"]) {
                viewModel.openFolder()
            },
            Command(title: "Save", subtitle: "Save current file", icon: "square.and.arrow.down", keywords: ["save"]) {
                viewModel.saveCurrentDocument()
            },
            Command(title: "Find", subtitle: "Find in file", icon: "magnifyingglass", keywords: ["find", "search"]) {
                showSearch = true
            },
            Command(title: "Find in Files", subtitle: "Search across all files", icon: "doc.text.magnifyingglass", keywords: ["find", "search", "global"]) {
                showGlobalSearch = true
            },
            Command(title: "Go to Line", subtitle: "Jump to line number", icon: "number", keywords: ["goto", "line", "jump"]) {
                showGoToLine = true
            },
            Command(title: "Go to Definition", subtitle: "Navigate to symbol definition", icon: "arrow.right.square", keywords: ["definition", "goto", "navigate"]) {
                goToDefinition()
            },
            Command(title: "Find References", subtitle: "Find all references to symbol", icon: "link", keywords: ["references", "find", "usages"]) {
                findReferences()
            },
            Command(title: "AI Edit", subtitle: "Edit code with AI", icon: "sparkles", keywords: ["ai", "edit", "generate"]) {
                showInlineEdit = true
            },
            Command(title: "Quick Actions", subtitle: "Fast AI operations", icon: "bolt.fill", keywords: ["quick", "actions", "ai", "explain", "refactor", "test"]) {
                showQuickActions = true
            },
            Command(title: "Refactor Code", subtitle: "AI-powered refactoring suggestions", icon: "wand.and.stars", keywords: ["refactor", "refactoring", "improve", "optimize"]) {
                showRefactoring = true
            },
            Command(title: "Split Right", subtitle: "Split editor horizontally", icon: "rectangle.split.2x1", keywords: ["split", "horizontal"]) {
                splitDirection = .horizontal
            },
            Command(title: "Split Down", subtitle: "Split editor vertically", icon: "rectangle.split.1x2", keywords: ["split", "vertical"]) {
                splitDirection = .vertical
            },
            Command(title: "Close Split", subtitle: "Close split view", icon: "rectangle", keywords: ["close", "split"]) {
                splitDirection = .none
            },
            Command(title: "Toggle Panel", subtitle: "Show/hide bottom panel", icon: "rectangle.bottomthird.inset.filled", keywords: ["panel", "toggle", "problems", "terminal"]) {
                showBottomPanel.toggle()
            },
            Command(title: "Toggle Terminal", subtitle: "Show/hide terminal", icon: "terminal", keywords: ["terminal", "shell", "command"]) {
                selectedBottomTab = .terminal
                showBottomPanel = true
            },
            Command(title: "Settings", subtitle: "Open settings", icon: "gearshape", keywords: ["settings", "preferences", "config"]) {
                showSettings = true
            }
        ]
    }
    
    private func goToDefinition() {
        guard let document = viewModel.editorState.activeDocument,
              let projectURL = viewModel.rootFolderURL else { return }
        
        let position = viewModel.editorState.cursorPosition
        if let symbol = DefinitionService.shared.getSymbolAtPosition(
            in: document.content,
            at: position
        ) {
            currentSymbol = symbol
            definitions = DefinitionService.shared.findDefinition(
                for: symbol,
                in: projectURL,
                currentFile: document.filePath,
                language: document.language
            )
            
            if definitions.count == 1 {
                // Go directly
                let def = definitions[0]
                viewModel.openFile(at: def.file)
                NotificationCenter.default.post(
                    name: NSNotification.Name("GoToLine"),
                    object: nil,
                    userInfo: ["line": def.line]
                )
            } else {
                showDefinition = true
            }
        }
    }
    
    private func findReferences() {
        guard let document = viewModel.editorState.activeDocument,
              let projectURL = viewModel.rootFolderURL else { return }
        
        let position = viewModel.editorState.cursorPosition
        if let symbol = DefinitionService.shared.getSymbolAtPosition(
            in: document.content,
            at: position
        ) {
            currentSymbol = symbol
            references = DefinitionService.shared.findReferences(
                for: symbol,
                in: projectURL
            )
            showReferences = true
        }
    }
    
    private func cursorLine(from position: Int, in content: String) -> Int? {
        guard position > 0, !content.isEmpty else { return 1 }
        let prefix = content.prefix(min(position, content.count))
        return prefix.components(separatedBy: .newlines).count
    }
}

enum BottomPanelTab: String, CaseIterable {
    case problems = "Problems"
    case output = "Output"
    case terminal = "Terminal"
    case debug = "Debug Console"
}

// MARK: - Resizable Divider

struct ResizableDivider: View {
    let isVertical: Bool
    let onResize: (CGFloat) -> Void
    
    @State private var isDragging = false
    @State private var lastTranslation: CGFloat = 0
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
            
            Rectangle()
                .fill(Color.clear)
                .frame(width: isVertical ? 8 : nil, height: isVertical ? nil : 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                lastTranslation = isVertical ? value.translation.width : value.translation.height
                            } else {
                                let currentTranslation = isVertical ? value.translation.width : value.translation.height
                                let delta = currentTranslation - lastTranslation
                                onResize(delta)
                                lastTranslation = currentTranslation
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            lastTranslation = 0
                        }
                )
        }
        .onHover { hovering in
            isHovered = hovering
            // Use the correct cursor type based on orientation
            // Direct cursor setting without Task wrapper for immediate response
            if hovering {
                if isVertical {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        .background(
            Group {
                if isDragging {
                    DesignSystem.Colors.accent.opacity(0.2)
                } else if isHovered {
                    DesignSystem.Colors.accent.opacity(0.1)
                } else {
                    Color.clear
                }
            }
        )
        // Ensure the entire divider area is interactive
        .frame(maxWidth: isVertical ? 8 : .infinity, maxHeight: isVertical ? .infinity : 8)
    }
}
