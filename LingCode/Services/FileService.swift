//
//  FileService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

class FileService {
    static let shared = FileService()
    
    private init() {}
    
    func openFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.text, .sourceCode, .data]
        
        guard panel.runModal() == .OK else {
            return nil
        }
        
        return panel.url
    }
    
    func openFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        guard panel.runModal() == .OK else {
            return nil
        }
        
        return panel.url
    }
    
    func saveFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func saveFileAs(content: String, currentURL: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text, .sourceCode]
        
        if let currentURL = currentURL {
            panel.nameFieldStringValue = currentURL.lastPathComponent
            panel.directoryURL = currentURL.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        
        do {
            try saveFile(content: content, to: url)
            return url
        } catch {
            return nil
        }
    }
    
    func readFile(at url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    func createFile(at url: URL, content: String = "") throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

