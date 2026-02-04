//
//  ComposerService.swift
//  LingCode
//
//  Composer - Multi-file generation and editing UI (like Cursor's Composer)
//  Enables AI to create/modify multiple files in one session
//

import Foundation
import Combine

// MARK: - Composer Session

struct ComposerSession: Identifiable {
    let id: UUID
    var name: String
    var prompt: String
    var files: [ComposerFile]
    var status: ComposerStatus
    var createdAt: Date
    var updatedAt: Date
    var projectURL: URL?
    
    init(prompt: String, projectURL: URL? = nil) {
        self.id = UUID()
        self.name = ComposerSession.generateName(from: prompt)
        self.prompt = prompt
        self.files = []
        self.status = .drafting
        self.createdAt = Date()
        self.updatedAt = Date()
        self.projectURL = projectURL
    }
    
    static func generateName(from prompt: String) -> String {
        let words = prompt.split(separator: " ").prefix(5)
        return words.joined(separator: " ") + (words.count < prompt.split(separator: " ").count ? "..." : "")
    }
}

enum ComposerStatus: String {
    case drafting = "Drafting"
    case generating = "Generating"
    case reviewing = "Reviewing"
    case applying = "Applying"
    case completed = "Completed"
    case failed = "Failed"
}

// MARK: - Composer File

struct ComposerFile: Identifiable, Equatable {
    let id: UUID
    var path: String
    var content: String
    var originalContent: String?
    var status: FileStatus
    var isNew: Bool
    var isSelected: Bool
    var language: String?
    
    enum FileStatus: String {
        case pending = "Pending"
        case generated = "Generated"
        case modified = "Modified"
        case applied = "Applied"
        case rejected = "Rejected"
        case error = "Error"
    }
    
    init(path: String, content: String, originalContent: String? = nil, isNew: Bool = true) {
        self.id = UUID()
        self.path = path
        self.content = content
        self.originalContent = originalContent
        self.status = .generated
        self.isNew = isNew
        self.isSelected = true
        self.language = ComposerFile.detectLanguage(from: path)
    }
    
    static func detectLanguage(from path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let mapping: [String: String] = [
            "swift": "swift",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "tsx": "typescript",
            "jsx": "javascript",
            "rb": "ruby",
            "go": "go",
            "rs": "rust",
            "java": "java",
            "kt": "kotlin",
            "c": "c",
            "cpp": "cpp",
            "h": "c",
            "hpp": "cpp",
            "cs": "csharp",
            "php": "php",
            "html": "html",
            "css": "css",
            "scss": "scss",
            "json": "json",
            "yaml": "yaml",
            "yml": "yaml",
            "xml": "xml",
            "sql": "sql",
            "sh": "bash",
            "md": "markdown"
        ]
        return mapping[ext]
    }
    
    var diff: String? {
        guard let original = originalContent else { return nil }
        // Simple line-by-line diff
        let originalLines = original.components(separatedBy: "\n")
        let newLines = content.components(separatedBy: "\n")
        
        var diffResult = ""
        let maxLines = max(originalLines.count, newLines.count)
        
        for i in 0..<maxLines {
            let origLine = i < originalLines.count ? originalLines[i] : ""
            let newLine = i < newLines.count ? newLines[i] : ""
            
            if origLine != newLine {
                if i < originalLines.count {
                    diffResult += "- \(origLine)\n"
                }
                if i < newLines.count {
                    diffResult += "+ \(newLine)\n"
                }
            }
        }
        
        return diffResult.isEmpty ? nil : diffResult
    }
    
    static func == (lhs: ComposerFile, rhs: ComposerFile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Composer Service

class ComposerService: ObservableObject {
    static let shared = ComposerService()
    
    @Published var currentSession: ComposerSession?
    @Published var sessions: [ComposerSession] = []
    @Published var isGenerating: Bool = false
    @Published var generationProgress: Double = 0
    @Published var lastError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Session Management
    
    func createSession(prompt: String, projectURL: URL?) -> ComposerSession {
        let session = ComposerSession(prompt: prompt, projectURL: projectURL)
        currentSession = session
        sessions.insert(session, at: 0)
        return session
    }
    
    func selectSession(_ id: UUID) {
        currentSession = sessions.first { $0.id == id }
    }
    
    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if currentSession?.id == id {
            currentSession = sessions.first
        }
    }
    
    // MARK: - Generation
    
    func generate() async throws {
        guard var session = currentSession else { return }
        
        await MainActor.run {
            isGenerating = true
            generationProgress = 0
            session.status = .generating
            currentSession = session
        }
        
        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }
        
        do {
            // Build context
            let context = await buildContext(for: session)
            
            // Generate files
            let files = try await generateFiles(prompt: session.prompt, context: context)
            
            await MainActor.run {
                session.files = files
                session.status = .reviewing
                session.updatedAt = Date()
                currentSession = session
                
                // Update in sessions list
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index] = session
                }
            }
        } catch {
            await MainActor.run {
                session.status = .failed
                currentSession = session
                lastError = error.localizedDescription
            }
            throw error
        }
    }
    
    private func buildContext(for session: ComposerSession) async -> String {
        var context = ""
        
        guard let projectURL = session.projectURL else { return context }
        
        // Get project structure
        context += "## Project Structure\n\n"
        if let structure = try? getProjectStructure(projectURL) {
            context += "```\n\(structure)\n```\n\n"
        }
        
        // Add relevant files if mentioned in prompt
        let relevantFiles = findRelevantFiles(prompt: session.prompt, projectURL: projectURL)
        for file in relevantFiles.prefix(5) {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                context += "## \(file.lastPathComponent)\n\n"
                context += "```\(ComposerFile.detectLanguage(from: file.path) ?? "")\n\(content)\n```\n\n"
            }
        }
        
        return context
    }
    
    private func getProjectStructure(_ projectURL: URL) throws -> String {
        var structure = ""
        let fm = FileManager.default
        let ignoreService = IgnoreFileService.shared
        
        func listDirectory(_ url: URL, indent: String = "") throws {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { !ignoreService.shouldIgnore(url: $0, relativeTo: projectURL) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            for item in contents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                structure += "\(indent)\(item.lastPathComponent)\(isDir ? "/" : "")\n"
                
                if isDir && indent.count < 6 { // Limit depth
                    try listDirectory(item, indent: indent + "  ")
                }
            }
        }
        
        try listDirectory(projectURL)
        return structure
    }
    
    private func findRelevantFiles(prompt: String, projectURL: URL) -> [URL] {
        var relevantFiles: [URL] = []
        let fm = FileManager.default
        let words = prompt.lowercased().split(separator: " ").map(String.init)
        
        func searchDirectory(_ url: URL) {
            guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            
            for item in contents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDir {
                    searchDirectory(item)
                } else {
                    let filename = item.lastPathComponent.lowercased()
                    if words.contains(where: { filename.contains($0) }) {
                        relevantFiles.append(item)
                    }
                }
            }
        }
        
        searchDirectory(projectURL)
        return relevantFiles
    }
    
    private func generateFiles(prompt: String, context: String) async throws -> [ComposerFile] {
        let systemPrompt = """
        You are a code generator. Based on the user's request, generate the necessary files.
        
        Rules:
        1. Output each file in this exact format:
        
        === FILE: path/to/file.ext ===
        ```language
        file content here
        ```
        === END FILE ===
        
        2. Include ALL necessary files (code, tests, configs)
        3. Use proper file paths relative to project root
        4. Follow best practices for the language/framework
        5. Include comments explaining complex parts
        """
        
        let userPrompt = """
        \(context)
        
        ## Request
        \(prompt)
        
        Generate all necessary files.
        """
        
        var response = ""
        let stream = AIService.shared.streamMessage(
            userPrompt,
            context: nil,
            images: [],
            maxTokens: 8000,
            systemPrompt: systemPrompt
        )
        
        for try await chunk in stream {
            response += chunk
            await MainActor.run {
                // Estimate progress based on response length
                generationProgress = min(0.9, Double(response.count) / 10000.0)
            }
        }
        
        await MainActor.run {
            generationProgress = 1.0
        }
        
        return parseGeneratedFiles(response)
    }
    
    private func parseGeneratedFiles(_ response: String) -> [ComposerFile] {
        var files: [ComposerFile] = []
        
        // Pattern: === FILE: path === ... === END FILE ===
        let pattern = #"=== FILE: (.+?) ===\s*```\w*\n([\s\S]*?)```\s*=== END FILE ==="#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches {
                if let pathRange = Range(match.range(at: 1), in: response),
                   let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: .whitespaces)
                    let content = String(response[contentRange])
                    
                    let file = ComposerFile(path: path, content: content)
                    files.append(file)
                }
            }
        }
        
        // Fallback: Try markdown code blocks with filenames
        if files.isEmpty {
            let fallbackPattern = #"(?:###?\s*)?`?([^\n`]+\.\w+)`?\s*\n```\w*\n([\s\S]*?)```"#
            if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []) {
                let range = NSRange(response.startIndex..., in: response)
                let matches = regex.matches(in: response, options: [], range: range)
                
                for match in matches {
                    if let pathRange = Range(match.range(at: 1), in: response),
                       let contentRange = Range(match.range(at: 2), in: response) {
                        let path = String(response[pathRange]).trimmingCharacters(in: .whitespaces)
                        let content = String(response[contentRange])
                        
                        // Filter out obvious non-file patterns
                        if path.contains("/") || path.contains(".") {
                            let file = ComposerFile(path: path, content: content)
                            files.append(file)
                        }
                    }
                }
            }
        }
        
        return files
    }
    
    // MARK: - File Operations
    
    func toggleFileSelection(_ fileId: UUID) {
        guard var session = currentSession,
              let index = session.files.firstIndex(where: { $0.id == fileId }) else { return }
        
        session.files[index].isSelected.toggle()
        session.updatedAt = Date()
        currentSession = session
        
        if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[sessionIndex] = session
        }
    }
    
    func updateFileContent(_ fileId: UUID, content: String) {
        guard var session = currentSession,
              let index = session.files.firstIndex(where: { $0.id == fileId }) else { return }
        
        session.files[index].content = content
        session.files[index].status = .modified
        session.updatedAt = Date()
        currentSession = session
        
        if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[sessionIndex] = session
        }
    }
    
    func rejectFile(_ fileId: UUID) {
        guard var session = currentSession,
              let index = session.files.firstIndex(where: { $0.id == fileId }) else { return }
        
        session.files[index].status = .rejected
        session.files[index].isSelected = false
        session.updatedAt = Date()
        currentSession = session
        
        if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[sessionIndex] = session
        }
    }
    
    // MARK: - Apply Changes
    
    func applySelectedFiles() async throws -> Int {
        guard var session = currentSession,
              let projectURL = session.projectURL else { return 0 }
        
        await MainActor.run {
            session.status = .applying
            currentSession = session
        }
        
        let selectedFiles = session.files.filter { $0.isSelected && $0.status != .rejected }
        var appliedCount = 0
        
        for var file in selectedFiles {
            let fileURL = projectURL.appendingPathComponent(file.path)
            
            do {
                // Create directory if needed
                let directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                
                // Write file
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                file.status = .applied
                appliedCount += 1
                
                // Update in session
                if let index = session.files.firstIndex(where: { $0.id == file.id }) {
                    session.files[index] = file
                }
            } catch {
                file.status = .error
                if let index = session.files.firstIndex(where: { $0.id == file.id }) {
                    session.files[index] = file
                }
            }
        }
        
        await MainActor.run {
            session.status = .completed
            session.updatedAt = Date()
            currentSession = session
            
            if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[sessionIndex] = session
            }
        }
        
        return appliedCount
    }
    
    // MARK: - Preview
    
    func getPreviewForFile(_ fileId: UUID) -> String? {
        guard let session = currentSession,
              let file = session.files.first(where: { $0.id == fileId }) else { return nil }
        
        if let diff = file.diff {
            return "Changes:\n\(diff)"
        }
        
        return file.content
    }
    
    // MARK: - Statistics
    
    var selectedFilesCount: Int {
        currentSession?.files.filter { $0.isSelected && $0.status != .rejected }.count ?? 0
    }
    
    var totalLinesAdded: Int {
        currentSession?.files
            .filter { $0.isSelected && $0.status != .rejected }
            .reduce(0) { $0 + $1.content.components(separatedBy: "\n").count } ?? 0
    }
}
