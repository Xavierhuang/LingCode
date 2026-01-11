//
//  IntentPredictionService.swift
//  LingCode
//
//  Cross-file intent prediction - predicts what user wants to change across files
//

import Foundation

struct IntentPrediction {
    let affectedFiles: [URL]
    let suggestedEdits: [Edit]
    let confidence: Double
    let reason: String
}

enum IntentSignal {
    case functionRenamed(old: String, new: String)
    case exportChanged(symbol: String, isExported: Bool)
    case typeChanged(symbol: String, oldType: String, newType: String)
    case testFileNearby(testFile: URL)
    case callSiteDetected(function: String, file: URL)
}

class IntentPredictionService {
    static let shared = IntentPredictionService()
    
    private let renameService = RenameRefactorService.shared
    private let referenceIndex = ASTIndex.shared
    
    private init() {}
    
    /// Predict intent from current edit
    func predictIntent(
        from edit: Edit,
        in projectURL: URL,
        activeFile: URL
    ) -> IntentPrediction? {
        // Analyze edit to extract signals
        let signals = extractSignals(from: edit, in: projectURL, activeFile: activeFile)
        
        // Build affected files graph
        let affectedFiles = buildAffectedFilesGraph(signals: signals, in: projectURL)
        
        // Generate suggested edits
        let suggestedEdits = generateSuggestedEdits(
            signals: signals,
            affectedFiles: affectedFiles,
            originalEdit: edit
        )
        
        // Compute confidence score
        let confidence = computeConfidence(signals: signals, affectedFiles: affectedFiles)
        
        // Only suggest if confidence is high enough
        guard confidence > 0.85, !suggestedEdits.isEmpty else {
            return nil
        }
        
        let reason = buildReason(signals: signals, fileCount: affectedFiles.count)
        
        return IntentPrediction(
            affectedFiles: affectedFiles,
            suggestedEdits: suggestedEdits,
            confidence: confidence,
            reason: reason
        )
    }
    
    /// Extract intent signals from edit
    private func extractSignals(
        from edit: Edit,
        in projectURL: URL,
        activeFile: URL
    ) -> [IntentSignal] {
        var signals: [IntentSignal] = []
        
        // Check if this is a rename operation
        if edit.anchor != nil,
           edit.operation == .replace,
           let content = edit.content.first {
            // Try to resolve symbol at edit location
            if let symbol = renameService.resolveSymbol(
                at: edit.range?.startLine ?? 1,
                in: activeFile
            ) {
                // Check if name changed (rename)
                if symbol.name != content {
                    signals.append(.functionRenamed(
                        old: symbol.name,
                        new: content
                    ))
                }
            }
        }
        
        // Check for type changes in content
        if let content = edit.content.joined(separator: "\n") as String? {
            // Simple heuristic: look for type annotations
            if content.contains(":") && content.contains("->") {
                // Possible return type change
                // Would parse more carefully in production
            }
        }
        
        // Check for test files nearby
        let testFiles = findTestFiles(near: activeFile, in: projectURL)
        for testFile in testFiles {
            signals.append(.testFileNearby(testFile: testFile))
        }
        
        return signals
    }
    
    /// Build affected files graph
    private func buildAffectedFilesGraph(
        signals: [IntentSignal],
        in projectURL: URL
    ) -> [URL] {
        var affectedFiles: Set<URL> = []
        
        for signal in signals {
            switch signal {
            case .functionRenamed(let old, _):
                // Find all files referencing this function
                // Would use reference index
                let files = findFilesReferencing(symbol: old, in: projectURL)
                affectedFiles.formUnion(files)
                
            case .exportChanged(let symbol, _):
                // Find files importing this symbol
                let files = findFilesImporting(symbol: symbol, in: projectURL)
                affectedFiles.formUnion(files)
                
            case .typeChanged(let symbol, _, _):
                // Find files using this type
                let files = findFilesUsingType(symbol: symbol, in: projectURL)
                affectedFiles.formUnion(files)
                
            case .testFileNearby(let testFile):
                affectedFiles.insert(testFile)
                
            case .callSiteDetected(_, let file):
                affectedFiles.insert(file)
            }
        }
        
        return Array(affectedFiles)
    }
    
    /// Generate suggested edits for affected files
    private func generateSuggestedEdits(
        signals: [IntentSignal],
        affectedFiles: [URL],
        originalEdit: Edit
    ) -> [Edit] {
        var edits: [Edit] = []
        
        for signal in signals {
            switch signal {
            case .functionRenamed(let old, let new):
                // Generate rename edits for all affected files
                for file in affectedFiles {
                    if let edit = generateRenameEdit(
                        oldName: old,
                        newName: new,
                        in: file
                    ) {
                        edits.append(edit)
                    }
                }
                
            case .exportChanged, .typeChanged:
                // Would generate appropriate edits
                break
                
            case .testFileNearby(let testFile):
                // Update test file to match rename
                if case .functionRenamed(let old, let new) = signal {
                    if let edit = generateRenameEdit(
                        oldName: old,
                        newName: new,
                        in: testFile
                    ) {
                        edits.append(edit)
                    }
                }
                
            case .callSiteDetected:
                // Would generate call site updates
                break
            }
        }
        
        return edits
    }
    
    /// Compute confidence score
    private func computeConfidence(
        signals: [IntentSignal],
        affectedFiles: [URL]
    ) -> Double {
        var confidence: Double = 0.0
        
        // High confidence signals
        for signal in signals {
            switch signal {
            case .functionRenamed:
                confidence += 0.4 // High confidence for renames
            case .exportChanged:
                confidence += 0.3
            case .typeChanged:
                confidence += 0.3
            case .testFileNearby:
                confidence += 0.2
            case .callSiteDetected:
                confidence += 0.2
            }
        }
        
        // Adjust for number of affected files (more files = higher confidence)
        if affectedFiles.count > 1 {
            confidence += 0.1
        }
        
        return min(confidence, 1.0)
    }
    
    /// Build human-readable reason
    private func buildReason(signals: [IntentSignal], fileCount: Int) -> String {
        var reasons: [String] = []
        
        for signal in signals {
            switch signal {
            case .functionRenamed(let old, let new):
                reasons.append("Function renamed: \(old) → \(new)")
            case .exportChanged:
                reasons.append("Export changed")
            case .typeChanged:
                reasons.append("Type changed")
            case .testFileNearby:
                reasons.append("Test file detected")
            case .callSiteDetected:
                reasons.append("Call sites detected")
            }
        }
        
        let reasonText = reasons.joined(separator: ", ")
        return "This change affects \(fileCount) file\(fileCount == 1 ? "" : "s") — \(reasonText)"
    }
    
    // MARK: - Helper Methods
    
    private func findTestFiles(near fileURL: URL, in projectURL: URL) -> [URL] {
        var testFiles: [URL] = []
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return testFiles
        }
        
        for case let url as URL in enumerator {
            guard !url.hasDirectoryPath else { continue }
            
            let urlName = url.deletingPathExtension().lastPathComponent.lowercased()
            if urlName.contains("test") || urlName.contains(fileName.lowercased() + "test") {
                testFiles.append(url)
            }
        }
        
        return testFiles
    }
    
    private func findFilesReferencing(symbol: String, in projectURL: URL) -> [URL] {
        // Would use reference index
        // For now, placeholder
        return []
    }
    
    private func findFilesImporting(symbol: String, in projectURL: URL) -> [URL] {
        // Would use import index
        // For now, placeholder
        return []
    }
    
    private func findFilesUsingType(symbol: String, in projectURL: URL) -> [URL] {
        // Would use type index
        // For now, placeholder
        return []
    }
    
    private func generateRenameEdit(
        oldName: String,
        newName: String,
        in fileURL: URL
    ) -> Edit? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        
        // Find occurrences of oldName
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: oldName))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        guard let firstMatch = matches.first else {
            return nil
        }
        
        let matchRange = Range(firstMatch.range, in: content)!
        let lineNumber = content.prefix(content.distance(from: content.startIndex, to: matchRange.lowerBound))
            .components(separatedBy: .newlines).count
        
        return Edit(
            file: fileURL.path,
            operation: .replace,
            range: EditRange(startLine: lineNumber, endLine: lineNumber),
            anchor: nil,
            content: [newName]
        )
    }
}
