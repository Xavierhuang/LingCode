//
//  ProjectGeneratorService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

/// Service for generating entire project structures from AI responses
class ProjectGeneratorService {
    static let shared = ProjectGeneratorService()
    
    private let fileService = FileService.shared
    private let codeGenerator = CodeGeneratorService.shared
    
    private init() {}
    
    // MARK: - Project Generation
    
    /// Generate a complete project from AI response
    func generateProject(
        from response: String,
        projectURL: URL,
        onProgress: @escaping (ProjectGenerationProgress) -> Void,
        onComplete: @escaping (ProjectGenerationResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Parse project structure from response
            guard let structure = self.codeGenerator.parseProjectStructure(from: response) else {
                // Fallback to file operations if no clear structure
                let operations = self.codeGenerator.extractFileOperations(from: response, projectURL: projectURL)
                if operations.isEmpty {
                    DispatchQueue.main.async {
                        onComplete(ProjectGenerationResult(
                            success: false,
                            projectPath: projectURL,
                            createdFiles: [],
                            createdDirectories: [],
                            errors: ["No files found in AI response"]
                        ))
                    }
                    return
                }
                
                // Execute file operations
                self.executeFileOperations(operations, projectURL: projectURL, onProgress: onProgress, onComplete: onComplete)
                return
            }
            
            // Report start
            DispatchQueue.main.async {
                onProgress(ProjectGenerationProgress(
                    phase: .parsing,
                    message: "Parsed \(structure.files.count) files",
                    totalFiles: structure.files.count,
                    completedFiles: 0
                ))
            }
            
            var createdFiles: [URL] = []
            var createdDirectories: [URL] = []
            var errors: [String] = []
            
            // Create directories first
            DispatchQueue.main.async {
                onProgress(ProjectGenerationProgress(
                    phase: .creatingDirectories,
                    message: "Creating directory structure...",
                    totalFiles: structure.files.count,
                    completedFiles: 0
                ))
            }
            
            for directory in structure.directories {
                let dirURL = projectURL.appendingPathComponent(directory)
                do {
                    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    createdDirectories.append(dirURL)
                } catch {
                    errors.append("Failed to create directory \(directory): \(error.localizedDescription)")
                }
            }
            
            // Create files
            for (index, file) in structure.files.enumerated() {
                let fileURL = projectURL.appendingPathComponent(file.path)
                
                DispatchQueue.main.async {
                    onProgress(ProjectGenerationProgress(
                        phase: .creatingFiles,
                        message: "Creating \(file.path)...",
                        totalFiles: structure.files.count,
                        completedFiles: index,
                        currentFile: file.path
                    ))
                }
                
                do {
                    // Create parent directory if needed
                    let parentDir = fileURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: parentDir.path) {
                        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                        createdDirectories.append(parentDir)
                    }
                    
                    // Write file
                    try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                    createdFiles.append(fileURL)
                } catch {
                    errors.append("Failed to create \(file.path): \(error.localizedDescription)")
                }
            }
            
            // Report completion
            DispatchQueue.main.async {
                onProgress(ProjectGenerationProgress(
                    phase: .complete,
                    message: "Created \(createdFiles.count) files",
                    totalFiles: structure.files.count,
                    completedFiles: structure.files.count
                ))
                
                onComplete(ProjectGenerationResult(
                    success: errors.isEmpty,
                    projectPath: projectURL,
                    createdFiles: createdFiles,
                    createdDirectories: createdDirectories,
                    errors: errors
                ))
            }
        }
    }
    
    /// Execute individual file operations
    private func executeFileOperations(
        _ operations: [FileOperation],
        projectURL: URL,
        onProgress: @escaping (ProjectGenerationProgress) -> Void,
        onComplete: @escaping (ProjectGenerationResult) -> Void
    ) {
        var createdFiles: [URL] = []
        var createdDirectories: [URL] = []
        var errors: [String] = []
        
        for (index, operation) in operations.enumerated() {
            let fileURL = URL(fileURLWithPath: operation.filePath)
            
            DispatchQueue.main.async {
                onProgress(ProjectGenerationProgress(
                    phase: .creatingFiles,
                    message: "\(operation.type.rawValue.capitalized) \(fileURL.lastPathComponent)...",
                    totalFiles: operations.count,
                    completedFiles: index,
                    currentFile: fileURL.lastPathComponent
                ))
            }
            
            do {
                switch operation.type {
                case .create:
                    // Create parent directory if needed
                    let parentDir = fileURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: parentDir.path) {
                        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                        createdDirectories.append(parentDir)
                    }
                    
                    try (operation.content ?? "").write(to: fileURL, atomically: true, encoding: .utf8)
                    createdFiles.append(fileURL)
                    
                case .update:
                    try (operation.content ?? "").write(to: fileURL, atomically: true, encoding: .utf8)
                    createdFiles.append(fileURL)
                    
                case .append:
                    var existingContent = ""
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        existingContent = try String(contentsOf: fileURL, encoding: .utf8)
                    }
                    let newContent = existingContent + "\n" + (operation.content ?? "")
                    try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    createdFiles.append(fileURL)
                    
                case .delete:
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                errors.append("Failed to \(operation.type.rawValue) \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async {
            onComplete(ProjectGenerationResult(
                success: errors.isEmpty,
                projectPath: projectURL,
                createdFiles: createdFiles,
                createdDirectories: createdDirectories,
                errors: errors
            ))
        }
    }
    
    // MARK: - Project Templates
    
    /// Get available project templates
    func getProjectTemplates() -> [ProjectTemplate] {
        return [
            ProjectTemplate(
                name: "Swift Package",
                description: "A Swift package with basic structure",
                icon: "swift",
                files: [
                    ("Package.swift", packageSwiftTemplate),
                    ("Sources/Main/main.swift", swiftMainTemplate),
                    ("Tests/MainTests/MainTests.swift", swiftTestTemplate),
                    ("README.md", readmeTemplate)
                ]
            ),
            ProjectTemplate(
                name: "SwiftUI App",
                description: "A SwiftUI macOS/iOS application",
                icon: "app",
                files: [
                    ("App/ContentView.swift", swiftUIContentViewTemplate),
                    ("App/AppMain.swift", swiftUIAppTemplate),
                    ("README.md", readmeTemplate)
                ]
            ),
            ProjectTemplate(
                name: "Python Project",
                description: "A Python project with virtual environment setup",
                icon: "terminal",
                files: [
                    ("main.py", pythonMainTemplate),
                    ("requirements.txt", "# Add your dependencies here\n"),
                    ("README.md", readmeTemplate),
                    (".gitignore", pythonGitignoreTemplate)
                ]
            ),
            ProjectTemplate(
                name: "React App",
                description: "A React application with TypeScript",
                icon: "globe",
                files: [
                    ("src/App.tsx", reactAppTemplate),
                    ("src/index.tsx", reactIndexTemplate),
                    ("package.json", reactPackageJsonTemplate),
                    ("tsconfig.json", tsconfigTemplate),
                    ("public/index.html", reactHtmlTemplate),
                    ("README.md", readmeTemplate)
                ]
            ),
            ProjectTemplate(
                name: "Node.js API",
                description: "A Node.js Express API server",
                icon: "server.rack",
                files: [
                    ("src/index.js", nodeServerTemplate),
                    ("package.json", nodePackageJsonTemplate),
                    (".env.example", "PORT=3000\n"),
                    ("README.md", readmeTemplate),
                    (".gitignore", nodeGitignoreTemplate)
                ]
            ),
            ProjectTemplate(
                name: "Rust Project",
                description: "A Rust project with Cargo",
                icon: "gear",
                files: [
                    ("Cargo.toml", rustCargoTemplate),
                    ("src/main.rs", rustMainTemplate),
                    ("README.md", readmeTemplate),
                    (".gitignore", rustGitignoreTemplate)
                ]
            )
        ]
    }
    
    /// Create project from template
    func createFromTemplate(
        _ template: ProjectTemplate,
        projectName: String,
        at location: URL,
        onComplete: @escaping (ProjectGenerationResult) -> Void
    ) {
        let projectURL = location.appendingPathComponent(projectName)
        
        DispatchQueue.global(qos: .userInitiated).async {
            var createdFiles: [URL] = []
            var createdDirectories: [URL] = []
            var errors: [String] = []
            
            do {
                // Create project directory
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
                createdDirectories.append(projectURL)
                
                // Create files
                for (path, content) in template.files {
                    let fileURL = projectURL.appendingPathComponent(path)
                    let parentDir = fileURL.deletingLastPathComponent()
                    
                    // Create parent directory if needed
                    if !FileManager.default.fileExists(atPath: parentDir.path) {
                        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                        createdDirectories.append(parentDir)
                    }
                    
                    // Replace placeholders in content
                    let processedContent = content
                        .replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)
                        .replacingOccurrences(of: "{{YEAR}}", with: String(Calendar.current.component(.year, from: Date())))
                    
                    try processedContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    createdFiles.append(fileURL)
                }
            } catch {
                errors.append("Failed to create project: \(error.localizedDescription)")
            }
            
            DispatchQueue.main.async {
                onComplete(ProjectGenerationResult(
                    success: errors.isEmpty,
                    projectPath: projectURL,
                    createdFiles: createdFiles,
                    createdDirectories: createdDirectories,
                    errors: errors
                ))
            }
        }
    }
    
    // MARK: - Templates Content
    
    private let packageSwiftTemplate = """
    // swift-tools-version: 5.9
    import PackageDescription
    
    let package = Package(
        name: "{{PROJECT_NAME}}",
        products: [
            .executable(name: "{{PROJECT_NAME}}", targets: ["Main"])
        ],
        targets: [
            .executableTarget(name: "Main"),
            .testTarget(name: "MainTests", dependencies: ["Main"])
        ]
    )
    """
    
    private let swiftMainTemplate = """
    import Foundation
    
    @main
    struct Main {
        static func main() {
            print("Hello, World!")
        }
    }
    """
    
    private let swiftTestTemplate = """
    import XCTest
    @testable import Main
    
    final class MainTests: XCTestCase {
        func testExample() {
            XCTAssertTrue(true)
        }
    }
    """
    
    private let swiftUIContentViewTemplate = """
    import SwiftUI
    
    struct ContentView: View {
        var body: some View {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
            }
            .padding()
        }
    }
    
    #Preview {
        ContentView()
    }
    """
    
    private let swiftUIAppTemplate = """
    import SwiftUI
    
    @main
    struct {{PROJECT_NAME}}App: App {
        var body: some Scene {
            WindowGroup {
                ContentView()
            }
        }
    }
    """
    
    private let pythonMainTemplate = """
    #!/usr/bin/env python3
    \"\"\"
    {{PROJECT_NAME}} - Main entry point
    \"\"\"
    
    def main():
        print("Hello, World!")
    
    if __name__ == "__main__":
        main()
    """
    
    private let pythonGitignoreTemplate = """
    __pycache__/
    *.py[cod]
    *$py.class
    *.so
    .Python
    env/
    venv/
    .env
    .venv
    dist/
    build/
    *.egg-info/
    .pytest_cache/
    .mypy_cache/
    """
    
    private let reactAppTemplate = """
    import React from 'react';
    
    function App() {
      return (
        <div className="App">
          <header className="App-header">
            <h1>Welcome to {{PROJECT_NAME}}</h1>
          </header>
        </div>
      );
    }
    
    export default App;
    """
    
    private let reactIndexTemplate = """
    import React from 'react';
    import ReactDOM from 'react-dom/client';
    import App from './App';
    
    const root = ReactDOM.createRoot(
      document.getElementById('root') as HTMLElement
    );
    root.render(
      <React.StrictMode>
        <App />
      </React.StrictMode>
    );
    """
    
    private let reactPackageJsonTemplate = """
    {
      "name": "{{PROJECT_NAME}}",
      "version": "0.1.0",
      "private": true,
      "dependencies": {
        "react": "^18.2.0",
        "react-dom": "^18.2.0"
      },
      "devDependencies": {
        "@types/react": "^18.2.0",
        "@types/react-dom": "^18.2.0",
        "typescript": "^5.0.0"
      },
      "scripts": {
        "start": "react-scripts start",
        "build": "react-scripts build",
        "test": "react-scripts test"
      }
    }
    """
    
    private let tsconfigTemplate = """
    {
      "compilerOptions": {
        "target": "ES2020",
        "lib": ["dom", "dom.iterable", "esnext"],
        "allowJs": true,
        "skipLibCheck": true,
        "esModuleInterop": true,
        "allowSyntheticDefaultImports": true,
        "strict": true,
        "forceConsistentCasingInFileNames": true,
        "module": "esnext",
        "moduleResolution": "node",
        "resolveJsonModule": true,
        "isolatedModules": true,
        "jsx": "react-jsx"
      },
      "include": ["src"]
    }
    """
    
    private let reactHtmlTemplate = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>{{PROJECT_NAME}}</title>
    </head>
    <body>
      <div id="root"></div>
    </body>
    </html>
    """
    
    private let nodeServerTemplate = """
    const express = require('express');
    const app = express();
    const port = process.env.PORT || 3000;
    
    app.use(express.json());
    
    app.get('/', (req, res) => {
      res.json({ message: 'Welcome to {{PROJECT_NAME}} API' });
    });
    
    app.listen(port, () => {
      console.log(`Server running on port ${port}`);
    });
    """
    
    private let nodePackageJsonTemplate = """
    {
      "name": "{{PROJECT_NAME}}",
      "version": "1.0.0",
      "main": "src/index.js",
      "scripts": {
        "start": "node src/index.js",
        "dev": "nodemon src/index.js"
      },
      "dependencies": {
        "express": "^4.18.2"
      },
      "devDependencies": {
        "nodemon": "^3.0.0"
      }
    }
    """
    
    private let nodeGitignoreTemplate = """
    node_modules/
    .env
    .DS_Store
    dist/
    coverage/
    """
    
    private let rustCargoTemplate = """
    [package]
    name = "{{PROJECT_NAME}}"
    version = "0.1.0"
    edition = "2021"
    
    [dependencies]
    """
    
    private let rustMainTemplate = """
    fn main() {
        println!("Hello, World!");
    }
    """
    
    private let rustGitignoreTemplate = """
    /target
    Cargo.lock
    """
    
    private let readmeTemplate = """
    # {{PROJECT_NAME}}
    
    ## Description
    
    A new project created with LingCode.
    
    ## Getting Started
    
    Instructions for building and running the project.
    
    ## License
    
    MIT License - {{YEAR}}
    """
}

// MARK: - Supporting Types

struct ProjectGenerationProgress {
    let phase: Phase
    let message: String
    let totalFiles: Int
    let completedFiles: Int
    var currentFile: String?
    
    enum Phase {
        case parsing
        case creatingDirectories
        case creatingFiles
        case complete
    }
    
    var percentage: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(completedFiles) / Double(totalFiles) * 100
    }
}

struct ProjectGenerationResult {
    let success: Bool
    let projectPath: URL
    let createdFiles: [URL]
    let createdDirectories: [URL]
    let errors: [String]
}

struct ProjectTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let files: [(path: String, content: String)]
}

