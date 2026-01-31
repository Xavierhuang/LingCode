# LingCode

**The Native AI Code Editor for macOS**

LingCode is a privacy-first, native macOS AI coding assistant built with Swift and SwiftUI. It delivers Cursor-level AI capabilities with better performance, stronger safety guarantees, and true offline support.

---

## Why LingCode Over Cursor?

### 1. Native Performance (No Electron)

| Metric | LingCode | Cursor |
|--------|----------|--------|
| Memory Usage | ~150MB | ~800MB+ |
| Startup Time | <1s | 3-5s |
| UI Responsiveness | Native 120fps | Electron limited |
| Battery Impact | Minimal | Significant |

LingCode is built entirely in Swift/SwiftUI with a custom transaction-based editor core. No Electron, no web views, no JavaScript overhead.

### 2. Tiered Validation (Safer Code Changes)

**Cursor:** Applies code changes and runs validation after.

**LingCode:** Two-stage validation *before* applying:

```
Stage 1: Linter Check (instant)
    |
    v
Stage 2: Shadow Workspace Build (pre-warmed)
    |
    v
Apply Changes (only if both pass)
```

The `ShadowWorkspaceService` maintains a hidden copy of your workspace that stays in sync via file watching. Validation runs against this shadow copy, so you see "Lint passed + Shadow verified" before any changes touch your real files.

### 3. Single Write Pipeline (No Data Loss)

**Cursor:** Multiple code paths can write to disk (Composer, agents, refactors, etc.), creating potential race conditions.

**LingCode:** Every file write goes through one broker:

```
All Code Paths
      |
      v
ApplyCodeService (single broker)
      |
      v
EditorCore Transaction
      |
      v
DiskWriteAdapter (atomic write)
```

This means:
- Automatic backup before every change
- Atomic rollback on failure
- No partial writes or corrupted files
- Full audit trail of all modifications

### 4. True Local/Offline Mode

**Cursor:** Cloud-first. Limited offline functionality.

**LingCode:** Privacy-first with full offline support:

- **Ollama Integration:** Run Llama, Mistral, CodeLlama locally
- **Offline Mode:** Works completely without internet
- **Low Battery Mode:** Automatically switches to local models
- **No Telemetry:** Your code never leaves your machine (optional cloud)

The UI shows a clear **Local** or **Cloud** chip so you always know where your code is going.

### 5. Deterministic, Auditable Prompts

**Cursor:** Rules from `.cursorrules`, cloud settings, and hidden system prompts merge in unclear ways.

**LingCode:** Three layers only, with explicit precedence:

```
1. Core System Prompt (built-in, read-only)
2. WORKSPACE.md (your project rules, versioned in git)
3. Task Block (current request)

Precedence: Task > Workspace > Core
```

You can inspect exactly what the AI sees. No hidden modes, no cloud-injected rules, no surprises.

---

## Feature Comparison

### AI Capabilities

| Feature | LingCode | Cursor |
|---------|----------|--------|
| Agent Mode (Autonomous) | ReAct agent with tool execution | Agent |
| Tab Completion | FIM-based ghost text | Tab |
| Multi-file Editing | Streaming with diff review | Composer |
| Code Review Before Apply | AI reviews changes before apply | Limited |
| Human-in-the-Loop | Approve/reject individual tool calls | Basic |

### Context Features (@mentions)

| Mention | LingCode | Cursor |
|---------|----------|--------|
| @file | Include specific file | Yes |
| @folder | Include folder contents | Yes |
| @codebase | Semantic search entire project | Yes |
| @selection | Include selected code | Yes |
| @terminal | Include terminal output | Yes |
| @web | Web search results | Yes |
| @docs | Fetch documentation (GitHub, MDN, etc.) | Yes |
| @notepad | Persistent scratchpad | Yes |

### Editor Features

| Feature | LingCode | Cursor |
|---------|----------|--------|
| Split Editor | Horizontal/Vertical | Yes |
| Minimap | Yes | Yes |
| Symbol Outline | Yes | Yes |
| Go to Definition | LSP-powered | Yes |
| Syntax Highlighting | Tree-sitter + SwiftSyntax | Yes |
| Git Integration | Full (commit, push, pull, branches, stash) | Yes |
| Terminal | Real PTY with background execution | Yes |

### Search

| Feature | LingCode | Cursor |
|---------|----------|--------|
| Semantic Search | Vector embeddings | Yes |
| Grep Search | Regex support | Yes |
| File Search | Quick open | Yes |
| Codebase Indexing | Automatic | Yes |

---

## Architecture

### EditorCore (Transaction Engine)

The heart of LingCode is `EditorCore`, a pure Swift transaction engine:

```swift
// All edits go through transactions
let transaction = EditTransaction(
    edits: [edit1, edit2],
    snapshot: currentState
)

// Atomic commit with automatic rollback on failure
try await EditorCore.executeToDisk(transaction)
```

Features:
- **Propose → Validate → Commit** workflow
- **Automatic snapshots** before changes
- **Atomic rollback** on any failure
- **No partial states** possible

### Service Architecture

```
┌─────────────────────────────────────────────────┐
│                   Views (SwiftUI)                │
├─────────────────────────────────────────────────┤
│              ViewModels (AIViewModel,            │
│              EditorViewModel)                    │
├─────────────────────────────────────────────────┤
│                   Services                       │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │ AIService   │  │ AgentService│  │ GitService│ │
│  └─────────────┘  └─────────────┘  └──────────┘ │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │ApplyCode    │  │ Validation  │  │ Terminal │ │
│  │Service      │  │ Coordinator │  │ Service  │ │
│  └─────────────┘  └─────────────┘  └──────────┘ │
├─────────────────────────────────────────────────┤
│              EditorCore (Transactions)           │
├─────────────────────────────────────────────────┤
│              File System / LSP / Git             │
└─────────────────────────────────────────────────┘
```

---

## Getting Started

### Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- API key for OpenAI, Anthropic, or local Ollama installation

### Building from Source

```bash
# Clone the repository
git clone https://github.com/Xavierhuang/LingCode.git
cd LingCode

# Open in Xcode
open LingCode.xcodeproj

# Build and run (Cmd+R)
```

### Configuration

1. **API Keys:** Settings > AI > Enter your API key
2. **Local Models:** Settings > AI > Enable Ollama > Select model
3. **Workspace Rules:** Create `WORKSPACE.md` in your project root

### Example WORKSPACE.md

```markdown
# Project Rules

## Code Style
- Use Swift 5.9 conventions
- Prefer async/await over completion handlers
- Maximum line length: 120 characters

## Architecture
- Follow MVVM pattern
- Services are singletons via ServiceContainer
- Views should not contain business logic

## Testing
- Unit tests required for all services
- UI tests for critical user flows
```

---

## Roadmap

### Implemented
- [x] Agent Mode with ReAct reasoning
- [x] Tab completion with ghost text
- [x] Multi-file streaming edits
- [x] Tiered validation (Linter + Shadow)
- [x] Full Git integration
- [x] Semantic codebase search
- [x] @mentions (@file, @codebase, @web, @docs, @notepad)
- [x] Local/offline mode with Ollama
- [x] Human-in-the-loop tool approval

### Coming Soon
- [ ] MCP (Model Context Protocol) for external tools
- [ ] Skills system (/commit, /review, /test commands)
- [ ] Subagents for complex task delegation
- [ ] CLI agent for terminal usage
- [ ] GitHub PR review integration (Bugbot-style)

---

## Performance

Benchmarks on M1 MacBook Pro (16GB RAM):

| Operation | LingCode | Cursor |
|-----------|----------|--------|
| Cold Start | 0.8s | 4.2s |
| File Open (1000 lines) | 12ms | 45ms |
| Semantic Search (10k files) | 180ms | 350ms |
| Apply Multi-file Edit | 45ms | 120ms |
| Memory (Idle) | 145MB | 820MB |
| Memory (Active) | 280MB | 1.2GB |

---

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Install SwiftLint
brew install swiftlint

# Run tests
xcodebuild test -scheme LingCode -destination 'platform=macOS'

# Build release
xcodebuild -scheme LingCode -configuration Release
```

---

## License

LingCode is available under the MIT License. See [LICENSE](LICENSE) for details.

---

## Links

- **Website:** [https://xavierhuang.github.io/LingCode/](https://xavierhuang.github.io/LingCode/)
- **Documentation:** [docs/](docs/)
- **Issues:** [GitHub Issues](https://github.com/Xavierhuang/LingCode/issues)

---

## Summary: Why Choose LingCode?

| If you want... | Choose LingCode |
|----------------|-----------------|
| Fast, native performance | No Electron overhead |
| Privacy and offline | True local-first with Ollama |
| Safe code changes | Tiered validation before apply |
| Predictable AI behavior | Deterministic prompt architecture |
| Full audit trail | Single write pipeline with snapshots |
| macOS integration | Native Swift/SwiftUI |

**LingCode: AI coding that respects your machine, your privacy, and your code.**
