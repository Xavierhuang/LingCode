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
    
    // Activity Bar
    @State private var selectedActivity: ActivityItem = .files
    
    // Split Editor
    @State private var splitDirection: SplitDirection = .none
    
    // AI Panel Toggle (Cursor-style)
    @State private var showAIPanel: Bool = true
    @State private var aiPanelWidth: CGFloat = 320
    
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
            
            Divider()
            
            // Sidebar content
            sidebarContent
                .frame(width: 250)
            
            Divider()
            
            // Main content area
            VStack(spacing: 0) {
                BreadcrumbView(filePath: viewModel.editorState.activeDocument?.filePath)
                
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
                            HStack(spacing: 0) {
                                SplitEditorView(viewModel: viewModel, splitDirection: $splitDirection)
                                
                                // Minimap
                                if let document = viewModel.editorState.activeDocument {
                                    Divider()
                                    MinimapView(
                                        content: document.content,
                                        language: document.language,
                                        visibleRange: nil,
                                        onScrollTo: { _ in }
                                    )
                                    .frame(width: 80)
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
                        }
                    }
                }
                
                // Bottom Panel
                if showBottomPanel {
                    Divider()
                    bottomPanelContent
                        .frame(height: bottomPanelHeight)
                }
                
                StatusBarView(
                    editorState: viewModel.editorState,
                    fontSize: viewModel.fontSize
                )
            }
        }
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
                
                Button(action: {
                    showQuickOpen = true
                }) {
                    Label("Quick Open", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("p", modifiers: .command)
                
                Button(action: {
                    viewModel.saveCurrentDocument()
                }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(viewModel.editorState.activeDocument == nil)
                
                Button(action: {
                    showSearch.toggle()
                }) {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(viewModel.editorState.activeDocument == nil)
                
                Button(action: {
                    showGlobalSearch.toggle()
                }) {
                    Label("Search in Files", systemImage: "doc.text.magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button(action: {
                    goToDefinition()
                }) {
                    Label("Go to Definition", systemImage: "arrow.right.square")
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(viewModel.editorState.activeDocument == nil)
                
                Button(action: {
                    findReferences()
                }) {
                    Label("Find References", systemImage: "link")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.editorState.activeDocument == nil)
                
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
                
                Button(action: {
                    showRefactoring.toggle()
                }) {
                    Label("Refactor", systemImage: "wand.and.stars")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(viewModel.editorState.activeDocument == nil)
                
                Button(action: {
                    showBottomPanel.toggle()
                }) {
                    Label("Panel", systemImage: showBottomPanel ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset.fill")
                }
                .keyboardShortcut("j", modifiers: .command)
                
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
                .help(showAIPanel ? "Hide AI Panel" : "Show AI Panel")
                
                Button(action: {
                    showSettings.toggle()
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
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
    
    @ViewBuilder
    var sidebarContent: some View {
        switch selectedActivity {
        case .files, .ai:
            // File explorer - also show when AI is selected (AI goes to right panel)
            VStack(spacing: 0) {
                HStack {
                    Text("Explorer")
                        .font(.headline)
                        .padding(.horizontal)
                    Spacer()
                    Button(action: {
                        viewModel.openFolder()
                    }) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

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
                        VStack {
                            Spacer()
                            Text("Open a folder to browse files")
                                .foregroundColor(.secondary)
                            Button(action: {
                                print("Open Folder button clicked")
                                viewModel.openFolder()
                            }) {
                                Text("Open Folder")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            Spacer()
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                }
            }
            
        case .search:
            GlobalSearchView(viewModel: viewModel, isPresented: .constant(true))
            
        case .git:
            GitPanelView(viewModel: viewModel)
            
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
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(selectedBottomTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                
                Spacer()
                
                Button(action: { showBottomPanel = false }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
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
    
    var body: some View {
        ZStack {
            Divider()
            
            Rectangle()
                .fill(Color.clear)
                .frame(width: isVertical ? 4 : nil, height: isVertical ? nil : 4)
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
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .background(isDragging ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
