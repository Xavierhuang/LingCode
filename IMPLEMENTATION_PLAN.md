# Implementation Plan: Top 5 Differentiators

## 1. Multi-File Context Awareness

### Goal
Automatically track and include related files when using AI features.

### Implementation Steps

#### Step 1: Create File Dependency Tracker
```swift
// Services/FileDependencyService.swift
class FileDependencyService {
    static let shared = FileDependencyService()
    
    func findRelatedFiles(for fileURL: URL, in projectURL: URL) -> [URL] {
        // Parse imports/includes
        // Find files that import this file
        // Find files this file imports
        // Return related files
    }
    
    func buildDependencyGraph(projectURL: URL) -> DependencyGraph {
        // Build complete dependency graph
    }
}
```

#### Step 2: Enhance AI Context
```swift
// ViewModels/AIViewModel.swift - Add method
func sendMessageWithContext(context: String? = nil, includeRelatedFiles: Bool = true) {
    var fullContext = context ?? ""
    
    if includeRelatedFiles, let activeFile = editorViewModel.editorState.activeDocument?.filePath {
        let relatedFiles = FileDependencyService.shared.findRelatedFiles(
            for: activeFile,
            in: editorViewModel.rootFolderURL ?? activeFile.deletingLastPathComponent()
        )
        
        for relatedFile in relatedFiles.prefix(5) {
            if let content = try? String(contentsOf: relatedFile) {
                fullContext += "\n\n--- Related file: \(relatedFile.lastPathComponent) ---\n\(content)"
            }
        }
    }
    
    sendMessage(context: fullContext)
}
```

#### Step 3: Add Related Files Sidebar
```swift
// Views/RelatedFilesView.swift
struct RelatedFilesView: View {
    let fileURL: URL
    let projectURL: URL
    @State private var relatedFiles: [URL] = []
    
    var body: some View {
        List(relatedFiles, id: \.self) { file in
            Button(action: { /* Open file */ }) {
                Text(file.lastPathComponent)
            }
        }
    }
}
```

## 2. Better AI Context Management

### Goal
Smart context selection and compression for large codebases.

### Implementation Steps

#### Step 1: Create Context Manager
```swift
// Services/ContextManager.swift
class ContextManager {
    func getRelevantContext(
        for query: String,
        in files: [URL],
        maxTokens: Int = 8000
    ) -> String {
        // Use semantic search to find most relevant code
        // Compress context intelligently
        // Return optimized context
    }
    
    func compressCode(_ code: String) -> String {
        // Remove comments
        // Remove whitespace
        // Keep structure
    }
}
```

#### Step 2: Add Context Templates
```swift
// Models/ContextTemplate.swift
struct ContextTemplate {
    let name: String
    let description: String
    let filePatterns: [String]
    let includePatterns: [String]
}

// Predefined templates:
// - "Full Stack Feature" (frontend + backend + tests)
// - "API Endpoint" (route + handler + model + tests)
// - "Component" (component + styles + tests)
```

## 3. Smart Refactoring Tools

### Goal
AI-powered refactoring with preview and safety checks.

### Implementation Steps

#### Step 1: Create Refactoring Service
```swift
// Services/RefactoringService.swift
class RefactoringService {
    func suggestRefactoring(
        for code: String,
        type: RefactoringType
    ) async throws -> RefactoringResult {
        // AI analyzes code
        // Suggests refactoring
        // Returns preview
    }
    
    func applyRefactoring(
        _ result: RefactoringResult,
        in files: [URL]
    ) async throws {
        // Apply changes
        // Verify syntax
        // Update all affected files
    }
}

enum RefactoringType {
    case extractMethod
    case extractVariable
    case inline
    case rename
    case simplify
    case optimize
}
```

#### Step 2: Add Refactoring UI
```swift
// Views/RefactoringView.swift
struct RefactoringView: View {
    @State private var suggestions: [RefactoringSuggestion] = []
    @State private var preview: RefactoringPreview?
    
    var body: some View {
        // Show refactoring suggestions
        // Preview changes
        // Apply with confirmation
    }
}
```

## 4. Advanced Search & Navigation

### Goal
Semantic code search and intelligent navigation.

### Implementation Steps

#### Step 1: Create Semantic Search
```swift
// Services/SemanticSearchService.swift
class SemanticSearchService {
    func search(
        query: String,
        in projectURL: URL,
        type: SearchType
    ) async -> [SearchResult] {
        // Use AI to understand query intent
        // Search by meaning, not just text
        // Rank results by relevance
    }
}

enum SearchType {
    case text
    case semantic
    case symbol
    case reference
}
```

#### Step 2: Enhance Global Search
```swift
// Views/GlobalSearchView.swift - Enhance existing
// Add semantic search option
// Add filters (file type, location, etc.)
// Add result preview
// Add "find similar code" feature
```

## 5. Code Generation from Natural Language

### Goal
Generate complete features from descriptions.

### Implementation Steps

#### Step 1: Create Code Generator
```swift
// Services/CodeGeneratorService.swift
class CodeGeneratorService {
    func generateFeature(
        description: String,
        projectType: String,
        existingFiles: [URL]
    ) async throws -> GeneratedFeature {
        // AI generates complete feature
        // Creates multiple files if needed
        // Includes tests and documentation
    }
    
    func generateTests(
        for code: String,
        language: String
    ) async throws -> String {
        // Generate comprehensive tests
    }
}
```

#### Step 2: Add Feature Generator UI
```swift
// Views/FeatureGeneratorView.swift
struct FeatureGeneratorView: View {
    @State private var description: String = ""
    @State private var generatedFiles: [GeneratedFile] = []
    
    var body: some View {
        VStack {
            TextField("Describe the feature...", text: $description)
            Button("Generate") {
                // Generate feature
            }
            // Show generated files
            // Preview and accept/reject
        }
    }
}
```

## Quick Implementation Checklist

### Week 1: Foundation
- [ ] Create FileDependencyService
- [ ] Create ContextManager
- [ ] Add related files tracking to EditorViewModel

### Week 2: AI Enhancements
- [ ] Enhance AIViewModel with multi-file context
- [ ] Add context templates
- [ ] Implement context compression

### Week 3: Search & Navigation
- [ ] Create SemanticSearchService
- [ ] Enhance GlobalSearchView
- [ ] Add "find similar code" feature

### Week 4: Refactoring
- [ ] Create RefactoringService
- [ ] Add RefactoringView
- [ ] Implement preview functionality

### Week 5: Code Generation
- [ ] Create CodeGeneratorService
- [ ] Add FeatureGeneratorView
- [ ] Implement test generation

## Integration Points

### Update EditorViewModel
```swift
// Add properties
@Published var relatedFiles: [URL] = []
@Published var contextMode: ContextMode = .smart

// Add methods
func updateRelatedFiles() {
    if let activeFile = editorState.activeDocument?.filePath {
        relatedFiles = FileDependencyService.shared.findRelatedFiles(
            for: activeFile,
            in: rootFolderURL ?? activeFile.deletingLastPathComponent()
        )
    }
}
```

### Update AIChatView
```swift
// Add context controls
Toggle("Include Related Files", isOn: $includeRelatedFiles)
Picker("Context Mode", selection: $contextMode) {
    Text("Smart").tag(ContextMode.smart)
    Text("Full").tag(ContextMode.full)
    Text("Minimal").tag(ContextMode.minimal)
}
```

### Update ContentView
```swift
// Add related files sidebar
if !viewModel.relatedFiles.isEmpty {
    RelatedFilesView(
        fileURL: viewModel.editorState.activeDocument?.filePath,
        projectURL: viewModel.rootFolderURL
    )
    .frame(width: 200)
}
```

