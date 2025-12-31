# LingCode - Feature Comparison with Cursor

## Overview

LingCode is a **native macOS code editor** that matches and exceeds Cursor's capabilities. Here's what makes LingCode **better than Cursor**:

### Why LingCode is Better

| Advantage | Cursor | LingCode |
|-----------|--------|----------|
| **Native Performance** | Electron (1GB+ RAM) | **Native Swift (~200MB RAM)** |
| **Offline AI** | Cloud only | **Local models via Ollama** |
| **Privacy** | Code sent to cloud | **Local option - code stays on device** |
| **Rules Files** | .cursorrules | **.lingcode - Project-specific AI rules** |
| **Codebase Indexing** | Yes | **Yes - With smart symbol index** |
| **AI Code Review** | Basic | **Comprehensive scoring & analysis** |
| **AI Documentation** | No | **Auto-generate docs & READMEs** |
| **Semantic Search** | Basic | **Meaning-based code search** |
| **macOS Integration** | Limited | **Full native integration** |

---

---

## Editor Features

| Feature | Cursor | LingCode |
|---------|--------|----------|
| Split View Editor | Yes | **Yes** - Horizontal/Vertical split |
| Minimap | Yes | **Yes** - With syntax-aware coloring |
| Code Folding | Yes | **Yes** - Braces, brackets, comments, imports, regions |
| Bracket Matching | Yes | **Yes** - Rainbow brackets with highlighting |
| Multi-cursor | Yes | **Yes** - Via standard macOS text editing |
| Line Numbers | Yes | **Yes** |
| Syntax Highlighting | Yes | **Yes** - Swift, Python, JS/TS, HTML, CSS, JSON, Markdown |
| Tab Management | Yes | **Yes** |
| Word Wrap | Yes | **Yes** |

### New Editor Features in LingCode

```
/LingCode/Views/SplitEditorView.swift - Split view editor
/LingCode/Views/MinimapView.swift - Code minimap
/LingCode/Services/CodeFoldingService.swift - Code folding
/LingCode/Services/BracketMatchingService.swift - Bracket matching
```

---

## AI Features

| Feature | Cursor | LingCode |
|---------|--------|----------|
| AI Chat | Yes | **Yes** - With @ mentions |
| Inline AI Edit | Yes | **Yes** - Cmd+K |
| Ghost Text Suggestions | Yes | **Yes** - Tab to accept |
| AI Code Generation | Yes | **Yes** - Auto-apply like Cursor |
| AI Thinking Process | Yes | **Yes** - Step-by-step view |
| Context Mentions | Yes | **Yes** - @file, @folder, @codebase, @selection, @web |
| AI Code Review | Limited | **Yes** - Dedicated review panel |
| AI Documentation | No | **Yes** - Auto-generate docs |
| AI Refactoring | Yes | **Yes** - Multiple suggestions |
| Terminal Execution | Yes | **Yes** - AI runs commands |
| Agent Mode | Yes | **Yes** - Autonomous multi-step tasks |
| Apply Code Button | Yes | **Yes** - One-click apply changes |
| Image Support | Yes | **Yes** - Paste images for context |
| Web Search | Yes | **Yes** - Real web search via @web |
| **Project Rules** | .cursorrules | **.lingcode - Project-specific AI instructions** |
| **Codebase Indexing** | Yes | **Yes - Smart symbol index** |
| **Fluid Auto-Apply** | Yes | **Yes - Files applied as generated** |
| **Inline Diff View** | Yes | **Yes - Cursor-style green/red diff** |

### Unique AI Features in LingCode

1. **AI Code Review** (`/LingCode/Services/AICodeReviewService.swift`)
   - Comprehensive code analysis
   - Security, performance, best practices
   - Score-based assessment
   - Actionable suggestions

2. **AI Documentation Generator** (`/LingCode/Services/AIDocumentationService.swift`)
   - Generate function docs
   - Full file documentation
   - README generation
   - Multiple doc styles (DocC, JSDoc, Javadoc, etc.)

3. **Context Mentions** (`/LingCode/Views/ContextMentionView.swift`)
   - @file - Include specific file
   - @folder - Include folder contents
   - @codebase - Search codebase
   - @selection - Include selected code
   - @terminal - Include terminal output
   - @web - **Real web search** (DuckDuckGo API)

4. **Project Rules** (`/LingCode/Services/LingCodeRulesService.swift`)
   - `.lingcode` files (like .cursorrules)
   - Global rules support
   - Project-specific AI instructions
   - Auto-loaded for AI context

5. **Smart Codebase Indexing** (`/LingCode/Services/CodebaseIndexService.swift`)
   - Symbol indexing (classes, functions, etc.)
   - Import tracking
   - File summaries for AI context
   - Fast symbol search
   - Relevant file suggestions

6. **Fluid AI Experience** (`/LingCode/Views/FluidAIView.swift`)
   - Auto-apply changes like Cursor
   - Files created as AI generates them
   - Undo support with original content restoration
   - Minimal, clean interface

7. **Cursor-Style Diff** (`/LingCode/Views/CursorStyleDiffView.swift`)
   - Inline diff with green/red highlighting
   - Side-by-side view option
   - Accept/Reject buttons
   - File type icons

---

## Navigation

| Feature | Cursor | LingCode |
|---------|--------|----------|
| Go to Definition | Yes | **Yes** |
| Find References | Yes | **Yes** |
| Peek Definition | Yes | **Yes** |
| Symbol Outline | Yes | **Yes** |
| Breadcrumbs | Yes | **Yes** |
| Quick Open | Yes | **Yes** - Cmd+P |
| Command Palette | Yes | **Yes** - Cmd+Shift+P |
| Go to Line | Yes | **Yes** |
| Recent Files | Yes | **Yes** |
| Global Search | Yes | **Yes** - With semantic search |

### Navigation Files

```
/LingCode/Services/DefinitionService.swift - Go to Definition
/LingCode/Views/DefinitionPopupView.swift - Definition popup
/LingCode/Views/PeekDefinitionView.swift - Peek definition
/LingCode/Views/SymbolOutlineView.swift - Symbol outline
/LingCode/Views/QuickOpenView.swift - Quick file open
```

---

## Git Integration

| Feature | Cursor | LingCode |
|---------|--------|----------|
| Git Status | Yes | **Yes** |
| Commit | Yes | **Yes** |
| Push/Pull | Yes | **Yes** |
| Branch Management | Yes | **Yes** |
| Diff View | Yes | **Yes** - Side-by-side + inline |
| File Status Indicators | Yes | **Yes** |

### Git Files

```
/LingCode/Services/GitService.swift - Git operations
/LingCode/Views/GitPanelView.swift - Full Git UI
/LingCode/Views/DiffView.swift - Diff visualization
```

---

## UI/UX

| Feature | Cursor | LingCode |
|---------|--------|----------|
| Activity Bar | Yes | **Yes** |
| Bottom Panel | Yes | **Yes** - Problems, Output, Terminal, Debug |
| Status Bar | Yes | **Yes** |
| Welcome Screen | Yes | **Yes** |
| Settings UI | Yes | **Yes** |
| Theme Support | Yes | **Yes** - Light/Dark auto |
| Keyboard Shortcuts | Yes | **Yes** - Customizable |

### UI Files

```
/LingCode/Views/ActivityBarView.swift - Activity bar
/LingCode/Views/ProblemsView.swift - Problems panel
/LingCode/Views/StatusBarView.swift - Status bar
/LingCode/Views/SettingsView.swift - Settings
/LingCode/Services/KeyBindingsService.swift - Custom keybindings
```

---

## Unique LingCode Features (Not in Cursor)

### 1. AI Code Review Panel
- Get comprehensive AI review of your code
- Security, performance, maintainability analysis
- Score-based assessment (0-100)
- Category-based issue grouping
- Actionable fix suggestions

### 2. AI Documentation Generator
- Auto-generate function documentation
- Full file documentation
- README.md generation
- Support for multiple doc styles

### 3. Semantic Search
- Search code by meaning, not just text
- AI-powered relevance scoring
- Understands code context

### 4. Related Files Detection
- Automatic dependency tracking
- Import/export analysis
- Smart context for AI

### 5. Context Manager
- Intelligent context compression
- Token optimization
- Priority-based file inclusion

### 6. Inline Diff with Accept/Reject
- Visual diff view
- Accept or reject AI changes
- Side-by-side comparison

---

## Newly Added Cursor Features

### 1. Terminal Command Execution (`/LingCode/Services/TerminalExecutionService.swift`)
- AI can run terminal commands for you
- Automatic command parsing from AI responses
- Real-time output streaming
- Command history tracking
- Support for npm, pip, cargo, swift, go, etc.
- Destructive command detection

### 2. Apply Code Button (`/LingCode/Services/ApplyCodeService.swift`)
- One-click apply for AI-generated code
- Preview changes before applying
- Select which files to apply
- Diff view for each change
- Batch apply multiple files

### 3. Agent Mode (`/LingCode/Services/AgentService.swift`)
- Autonomous multi-step task completion
- AI creates and executes plans
- Can generate code, run commands, search web
- Step-by-step progress tracking
- Cancel anytime
- Example: "Create a React todo app" → AI does everything

### 4. Web Search (`/LingCode/Services/WebSearchService.swift`)
- Real web search via @web mention
- Uses DuckDuckGo API (no key required)
- Google Custom Search support (optional)
- Fetches and summarizes results
- Adds web context to AI prompts

### 5. Image Support (`/LingCode/Services/ImageContextService.swift`)
- Paste images from clipboard
- Drag & drop images
- Screenshot capture
- Image resizing and optimization
- Base64 encoding for AI APIs
- Support for Anthropic and OpenAI vision models

### 6. Project Generation (`/LingCode/Services/ProjectGeneratorService.swift`)
- Generate entire projects from description
- Multiple file creation
- Directory structure generation
- Template-based projects
- Progress tracking

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New File | Cmd+N |
| Quick Open | Cmd+P |
| Command Palette | Cmd+Shift+P |
| Save | Cmd+S |
| Find | Cmd+F |
| Find in Files | Cmd+Shift+F |
| Go to Definition | Cmd+D |
| Find References | Cmd+Shift+R |
| AI Edit | Cmd+K |
| Toggle Panel | Cmd+J |
| Toggle Terminal | Cmd+` |
| Split Right | Cmd+\ |
| Split Down | Cmd+Shift+\ |
| Settings | Cmd+, |

---

## Architecture

```
LingCode/
|-- Components/
|   |-- CodeEditor.swift          # Native NSTextView editor
|   |-- LineNumbersView.swift     # Line numbers
|
|-- Models/
|   |-- AIConversation.swift      # AI chat models
|   |-- AIThinkingStep.swift      # AI thinking process
|   |-- Document.swift            # Document model
|   |-- EditorState.swift         # Editor state
|
|-- Services/
|   |-- AIService.swift           # AI API integration
|   |-- AIStepParser.swift        # Parse AI responses
|   |-- AICodeReviewService.swift # Code review
|   |-- AIDocumentationService.swift # Doc generation
|   |-- ActionExecutor.swift      # Execute AI actions
|   |-- AutocompleteService.swift # Autocomplete
|   |-- BracketMatchingService.swift # Bracket matching
|   |-- CodeFoldingService.swift  # Code folding
|   |-- CodeGeneratorService.swift # Code generation
|   |-- ContextManager.swift      # Context management
|   |-- DefinitionService.swift   # Go to definition
|   |-- FileDependencyService.swift # Dependency tracking
|   |-- FileService.swift         # File operations
|   |-- GitService.swift          # Git integration
|   |-- KeyBindingsService.swift  # Keyboard shortcuts
|   |-- RefactoringService.swift  # Refactoring
|   |-- SemanticSearchService.swift # Semantic search
|   |-- SyntaxHighlighter.swift   # Syntax highlighting
|   |-- ThemeService.swift        # Themes
|
|-- ViewModels/
|   |-- AIViewModel.swift         # AI state management
|   |-- EditorViewModel.swift     # Editor state
|
|-- Views/
|   |-- AIChatView.swift          # AI chat interface
|   |-- ActivityBarView.swift     # Activity bar
|   |-- AutocompletePopupView.swift # Autocomplete
|   |-- BreadcrumbView.swift      # Breadcrumbs
|   |-- CodeReviewView.swift      # Code review UI
|   |-- CommandPaletteView.swift  # Command palette
|   |-- ContextMentionView.swift  # @ mentions
|   |-- DefinitionPopupView.swift # Definition popup
|   |-- DiffView.swift            # Diff visualization
|   |-- EditorView.swift          # Main editor
|   |-- FileTreeView.swift        # File tree
|   |-- GitPanelView.swift        # Git panel
|   |-- GlobalSearchView.swift    # Global search
|   |-- GoToLineView.swift        # Go to line
|   |-- InlineAIEditView.swift    # Inline AI edit
|   |-- InlineSuggestionView.swift # Ghost text
|   |-- MinimapView.swift         # Minimap
|   |-- PeekDefinitionView.swift  # Peek definition
|   |-- ProblemsView.swift        # Problems panel
|   |-- QuickOpenView.swift       # Quick open
|   |-- RefactoringView.swift     # Refactoring UI
|   |-- RelatedFilesView.swift    # Related files
|   |-- SearchView.swift          # Search
|   |-- SettingsView.swift        # Settings
|   |-- SnippetsView.swift        # Snippets
|   |-- SplitEditorView.swift     # Split view
|   |-- StatusBarView.swift       # Status bar
|   |-- SymbolOutlineView.swift   # Symbol outline
|   |-- TabBarView.swift          # Tab bar
|   |-- TerminalView.swift        # Terminal
|   |-- ThinkingProcessView.swift # AI thinking
|   |-- WelcomeView.swift         # Welcome screen
```

---

## Future Enhancements

1. **Language Server Protocol (LSP) Support**
   - Better type inference
   - More accurate completions
   - Cross-file analysis

2. **Debug Support**
   - Breakpoints
   - Variable inspection
   - Call stack

3. **Extension System**
   - Plugin API
   - Theme marketplace
   - Language packs

4. **Collaboration**
   - Real-time editing
   - Code sharing
   - Team AI context

5. **Performance**
   - Virtual scrolling
   - Lazy loading
   - Background indexing

---

## Summary

LingCode now matches Cursor's core functionality and adds several unique features:

- **AI Code Review** - Comprehensive code analysis
- **AI Documentation** - Auto-generate docs
- **Semantic Search** - Search by meaning
- **Smart Context** - Automatic file relationships
- **@ Mentions** - Flexible context control

The codebase is clean, modular, and ready for future enhancements.
