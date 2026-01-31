//
//  IntentEngine.swift
//  LingCode
//
//  Unified intelligence layer: intent classification, task classification, and cross-file prediction.
//  Merges IntentClassifier + TaskClassifier + IntentPredictionService into one coherent engine.
//

import Foundation

// MARK: - Intent Prediction Types

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

// MARK: - IntentEngine

/// Unified engine for edit intent (replace/rename/refactor), task type (autocomplete/inlineEdit/refactor/debug/generate/chat),
/// and cross-file intent prediction with background cache warming.
@MainActor
final class IntentEngine {
    static let shared = IntentEngine()
    
    // MARK: - Background Worker Dependencies
    
    private let renameService = RenameRefactorService.shared
    private let referenceIndex = ASTIndex.shared
    
    private init() {}
    
    // MARK: - Edit Intent Classification
    
    /// Classified edit intent type for workspace-aware edit expansion and safety
    enum IntentType: Equatable {
        case simpleReplace(from: String, to: String)
        case rename(from: String, to: String)
        case refactor
        case rewrite
        case globalUpdate
        case complex
        
        /// Edit intent category for safety validation
        enum EditIntentCategory: Equatable {
            case textReplacement
            case boundedEdit
            case fullRewrite
            case complex
        }
        
        var editIntentCategory: EditIntentCategory {
            switch self {
            case .simpleReplace, .rename:
                return .textReplacement
            case .refactor:
                return .boundedEdit
            case .rewrite:
                return .fullRewrite
            case .globalUpdate, .complex:
                return .complex
            }
        }
    }
    
    /// Classify user edit intent from prompt (deterministic, pre-AI).
    func classifyIntent(_ prompt: String) -> IntentType {
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let replaceMatch = extractReplacePattern(from: normalized) {
            return .simpleReplace(from: replaceMatch.from, to: replaceMatch.to)
        }
        if let renameMatch = extractRenamePattern(from: normalized) {
            return .rename(from: renameMatch.from, to: renameMatch.to)
        }
        if containsRewriteKeywords(normalized) {
            return .rewrite
        }
        if containsRefactorKeywords(normalized) {
            return .refactor
        }
        if containsGlobalUpdateKeywords(normalized) {
            return .globalUpdate
        }
        return .complex
    }
    
    // MARK: - Task Type Classification
    
    enum TaskType: Equatable {
        case autocomplete
        case inlineEdit
        case refactor
        case debug
        case generate
        case chat
    }
    
    struct ClassificationContext {
        let userInput: String
        let cursorIsMidLine: Bool
        let diagnosticsPresent: Bool
        let selectionExists: Bool
        let activeFile: URL?
        let selectedText: String?
    }
    
    /// Classify task type with fast heuristics + model fallback.
    func classifyTask(context: ClassificationContext) -> TaskType {
        if context.cursorIsMidLine {
            return .autocomplete
        }
        if context.diagnosticsPresent {
            return .debug
        }
        if context.selectionExists && !(context.selectedText?.isEmpty ?? true) {
            return .inlineEdit
        }
        return classifyTaskHeuristically(userInput: context.userInput)
    }
    
    // MARK: - Background Cache Warming (from IntentPredictionService)
    
    /// Warm up cache for a file mentioned in the stream so predictIntent is faster when the edit lands.
    /// Call as soon as the AI mentions a filename in the stream; runs in background.
    func warmupCacheForFile(filenameOrPath: String, projectURL: URL) {
        let trimmed = filenameOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            guard let fileURL = resolveFileURL(trimmed, in: projectURL) else { return }
            _ = await referenceIndex.getSymbols(for: fileURL)
        }
    }
    
    /// Resolve filename or relative path to a file URL under projectURL.
    private func resolveFileURL(_ filenameOrPath: String, in projectURL: URL) -> URL? {
        let normalized = filenameOrPath.hasPrefix("/") ? String(filenameOrPath.dropFirst()) : filenameOrPath
        let candidate = projectURL.appendingPathComponent(normalized)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
            return candidate
        }
        if normalized == filenameOrPath, !normalized.contains("/") {
            if let found = findFileByName(normalized, in: projectURL) {
                return found
            }
        }
        return nil
    }
    
    private func findFileByName(_ name: String, in projectURL: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        let blocked = ["node_modules", "vendor", "build", "dist", ".git", ".build", "Pods", "DerivedData", ".swiftpm"]
        for case let url as URL in enumerator {
            guard !url.hasDirectoryPath else {
                if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                   resourceValues.isDirectory == true,
                   blocked.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }
    
    // MARK: - Cross-File Intent Prediction (from IntentPredictionService)
    
    /// Predict intent from current edit
    func predictIntent(
        from edit: Edit,
        in projectURL: URL,
        activeFile: URL
    ) -> IntentPrediction? {
        let signals = extractSignals(from: edit, in: projectURL, activeFile: activeFile)
        let affectedFiles = buildAffectedFilesGraph(signals: signals, in: projectURL)
        let suggestedEdits = generateSuggestedEdits(
            signals: signals,
            affectedFiles: affectedFiles,
            originalEdit: edit
        )
        let confidence = computeConfidence(signals: signals, affectedFiles: affectedFiles)
        
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
    
    // MARK: - Private Intent Classification Helpers
    
    private func extractReplacePattern(from prompt: String) -> (from: String, to: String)? {
        let patterns = [
            #"change\s+(.+?)\s+to\s+(.+?)$"#,
            #"replace\s+(.+?)\s+with\s+(.+?)$"#,
            #"update\s+(.+?)\s+to\s+(.+?)$"#,
            #"switch\s+(.+?)\s+to\s+(.+?)$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 3 {
                let fromRange = Range(match.range(at: 1), in: prompt)!
                let toRange = Range(match.range(at: 2), in: prompt)!
                let from = String(prompt[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let to = String(prompt[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !from.isEmpty && !to.isEmpty && from.count < 100 && to.count < 100 {
                    return (from: from, to: to)
                }
            }
        }
        return nil
    }
    
    private func extractRenamePattern(from prompt: String) -> (from: String, to: String)? {
        let patterns = [
            #"rename\s+(.+?)\s+to\s+(.+?)$"#,
            #"rename\s+(.+?)\s+as\s+(.+?)$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
               match.numberOfRanges >= 3 {
                let fromRange = Range(match.range(at: 1), in: prompt)!
                let toRange = Range(match.range(at: 2), in: prompt)!
                let from = String(prompt[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let to = String(prompt[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !from.isEmpty && !to.isEmpty && from.count < 100 && to.count < 100 {
                    return (from: from, to: to)
                }
            }
        }
        return nil
    }
    
    private func containsRefactorKeywords(_ prompt: String) -> Bool {
        ["refactor", "improve", "optimize", "restructure", "reorganize", "clean up", "cleanup"]
            .contains { prompt.contains($0) }
    }
    
    private func containsRewriteKeywords(_ prompt: String) -> Bool {
        ["rewrite", "complete rewrite", "full rewrite", "reimplement", "reimplement from scratch"]
            .contains { prompt.contains($0) }
    }
    
    private func containsGlobalUpdateKeywords(_ prompt: String) -> Bool {
        ["everywhere", "across project", "across the project", "in all files", "globally", "throughout", "project-wide"]
            .contains { prompt.contains($0) }
    }
    
    // MARK: - Private Task Classification Helpers
    
    private func classifyTaskHeuristically(userInput: String) -> TaskType {
        let lowercased = userInput.lowercased()
        if lowercased.contains("refactor") || lowercased.contains("restructure") || lowercased.contains("rename") || lowercased.contains("extract") {
            return .refactor
        }
        if lowercased.contains("debug") || lowercased.contains("fix error") || lowercased.contains("why is") || lowercased.contains("not working") || lowercased.contains("broken") {
            return .debug
        }
        if lowercased.contains("generate") || lowercased.contains("create") || lowercased.contains("make") || lowercased.contains("build") || lowercased.contains("add") {
            return .generate
        }
        if lowercased.contains("change") || lowercased.contains("modify") || lowercased.contains("update") || lowercased.contains("improve") || lowercased.contains("edit") {
            return .inlineEdit
        }
        return .chat
    }
    
    // MARK: - Private Intent Prediction Helpers
    
    /// Extract intent signals from edit
    private func extractSignals(
        from edit: Edit,
        in projectURL: URL,
        activeFile: URL
    ) -> [IntentSignal] {
        var signals: [IntentSignal] = []
        
        if edit.anchor != nil,
           edit.operation == .replace,
           let content = edit.content.first {
            if let symbol = renameService.resolveSymbol(
                at: edit.range?.startLine ?? 1,
                in: activeFile
            ) {
                if symbol.name != content {
                    signals.append(.functionRenamed(
                        old: symbol.name,
                        new: content
                    ))
                }
            }
        }
        
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
                let files = findFilesReferencing(symbol: old, in: projectURL)
                affectedFiles.formUnion(files)
            case .exportChanged(let symbol, _):
                let files = findFilesImporting(symbol: symbol, in: projectURL)
                affectedFiles.formUnion(files)
            case .typeChanged(let symbol, _, _):
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
                for file in affectedFiles {
                    if let edit = generateRenameEdit(
                        oldName: old,
                        newName: new,
                        in: file
                    ) {
                        edits.append(edit)
                    }
                }
            case .exportChanged, .typeChanged, .callSiteDetected:
                break
            case .testFileNearby(let testFile):
                if case .functionRenamed(let old, let new) = signal {
                    if let edit = generateRenameEdit(
                        oldName: old,
                        newName: new,
                        in: testFile
                    ) {
                        edits.append(edit)
                    }
                }
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
        
        for signal in signals {
            switch signal {
            case .functionRenamed:
                confidence += 0.4
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
                reasons.append("Function renamed: \(old) -> \(new)")
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
        return "This change affects \(fileCount) file\(fileCount == 1 ? "" : "s") - \(reasonText)"
    }
    
    // MARK: - Private File Discovery Helpers
    
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
        // Would use reference index - placeholder for now
        return []
    }
    
    private func findFilesImporting(symbol: String, in projectURL: URL) -> [URL] {
        // Would use import index - placeholder for now
        return []
    }
    
    private func findFilesUsingType(symbol: String, in projectURL: URL) -> [URL] {
        // Would use type index - placeholder for now
        return []
    }
    
    /// AST-aware renaming to avoid renaming in strings/comments
    private func generateRenameEdit(
        oldName: String,
        newName: String,
        in fileURL: URL
    ) -> Edit? {
        guard let symbol = renameService.resolveSymbol(
            at: 1,
            in: fileURL
        ), symbol.name == oldName else {
            return generateRenameEditWithRegex(oldName: oldName, newName: newName, in: fileURL)
        }
        
        return generateRenameEditWithRegex(oldName: oldName, newName: newName, in: fileURL)
    }
    
    /// Fallback regex-based rename with string/comment filtering
    private func generateRenameEditWithRegex(
        oldName: String,
        newName: String,
        in fileURL: URL
    ) -> Edit? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: oldName))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        for match in matches {
            guard let matchRange = Range(match.range, in: content) else { continue }
            
            let isInString = isInStringLiteral(at: matchRange, in: content)
            let isInCommentBlock = isInComment(at: matchRange, in: content)
            
            if !isInString && !isInCommentBlock {
                let beforeMatch = String(content[..<matchRange.lowerBound])
                let lineNumber = beforeMatch.components(separatedBy: .newlines).count
                return Edit(
                    file: fileURL.path,
                    operation: .replace,
                    range: EditRange(startLine: lineNumber, endLine: lineNumber),
                    anchor: nil,
                    content: [newName]
                )
            }
        }
        
        return nil
    }
    
    /// Check if a range is inside a string literal
    private func isInStringLiteral(at range: Range<String.Index>, in content: String) -> Bool {
        let before = String(content[..<range.lowerBound])
        var quoteCount = 0
        var escapeNext = false
        for char in before {
            if escapeNext {
                escapeNext = false
                continue
            }
            if char == "\\" {
                escapeNext = true
                continue
            }
            if char == "\"" || char == "'" {
                quoteCount += 1
            }
        }
        return quoteCount % 2 != 0
    }
    
    /// Check if a range is inside a comment
    private func isInComment(at range: Range<String.Index>, in content: String) -> Bool {
        let before = String(content[..<range.lowerBound])
        if let lastNewline = before.lastIndex(of: "\n") {
            let lineStart = before.index(after: lastNewline)
            let line = String(before[lineStart...])
            if line.contains("//") {
                return true
            }
        }
        let commentStart = before.range(of: "/*", options: .backwards)?.lowerBound
        let commentEnd = before.range(of: "*/", options: .backwards)?.lowerBound
        
        if let start = commentStart {
            if let end = commentEnd {
                return start > end
            }
            return true
        }
        return false
    }
}

// MARK: - Backwards Compatibility Alias

/// Backwards compatibility: IntentPredictionService now delegates to IntentEngine
@MainActor
class IntentPredictionService {
    static let shared = IntentPredictionService()
    
    private init() {}
    
    func warmupCacheForFile(filenameOrPath: String, projectURL: URL) {
        IntentEngine.shared.warmupCacheForFile(filenameOrPath: filenameOrPath, projectURL: projectURL)
    }
    
    func predictIntent(from edit: Edit, in projectURL: URL, activeFile: URL) -> IntentPrediction? {
        return IntentEngine.shared.predictIntent(from: edit, in: projectURL, activeFile: activeFile)
    }
}
