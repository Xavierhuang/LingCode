# LingCode

A powerful, AI-powered code editor for macOS that rivals and exceeds Cursor's capabilities. Built with SwiftUI and designed for modern software development.

## Features

### 🤖 AI-Powered Development
- **Multiple AI Providers**: Support for OpenAI (GPT-4) and Anthropic (Claude Sonnet, Haiku, Opus)
- **Streaming Responses**: Real-time AI code generation with streaming support
- **Cursor-Style Interface**: Familiar Cursor-like experience with enhanced features
- **Agent Mode**: Autonomous AI agent that can plan and execute complex tasks
- **Code Review**: AI-powered code review with suggestions and improvements
- **Documentation Generation**: Automatic code documentation generation
- **Refactoring Assistant**: AI-assisted code refactoring

### 💻 Code Editor
- **Syntax Highlighting**: Full syntax highlighting for 50+ languages
- **Code Folding**: Collapsible code blocks for better navigation
- **Bracket Matching**: Visual bracket matching and auto-completion
- **Line Numbers**: Customizable line number display
- **Minimap**: Code overview with minimap navigation
- **Multiple Cursors**: Multi-cursor editing support
- **Ghost Text**: AI-powered inline suggestions
- **Autocomplete**: Intelligent code autocomplete

### 🔍 Search & Navigation
- **Semantic Search**: AI-powered semantic code search
- **Global Search**: Fast full-text search across the codebase
- **Go to Definition**: Jump to symbol definitions
- **Symbol Outline**: Navigate code structure with symbol outline
- **Related Files**: Find related files based on dependencies
- **File Tree**: Hierarchical file tree with search

### 🎨 User Interface
- **Modern SwiftUI Design**: Beautiful, native macOS interface
- **Dark/Light Themes**: Multiple theme options
- **Split Editor**: Multi-pane editor support
- **Tab Management**: Tabbed interface for multiple files
- **Activity Bar**: Quick access to features
- **Command Palette**: Quick command execution
- **Status Bar**: Project status and information

### 🛠️ Developer Tools
- **Integrated Terminal**: Built-in terminal with PTY support
- **Terminal Execution**: Run AI-generated terminal commands directly
- **Git Integration**: Full Git support with visual diff
- **Git Status**: Real-time Git status display
- **File Operations**: Create, delete, rename files and folders
- **Project Generation**: AI-powered project scaffolding

### 🔐 Security & Privacy
- **Local-Only Mode**: Keep code local with optional encryption
- **Secure Key Storage**: API keys stored in macOS Keychain
- **Code Validation**: Prevent unintended code changes
- **Audit Logging**: Track all AI-generated changes

### 📊 Advanced Features
- **Usage Tracking**: Monitor API usage and costs
- **Performance Optimization**: Smart caching and request queuing
- **Graphite Integration**: Automatic PR stacking for large changes
- **Image Context**: Attach images to AI requests
- **Context Management**: Smart context selection for AI requests
- **Mention System**: @ mention files, folders, and code sections

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later (for building from source)
- API key from OpenAI or Anthropic

## Installation

### From Source

1. Clone the repository:
```bash
git clone git@github.com:Xavierhuang/LingCode.git
cd LingCode
```

2. Open the project in Xcode:
```bash
open LingCode.xcodeproj
```

3. Build and run the project (⌘R)

### API Key Setup

1. Get your API key:
   - **OpenAI**: https://platform.openai.com/api-keys
   - **Anthropic**: https://console.anthropic.com/settings/keys

2. On first launch, enter your API key in the welcome screen
3. Or configure it later in Settings (⌘,)

**Note for App Store Review**: See [APP_STORE_REVIEW_GUIDE.md](APP_STORE_REVIEW_GUIDE.md) for instructions on providing a sample API key for Apple reviewers.

## Usage

### Basic Usage

1. **Open a Project**: File → Open Folder (⌘O)
2. **Start AI Chat**: Click the AI icon in the activity bar or press ⌘⇧L
3. **Ask Questions**: Type your question and press Enter
4. **Apply Changes**: Review AI suggestions and click "Apply" to accept

### AI Features

- **Chat Mode**: General AI assistance and code questions
- **Cursor Mode**: Cursor-style streaming code generation
- **Composer Mode**: Multi-file editing interface
- **Agent Mode**: Autonomous task execution
- **Inline Edit**: Edit code directly with AI suggestions

### Terminal Commands

When the AI suggests terminal commands:
1. Commands are automatically extracted and displayed
2. Click "Run" on individual commands
3. Or click "Run All" to execute multiple commands
4. View output in real-time

### Keyboard Shortcuts

- `⌘⇧L`: Open AI Chat
- `⌘P`: Quick Open File
- `⌘⇧P`: Command Palette
- `⌘B`: Toggle Sidebar
- `⌘K ⌘S`: Keyboard Shortcuts
- `⌘,`: Settings

## Architecture

### Services
- `AIService`: Core AI integration (OpenAI, Anthropic)
- `TerminalExecutionService`: Terminal command execution
- `FileService`: File system operations
- `GitService`: Git integration
- `CodeValidationService`: Code safety validation
- `UsageTrackingService`: API usage monitoring
- `PerformanceService`: Performance optimization
- `ImageContextService`: Image attachment handling

### ViewModels
- `AIViewModel`: AI conversation state management
- `EditorViewModel`: Editor state and operations

### Views
- `AIChatView`: Main AI chat interface
- `CursorStreamingView`: Cursor-style streaming interface
- `ComposerView`: Multi-file editing interface
- `EditorView`: Code editor component
- `TerminalView`: Terminal interface

## Development

### Project Structure
```
LingCode/
├── LingCode/
│   ├── Components/      # Reusable UI components
│   ├── Models/          # Data models
│   ├── Services/        # Business logic services
│   ├── Views/           # SwiftUI views
│   ├── ViewModels/      # View models
│   └── Utils/           # Utilities and helpers
└── LingCode.xcodeproj/  # Xcode project
```

### Building

1. Open `LingCode.xcodeproj` in Xcode
2. Select your target device (My Mac)
3. Build (⌘B) or Run (⌘R)

### Testing

Run tests with ⌘U in Xcode.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by Cursor and VS Code
- Built with SwiftUI and Combine
- Uses OpenAI and Anthropic APIs

## Support

For issues, questions, or feature requests, please contact us:

- **Email**: [hhuangweijia@gmail.com](mailto:hhuangweijia@gmail.com)
- **Phone**: [(646) 567-1456](tel:+16465671456)
- **GitHub Issues**: [Open an issue](https://github.com/Xavierhuang/LingCode/issues)
- **Website**: [https://xavierhuang.github.io/LingCode/](https://xavierhuang.github.io/LingCode/)

---

**Note**: This app requires disabling App Sandbox for full terminal functionality. This means it cannot be distributed through the Mac App Store, but is suitable for direct distribution.

