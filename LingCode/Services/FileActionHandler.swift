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
        
        // Read original content if file exists (for change highlighting and backup)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let originalContent = fileExists ? try? String(contentsOf: fileURL, encoding: .utf8) : nil
        
        // Enhanced safety checks: Don't apply if content is invalid
        let trimmedContent = file.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            print("⚠️ Warning: Skipping apply - file content is empty for \(file.path)")
            return
        }
        
        // Additional check: If file exists and new content is shorter than original, BLOCK the apply
        if let original = originalContent, !original.isEmpty {
            let originalLines = original.components(separatedBy: .newlines).count
            let newLines = file.content.components(separatedBy: .newlines).count
            
            // If new content has significantly fewer lines, it's likely incomplete - DON'T APPLY
            if newLines < originalLines / 2 && originalLines > 10 {
                print("❌ BLOCKED: New content for \(file.path) has \(newLines) lines vs original \(originalLines) lines. This is likely incomplete and would delete your code!")
                print("   Original file size: \(original.count) characters")
                print("   New file size: \(file.content.count) characters")
                print("   Skipping apply to protect your existing code.")
                return
            }
            
            // Also check if new content is much smaller in character count
            if file.content.count < original.count / 3 && original.count > 100 {
                print("❌ BLOCKED: New content for \(file.path) is \(file.content.count) characters vs original \(original.count) characters. This would delete most of your code!")
                print("   Skipping apply to protect your existing code.")
                return
            }
        }
        
        // Don't apply if file is still streaming
        if file.isStreaming {
            print("⚠️ Warning: Skipping apply - file \(file.path) is still streaming")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            // Write content atomically
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Verify the write was successful by reading back
            if let writtenContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                if writtenContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("❌ Error: File was written but is now empty! Restoring original content.")
                    // Restore original content if available
                    if let original = originalContent, !original.isEmpty {
                        try? original.write(to: fileURL, atomically: true, encoding: .utf8)
                    }
                    return
                }
            }
            
            // Defer state changes outside of view update cycle to avoid "Publishing changes" warnings
            Task { @MainActor in
                // Refresh file tree first to ensure file system is updated
                editorViewModel.refreshFileTree()
                
                // Open with change highlighting (this will refresh the editor view)
                editorViewModel.openFile(at: fileURL, originalContent: originalContent ?? "")
                
                // Force a refresh of the editor to show updated content
                if let document = editorViewModel.editorState.documents.first(where: { $0.filePath?.path == fileURL.path }) {
                    // Reload content from disk to ensure it's up to date
                    if let diskContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                        document.content = diskContent
                        document.isModified = false
                    }
                }
            }
        } catch {
            print("❌ Failed to apply file \(file.path): \(error)")
            // If write failed and we have original content, try to restore it
            if let original = originalContent, !original.isEmpty {
                do {
                    try original.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("✅ Restored original content for \(file.path)")
                } catch {
                    print("❌ Failed to restore original content: \(error)")
                }
            }
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

