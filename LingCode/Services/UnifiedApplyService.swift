//
//  UnifiedApplyService.swift
//  LingCode
//
//  Unified service for applying code changes
//  Consolidates all apply functions into a single, reliable path
//

import Foundation
import Combine

/// Result of an apply operation
struct FileApplyResult {
    let success: Bool
    let filePath: String
    let message: String
    let wasBlocked: Bool
    let error: Error?
    
    static func success(path: String, message: String = "Applied successfully") -> FileApplyResult {
        FileApplyResult(success: true, filePath: path, message: message, wasBlocked: false, error: nil)
    }
    
    static func blocked(path: String, reason: String) -> FileApplyResult {
        FileApplyResult(success: false, filePath: path, message: reason, wasBlocked: true, error: nil)
    }
    
    static func failure(path: String, error: Error) -> FileApplyResult {
        FileApplyResult(success: false, filePath: path, message: error.localizedDescription, wasBlocked: false, error: error)
    }
}

/// Unified service for all code apply operations
@MainActor
class UnifiedApplyService: ObservableObject {
    static let shared = UnifiedApplyService()
    
    // MARK: - Published State
    
    @Published var isApplying: Bool = false
    @Published var currentOperation: String = ""
    @Published var lastResults: [FileApplyResult] = []
    @Published var appliedFilePaths: Set<String> = []
    
    // MARK: - Dependencies
    
    private let fileManager = FileManager.default
    private let autoImportService = AutoImportService.shared
    
    private init() {}
    
    // MARK: - Main Apply Interface
    
    /// Apply a single file change
    /// This is the ONLY method that should be used to apply file changes
    func applyFile(
        _ file: StreamingFileInfo,
        projectURL: URL,
        openInEditor: Bool = true,
        editorViewModel: EditorViewModel? = nil
    ) async -> FileApplyResult {
        // Guard against streaming files
        guard !file.isStreaming else {
            return .blocked(path: file.path, reason: "File is still streaming")
        }
        
        // Guard against already applied files
        guard !appliedFilePaths.contains(file.path) else {
            return .blocked(path: file.path, reason: "File already applied")
        }
        
        isApplying = true
        currentOperation = "Applying \(file.name)..."
        
        defer {
            isApplying = false
            currentOperation = ""
        }
        
        let fileURL = projectURL.appendingPathComponent(file.path)
        
        // Validate content
        let validationResult = validateContent(file.content, existingFile: fileURL)
        if !validationResult.isValid {
            let result = FileApplyResult.blocked(path: file.path, reason: validationResult.reason)
            lastResults.append(result)
            return result
        }
        
        // Process content (auto-imports, formatting)
        let processedContent = processContent(file.content, file: file, projectURL: projectURL)
        
        do {
            // Create backup if file exists
            if fileManager.fileExists(atPath: fileURL.path) {
                try createBackup(fileURL)
            }
            
            // Create directory if needed
            let directory = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            // Write file
            try processedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Track as applied
            appliedFilePaths.insert(file.path)
            
            // Mark in coordinator
            StreamingUpdateCoordinator.shared.markFileAsApplied(file.id)
            
            // Post notification for file tree refresh
            NotificationCenter.default.post(name: NSNotification.Name("FileCreated"), object: fileURL)
            
            // Open in editor if requested
            if openInEditor, let editor = editorViewModel {
                try await Task.sleep(nanoseconds: 50_000_000) // Brief delay for file system sync
                editor.openFile(at: fileURL)
            }
            
            let result = FileApplyResult.success(path: file.path)
            lastResults.append(result)
            return result
            
        } catch {
            let result = FileApplyResult.failure(path: file.path, error: error)
            lastResults.append(result)
            return result
        }
    }
    
    /// Apply multiple files
    func applyFiles(
        _ files: [StreamingFileInfo],
        projectURL: URL,
        openInEditor: Bool = true,
        editorViewModel: EditorViewModel? = nil
    ) async -> [FileApplyResult] {
        var results: [FileApplyResult] = []
        
        isApplying = true
        
        for (index, file) in files.enumerated() {
            currentOperation = "Applying \(file.name) (\(index + 1)/\(files.count))..."
            
            let result = await applyFile(
                file,
                projectURL: projectURL,
                openInEditor: openInEditor && index == files.count - 1, // Only open last file
                editorViewModel: editorViewModel
            )
            results.append(result)
        }
        
        isApplying = false
        currentOperation = ""
        
        return results
    }
    
    // MARK: - Validation
    
    private struct ValidationResult {
        let isValid: Bool
        let reason: String
    }
    
    private func validateContent(_ content: String, existingFile: URL) -> ValidationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty content check
        if trimmed.isEmpty {
            return ValidationResult(isValid: false, reason: "Content is empty")
        }
        
        // Check against existing file
        if fileManager.fileExists(atPath: existingFile.path),
           let originalContent = try? String(contentsOf: existingFile, encoding: .utf8) {
            
            let originalTrimmed = originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip validation for small files
            guard originalTrimmed.count > 100 else {
                return ValidationResult(isValid: true, reason: "")
            }
            
            let originalLines = originalContent.components(separatedBy: .newlines).count
            let newLines = content.components(separatedBy: .newlines).count
            
            // Calculate ratios
            let lineRatio = Double(newLines) / Double(max(1, originalLines))
            let charRatio = Double(trimmed.count) / Double(max(1, originalTrimmed.count))
            
            // Block if too small (less than 50% of original)
            if lineRatio < 0.5 && originalLines > 10 {
                return ValidationResult(
                    isValid: false,
                    reason: "New content is too small (\(Int(lineRatio * 100))% of original lines)"
                )
            }
            
            if charRatio < 0.5 && originalTrimmed.count > 200 {
                return ValidationResult(
                    isValid: false,
                    reason: "New content is too small (\(Int(charRatio * 100))% of original size)"
                )
            }
        }
        
        return ValidationResult(isValid: true, reason: "")
    }
    
    // MARK: - Content Processing
    
    private func processContent(_ content: String, file: StreamingFileInfo, projectURL: URL) -> String {
        var processed = content
        
        // Auto-imports if enabled
        if UserDefaults.standard.bool(forKey: "autoImportsEnabled") {
            let language = file.language.isEmpty ? nil : file.language
            processed = autoImportService.addMissingImports(
                to: processed,
                filePath: file.path,
                projectURL: projectURL,
                language: language
            )
        }
        
        return processed
    }
    
    // MARK: - Backup
    
    private func createBackup(_ fileURL: URL) throws {
        let backupDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LingCode/Backups", isDirectory: true)
        
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "\(fileURL.lastPathComponent).\(timestamp).backup"
        let backupURL = backupDir.appendingPathComponent(backupName)
        
        try fileManager.copyItem(at: fileURL, to: backupURL)
        
        // Clean old backups (keep last 20)
        cleanOldBackups(in: backupDir)
    }
    
    private func cleanOldBackups(in directory: URL) {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        let sorted = files.sorted { f1, f2 in
            let d1 = (try? f1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let d2 = (try? f2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return d1 > d2
        }
        
        // Remove all but last 20
        for file in sorted.dropFirst(20) {
            try? fileManager.removeItem(at: file)
        }
    }
    
    // MARK: - State Management
    
    func reset() {
        isApplying = false
        currentOperation = ""
        lastResults = []
        appliedFilePaths = []
    }
    
    func isFileApplied(_ path: String) -> Bool {
        appliedFilePaths.contains(path)
    }
    
    func markAsApplied(_ path: String) {
        appliedFilePaths.insert(path)
    }
}
