//
//  ActionExecutor.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

/// Executes file operations from AI responses
class ActionExecutor {
    static let shared = ActionExecutor()
    
    private let fileService = FileService.shared
    private let codeGenerator = CodeGeneratorService.shared
    private let projectGenerator = ProjectGeneratorService.shared
    
    private init() {}
    
    // MARK: - File Operations
    
    /// Execute multiple file operations with progress tracking
    func executeFileOperations(
        _ operations: [FileOperation],
        projectURL: URL?,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard !operations.isEmpty else {
            onComplete([])
            return
        }
        
        var createdFiles: [URL] = []
        var errors: [String] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, operation) in operations.enumerated() {
                let fileURL = URL(fileURLWithPath: operation.filePath)
                
                DispatchQueue.main.async {
                    onProgress("[\(index + 1)/\(operations.count)] \(operation.type.rawValue.capitalized): \(fileURL.lastPathComponent)")
                }
                
                do {
                    switch operation.type {
                    case .create:
                        try self.createFile(at: fileURL, content: operation.content ?? "")
                        createdFiles.append(fileURL)
                        
                    case .update:
                        if let content = operation.content {
                            try self.updateFile(at: fileURL, content: content, lineRange: operation.lineRange)
                        }
                        createdFiles.append(fileURL)
                        
                    case .append:
                        if let content = operation.content {
                            try self.appendToFile(at: fileURL, content: content)
                        }
                        createdFiles.append(fileURL)
                        
                    case .delete:
                        try self.deleteFile(at: fileURL)
                    }
                } catch {
                    errors.append("Failed to \(operation.type.rawValue) \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                if !errors.isEmpty {
                    onError(ActionExecutorError.partialFailure(errors: errors, successfulFiles: createdFiles))
                } else {
                    onComplete(createdFiles)
                }
            }
        }
    }
    
    /// Execute from AI response - main entry point
    func executeFromAIResponse(
        _ response: String,
        projectURL: URL?,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // First, try to parse as a project structure
        if let structure = codeGenerator.parseProjectStructure(from: response), !structure.files.isEmpty {
            executeProjectStructure(
                structure,
                projectURL: projectURL,
                onProgress: onProgress,
                onComplete: onComplete,
                onError: onError
            )
            return
        }
        
        // Fall back to file operations
        let operations = codeGenerator.extractFileOperations(from: response, projectURL: projectURL)
        
        if operations.isEmpty {
            // No file operations found - might be just explanatory text
            onComplete([])
            return
        }
        
        executeFileOperations(
            operations,
            projectURL: projectURL,
            onProgress: onProgress,
            onComplete: onComplete,
            onError: onError
        )
    }
    
    /// Execute a project structure
    private func executeProjectStructure(
        _ structure: ProjectStructure,
        projectURL: URL?,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let baseURL = projectURL else {
            // Ask user for project location
            DispatchQueue.main.async {
                onError(ActionExecutorError.noProjectURL)
            }
            return
        }
        
        var createdFiles: [URL] = []
        var errors: [String] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Create directories first
            DispatchQueue.main.async {
                onProgress("Creating directory structure...")
            }
            
            for directory in structure.directories {
                let dirURL = baseURL.appendingPathComponent(directory)
                do {
                    if !FileManager.default.fileExists(atPath: dirURL.path) {
                        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    }
                } catch {
                    errors.append("Failed to create directory \(directory): \(error.localizedDescription)")
                }
            }
            
            // Create files
            for (index, file) in structure.files.enumerated() {
                DispatchQueue.main.async {
                    onProgress("[\(index + 1)/\(structure.files.count)] Creating: \(file.path)")
                }
                
                let fileURL = baseURL.appendingPathComponent(file.path)
                
                do {
                    // Ensure parent directory exists
                    let parentDir = fileURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: parentDir.path) {
                        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }
                    
                    // Write file
                    try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                    createdFiles.append(fileURL)
                } catch {
                    errors.append("Failed to create \(file.path): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                onProgress("Created \(createdFiles.count) files")
                
                if !errors.isEmpty {
                    onError(ActionExecutorError.partialFailure(errors: errors, successfulFiles: createdFiles))
                } else {
                    onComplete(createdFiles)
                }
            }
        }
    }
    
    // MARK: - Individual File Operations
    
    private func createFile(at url: URL, content: String) throws {
        // Create directory if needed
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        // Write file
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func updateFile(at url: URL, content: String, lineRange: (start: Int, end: Int)?) throws {
        if let range = lineRange {
            // Update specific lines
            guard FileManager.default.fileExists(atPath: url.path) else {
                // If file doesn't exist, create it
                try createFile(at: url, content: content)
                return
            }
            
            let existingContent = try String(contentsOf: url, encoding: .utf8)
            let lines = existingContent.components(separatedBy: .newlines)
            
            var newLines = lines
            let newContentLines = content.components(separatedBy: .newlines)
            
            // Replace lines in range
            let startIndex = max(0, range.start - 1)
            let endIndex = min(lines.count, range.end)
            
            if startIndex < newLines.count {
                let safeEndIndex = min(endIndex, newLines.count)
                newLines.replaceSubrange(startIndex..<safeEndIndex, with: newContentLines)
            }
            
            let newContent = newLines.joined(separator: "\n")
            try newContent.write(to: url, atomically: true, encoding: .utf8)
        } else {
            // Replace entire file
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func appendToFile(at url: URL, content: String) throws {
        var existingContent = ""
        if FileManager.default.fileExists(atPath: url.path) {
            existingContent = try String(contentsOf: url, encoding: .utf8)
        } else {
            // Create directory if needed
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
        
        let separator = existingContent.isEmpty ? "" : "\n"
        let newContent = existingContent + separator + content
        try newContent.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func deleteFile(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Batch Operations
    
    /// Execute multiple actions in sequence
    func executeBatch(
        _ actions: [AIAction],
        response: String,
        projectURL: URL?,
        onActionUpdate: @escaping (AIAction) -> Void,
        onComplete: @escaping ([URL]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Mark all actions as executing
        for action in actions {
            action.status = .executing
            onActionUpdate(action)
        }
        
        executeFromAIResponse(
            response,
            projectURL: projectURL,
            onProgress: { message in
                // Update relevant action
                if let action = actions.first(where: { $0.status == .executing }) {
                    action.result = message
                    onActionUpdate(action)
                }
            },
            onComplete: { files in
                // Mark all actions as completed
                for action in actions {
                    action.status = .completed
                    action.result = "Completed successfully"
                    onActionUpdate(action)
                }
                onComplete(files)
            },
            onError: { error in
                // Mark remaining actions as failed
                for action in actions where action.status != .completed {
                    action.status = .failed
                    action.error = error.localizedDescription
                    onActionUpdate(action)
                }
                onError(error)
            }
        )
    }
    
    // MARK: - Validation
    
    /// Validate file operations before executing
    func validateOperations(_ operations: [FileOperation]) -> [String] {
        var warnings: [String] = []
        
        for operation in operations {
            let fileURL = URL(fileURLWithPath: operation.filePath)
            
            switch operation.type {
            case .create:
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    warnings.append("File already exists and will be overwritten: \(fileURL.lastPathComponent)")
                }
                
            case .update:
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    warnings.append("File does not exist and will be created: \(fileURL.lastPathComponent)")
                }
                
            case .delete:
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    warnings.append("File does not exist: \(fileURL.lastPathComponent)")
                }
                
            case .append:
                break // No validation needed
            }
        }
        
        return warnings
    }
}

// MARK: - Errors

enum ActionExecutorError: LocalizedError {
    case noProjectURL
    case partialFailure(errors: [String], successfulFiles: [URL])
    case fileNotFound(path: String)
    case permissionDenied(path: String)
    
    var errorDescription: String? {
        switch self {
        case .noProjectURL:
            return "No project URL specified. Please open or create a project first."
        case .partialFailure(let errors, let files):
            return "Partial success: Created \(files.count) files. Errors: \(errors.joined(separator: "; "))"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        }
    }
}
