//
//  FileActionHandler.swift
//  LingCode
//
//  Service for handling file operations (open, apply, etc.)
//

import Foundation

class FileActionHandler {
    static let shared = FileActionHandler()
    
    private init() {}
    
    func openFile(
        _ file: StreamingFileInfo,
        projectURL: URL?,
        editorViewModel: EditorViewModel
    ) {
        guard let projectURL = projectURL else {
            print("⚠️ Cannot open file: No project folder selected")
            return
        }
        
        // Handle both relative and absolute paths
        let fileURL: URL
        if file.path.hasPrefix("/") {
            // Absolute path
            fileURL = URL(fileURLWithPath: file.path)
        } else {
            // Relative path - append to project root
            fileURL = projectURL.appendingPathComponent(file.path)
        }
        
        // Check if file already exists
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        
        // Read original content if file exists (for change highlighting)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil
        
        if fileExists {
            // File exists - overwrite and open with change highlighting
            print("📂 Updating existing file: \(fileURL.path)")
            do {
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                // Defer state changes outside of view update cycle
                Task { @MainActor in
                    editorViewModel.openFile(at: fileURL, originalContent: originalContent)
                }
            } catch {
                print("❌ Failed to update file: \(error)")
            }
        } else {
            // File doesn't exist - create it with generated content
            let directory = fileURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ Created and opened file: \(fileURL.path)")
                // Defer state changes outside of view update cycle
                Task { @MainActor in
                    // New files: highlight everything as new (pass empty string as original)
                    editorViewModel.openFile(at: fileURL, originalContent: "")
                    // Refresh file tree to show new file immediately
                    editorViewModel.refreshFileTree()
                }
            } catch {
                print("❌ Failed to create file: \(error)")
                // Try to open anyway if it exists now
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    Task { @MainActor in
                        editorViewModel.openFile(at: fileURL)
                    }
                }
            }
        }
    }
    
    func applyFile(
        _ file: StreamingFileInfo,
        projectURL: URL?,
        editorViewModel: EditorViewModel
    ) {
        guard let projectURL = projectURL else { return }
        let fileURL = projectURL.appendingPathComponent(file.path)
        let directory = fileURL.deletingLastPathComponent()
        
        // Read original content if file exists (for change highlighting)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil
        
        // Safety check: Don't apply empty content
        guard !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ Warning: Skipping apply - file content is empty for \(file.path)")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Defer state changes outside of view update cycle to avoid "Publishing changes" warnings
            Task { @MainActor in
                // Open with change highlighting
                editorViewModel.openFile(at: fileURL, originalContent: originalContent ?? "")
                
                // Refresh file tree to show new file immediately
                editorViewModel.refreshFileTree()
            }
        } catch {
            print("Failed to apply file: \(error)")
        }
    }
    
    func openAction(
        _ action: AIAction,
        projectURL: URL?,
        editorViewModel: EditorViewModel
    ) {
        guard let projectURL = projectURL,
              let filePath = action.filePath else { return }
        let fileURL = projectURL.appendingPathComponent(filePath)
        editorViewModel.openFile(at: fileURL)
    }
    
    func applyAction(
        _ action: AIAction,
        projectURL: URL?,
        editorViewModel: EditorViewModel
    ) {
        guard let content = action.fileContent ?? action.result,
              let projectURL = projectURL,
              let filePath = action.filePath else { return }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let directory = fileURL.deletingLastPathComponent()
        
        // Read original content if file exists (for change highlighting)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            action.status = .completed
            
            // Defer state changes outside of view update cycle
            Task { @MainActor in
                // Open with change highlighting
                editorViewModel.openFile(at: fileURL, originalContent: originalContent ?? "")
                
                // Refresh file tree to show new file immediately
                editorViewModel.refreshFileTree()
            }
        } catch {
            action.status = .failed
            action.error = error.localizedDescription
        }
    }
}

