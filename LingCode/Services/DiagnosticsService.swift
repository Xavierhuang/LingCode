//
//  DiagnosticsService.swift
//  LingCode
//
//  Manages real-time diagnostics from LSP servers
//  Provides red squiggles and error highlighting
//

import Foundation
import SwiftUI
import Combine

/// Represents a diagnostic (error/warning) in the editor
struct EditorDiagnostic: Identifiable, Equatable {
    let id = UUID()
    let range: NSRange
    let severity: DiagnosticSeverity
    let message: String
    let code: String?
    
    enum DiagnosticSeverity: Int, Equatable {
        case error = 1
        case warning = 2
        case information = 3
        case hint = 4
        
        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .information: return .blue
            case .hint: return .gray
            }
        }
    }
}

/// Service that manages diagnostics from LSP servers
@MainActor
class DiagnosticsService: ObservableObject {
    static let shared = DiagnosticsService()
    
    // File URI -> diagnostics
    @Published var diagnostics: [String: [EditorDiagnostic]] = [:]
    
    private init() {
        // Subscribe to LSP diagnostics updates
        setupLSPDiagnosticsSubscription()
    }
    
    /// Setup subscription to LSP diagnostics
    private func setupLSPDiagnosticsSubscription() {
        // Set callback on SourceKit-LSP client
        SourceKitLSPClient.shared.onDiagnosticsUpdate = { [weak self] uri, lspDiagnostics in
            Task { @MainActor in
                self?.updateDiagnostics(uri: uri, lspDiagnostics: lspDiagnostics)
            }
        }
    }
    
    /// Update diagnostics for a file
    func updateDiagnostics(uri: String, lspDiagnostics: [LSPDiagnostic], fileContent: String? = nil) {
        // If we have file content, convert ranges properly
        if let content = fileContent {
            let editorDiagnostics = lspDiagnostics.map { diag in
                let range = Self.convertLSPRangeToNSRange(diag.range, in: content)
                let severity = EditorDiagnostic.DiagnosticSeverity(rawValue: diag.severity) ?? .error
                return EditorDiagnostic(
                    range: range,
                    severity: severity,
                    message: diag.message,
                    code: diag.code
                )
            }
            diagnostics[uri] = editorDiagnostics
        } else {
            // Store with placeholder ranges - will be converted when file is opened
            let editorDiagnostics = lspDiagnostics.map { diag in
                convertToEditorDiagnostic(diag)
            }
            diagnostics[uri] = editorDiagnostics
        }
    }
    
    /// Get diagnostics for a file URL
    /// If fileContent is provided, converts LSP ranges to NSRanges properly
    func getDiagnostics(for fileURL: URL, fileContent: String? = nil) -> [EditorDiagnostic] {
        let uri = fileURL.absoluteString
        var diags = diagnostics[uri] ?? []
        
        // If we have file content, convert any placeholder ranges (location 0, length 0) to proper ranges
        if let content = fileContent {
            // Check if we need to convert ranges (they might be placeholders)
            let needsConversion = diags.contains { $0.range.location == 0 && $0.range.length == 0 }
            
            if needsConversion {
                // Get fresh LSP diagnostics and convert ranges
                Task {
                    if let lspDiagnostics = try? await SourceKitLSPClient.shared.getDiagnostics(for: fileURL, fileContent: content) {
                        let converted = lspDiagnostics.map { lspDiag in
                            let range = Self.convertLSPRangeToNSRange(lspDiag.range, in: content)
                            let severity = EditorDiagnostic.DiagnosticSeverity(rawValue: lspDiag.severity) ?? .error
                            return EditorDiagnostic(
                                range: range,
                                severity: severity,
                                message: lspDiag.message,
                                code: lspDiag.code
                            )
                        }
                        await MainActor.run {
                            diagnostics[uri] = converted
                        }
                    }
                }
            } else {
                // Ranges are already converted, but update them with current content in case file changed
                diags = diags.map { diag in
                    // Re-validate range is still valid
                    if diag.range.location + diag.range.length <= content.count {
                        return diag
                    } else {
                        // Range is invalid, return with corrected range
                        let correctedRange = NSRange(location: min(diag.range.location, content.count), length: 0)
                        return EditorDiagnostic(
                            range: correctedRange,
                            severity: diag.severity,
                            message: diag.message,
                            code: diag.code
                        )
                    }
                }
            }
        }
        
        return diags
    }
    
    /// Convert LSP diagnostic to editor diagnostic
    private func convertToEditorDiagnostic(_ lspDiag: LSPDiagnostic) -> EditorDiagnostic {
        // Convert LSP range (line/character) to NSRange (character offset)
        // This requires the file content to calculate properly
        // For now, we'll store the LSP range and convert on-demand when we have the text
        // Placeholder range - will be converted when rendering
        let range = NSRange(location: 0, length: 0)
        
        let severity = EditorDiagnostic.DiagnosticSeverity(rawValue: lspDiag.severity) ?? .error
        
        return EditorDiagnostic(
            range: range,
            severity: severity,
            message: lspDiag.message,
            code: lspDiag.code
        )
    }
    
    /// Convert LSP range to NSRange given file content
    static func convertLSPRangeToNSRange(_ lspRange: LSPRange, in content: String) -> NSRange {
        let lines = content.components(separatedBy: .newlines)
        
        // Calculate start offset
        var startOffset = 0
        for i in 0..<min(lspRange.start.line, lines.count) {
            startOffset += lines[i].count + 1 // +1 for newline
        }
        if lspRange.start.line < lines.count {
            startOffset += min(lspRange.start.character, lines[lspRange.start.line].count)
        }
        
        // Calculate end offset
        var endOffset = 0
        for i in 0..<min(lspRange.end.line, lines.count) {
            endOffset += lines[i].count + 1
        }
        if lspRange.end.line < lines.count {
            endOffset += min(lspRange.end.character, lines[lspRange.end.line].count)
        }
        
        return NSRange(location: startOffset, length: max(0, endOffset - startOffset))
    }
    
    /// Clear diagnostics for a file
    func clearDiagnostics(for fileURL: URL) {
        let uri = fileURL.absoluteString
        diagnostics.removeValue(forKey: uri)
    }
}
