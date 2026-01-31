//
//  ApplyCodeService.swift
//  LingCode
//
//  Lightweight adapter: executes committed EditorCore transactions to disk.
//  High-integrity snapshot and rollback live in EditorCore.EditTransaction.executeToDisk.
//

import Foundation
import Combine
import EditorCore

/// Wraps LingCode WorkspaceSnapshot for EditorCore.WorkspaceSnapshotProtocol.
private struct WorkspaceSnapshotAdapter: WorkspaceSnapshotProtocol {
    let snapshot: WorkspaceSnapshot
    func restore(to workspaceURL: URL) throws {
        try snapshot.restore(to: workspaceURL)
    }
}

/// Adapter that executes EditorCore transactions to disk. Single unified transaction pipeline.
class ApplyCodeService: ObservableObject, DiskWriteAdapter {
    static let shared = ApplyCodeService()
    
    @Published var pendingChanges: [CodeChange] = []
    @Published var isApplying: Bool = false
    @Published var lastApplyResult: ApplyResult?
    
    private let codeGenerator = CodeGeneratorService.shared
    
    private init() {}
    
    // MARK: - Disk Write (Unified Transaction Pipeline via EditorCore)
    
    /// Single entry point: build EditTransaction, run EditorCore.executeToDisk (snapshot + adapter), no fast path.
    func writeChanges(
        _ changes: [CodeChange],
        workspaceURL: URL,
        onProgress: ((Int, Int) -> Void)? = nil,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        guard !changes.isEmpty else {
            onComplete(ApplyResult(success: true, appliedCount: 0, failedCount: 0, errors: [], appliedFiles: []))
            return
        }
        let proposedEdits = changes.compactMap { codeChangeToProposedEdit($0, workspaceURL: workspaceURL) }
        guard proposedEdits.count == changes.count else {
            onComplete(ApplyResult(success: false, appliedCount: 0, failedCount: changes.count, errors: ["Failed to convert changes to transaction"], appliedFiles: []))
            return
        }
        let transaction = EditTransaction(edits: proposedEdits, metadata: TransactionMetadata(description: "ApplyCodeService", source: "broker"))
        isApplying = true
        let snapshot = WorkspaceSnapshot.create(from: workspaceURL)
        let progressWrapper: ((Int, Int) -> Void)? = onProgress.map { callback in
            { cur, total in DispatchQueue.main.async { callback(cur, total) } }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = transaction.executeToDisk(
                workspaceURL: workspaceURL,
                createSnapshot: { WorkspaceSnapshotAdapter(snapshot: snapshot) },
                adapter: self,
                onProgress: progressWrapper
            )
            let applyResult: ApplyResult
            switch result {
            case .success(let urls):
                applyResult = ApplyResult(success: true, appliedCount: urls.count, failedCount: 0, errors: [], appliedFiles: urls)
            case .failure(let error):
                applyResult = ApplyResult(success: false, appliedCount: 0, failedCount: changes.count, errors: [error.localizedDescription], appliedFiles: [])
            }
            DispatchQueue.main.async {
                self.lastApplyResult = applyResult
                self.isApplying = false
                self.pendingChanges.removeAll()
                if !applyResult.appliedFiles.isEmpty {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FilesCreated"),
                        object: nil,
                        userInfo: ["files": applyResult.appliedFiles]
                    )
                }
                onComplete(applyResult)
            }
        }
    }
    
    /// DiskWriteAdapter: perform one edit to disk (write or delete). Used by EditorCore transaction pipeline.
    func writeEdit(_ edit: ProposedEdit, workspaceURL: URL) throws -> URL {
        let filePath = edit.filePath.hasPrefix("/") ? edit.filePath : (workspaceURL.path as NSString).appendingPathComponent(edit.filePath)
        let fileURL = URL(fileURLWithPath: filePath)
        switch edit.metadata.editType {
        case .deletion:
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return fileURL
        case .creation, .modification:
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try edit.proposedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
    }
    
    private func codeChangeToProposedEdit(_ change: CodeChange, workspaceURL: URL) -> ProposedEdit? {
        let relativePath: String
        if change.filePath.hasPrefix(workspaceURL.path) {
            relativePath = String(change.filePath.dropFirst(workspaceURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relativePath = (change.filePath as NSString).lastPathComponent
        }
        let original = change.originalContent ?? ""
        let proposed = change.newContent
        let editType: EditType
        switch change.operationType {
        case .create: editType = .creation
        case .update, .append: editType = .modification
        case .delete: editType = .deletion
        }
        let oldCount = original.components(separatedBy: .newlines).count
        let newCount = proposed.components(separatedBy: .newlines).count
        let diff = DiffResult(
            hunks: [],
            addedLines: max(0, newCount - oldCount),
            removedLines: max(0, oldCount - newCount),
            unchangedLines: 0
        )
        return ProposedEdit(
            id: change.id,
            filePath: relativePath,
            originalContent: original,
            proposedContent: proposed,
            diff: diff,
            metadata: EditMetadata(editType: editType, source: "ApplyCodeService")
        )
    }
    
    // MARK: - Parse Changes (CodeGenerator path)
    
    /// Parse code changes from AI response (CodeGeneratorService path)
    func parseChanges(from response: String, projectURL: URL?) -> [CodeChange] {
        var changes: [CodeChange] = []
        
        // Get file operations from code generator
        let operations = codeGenerator.extractFileOperations(from: response, projectURL: projectURL)
        
        for operation in operations {
            let fileURL = URL(fileURLWithPath: operation.filePath)
            
            // Get existing content if file exists
            let existingContent: String?
            if FileManager.default.fileExists(atPath: fileURL.path) {
                existingContent = try? String(contentsOf: fileURL, encoding: .utf8)
            } else {
                existingContent = nil
            }
            
            let change = CodeChange(
                id: UUID(),
                filePath: operation.filePath,
                fileName: fileURL.lastPathComponent,
                operationType: operation.type,
                originalContent: existingContent,
                newContent: operation.content ?? "",
                lineRange: operation.lineRange,
                language: detectLanguage(from: fileURL)
            )
            
            changes.append(change)
        }
        
        return changes
    }
    
    // MARK: - Patch Parsing and Application
    
    /// Parse AI response and extract structured patches (patch-based writes via broker)
    func generatePatches(from response: String, projectURL: URL?) -> [CodePatch] {
        var patches: [CodePatch] = []
        if let jsonPatches = parseJSONPatches(from: response, projectURL: projectURL) {
            patches.append(contentsOf: jsonPatches)
        }
        let fileBlocks = parseFileBlocksToPatches(from: response, projectURL: projectURL)
        patches.append(contentsOf: fileBlocks)
        return patches
    }
    
    /// Apply a patch in-memory; returns new file content. Use applyPatchesToDisk to write.
    func applyPatchInMemory(_ patch: CodePatch, projectURL: URL?) throws -> String {
        let fileURL = resolveFileURL(for: patch.filePath, projectURL: projectURL)
        let existingContent: String
        if FileManager.default.fileExists(atPath: fileURL.path) {
            existingContent = try String(contentsOf: fileURL, encoding: .utf8)
        } else {
            existingContent = ""
        }
        let existingLines = existingContent.components(separatedBy: .newlines)
        
        switch patch.operation {
        case .insert:
            if let range = patch.range {
                var newLines = existingLines
                let insertIndex = min(range.startLine - 1, newLines.count)
                newLines.insert(contentsOf: patch.content, at: insertIndex)
                return newLines.joined(separator: "\n")
            }
            return existingContent + "\n" + patch.content.joined(separator: "\n")
            
        case .replace:
            if let range = patch.range {
                var newLines = existingLines
                let startIndex = max(0, range.startLine - 1)
                let endIndex = min(range.endLine, newLines.count)
                if startIndex > endIndex {
                    let newContent = patch.content.joined(separator: "\n")
                    guard !newContent.isEmpty else {
                        throw NSError(domain: "ApplyCodeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot replace with empty content"])
                    }
                    return newContent
                }
                newLines.replaceSubrange(startIndex..<endIndex, with: patch.content)
                return newLines.joined(separator: "\n")
            }
            let newContent = patch.content.joined(separator: "\n")
            let newLineCount = patch.content.count
            let originalLineCount = existingLines.count
            if originalLineCount > 50 && newLineCount > 0 {
                let ratio = Double(newLineCount) / Double(originalLineCount)
                if ratio < 0.2 {
                    throw NSError(domain: "ApplyCodeService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Rejected: New content (\(newLineCount) lines) much smaller than original (\(originalLineCount) lines). Provide complete file or use range-based edit."])
                }
            }
            guard !newContent.isEmpty else {
                throw NSError(domain: "ApplyCodeService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot replace file with empty content"])
            }
            return newContent
            
        case .delete:
            if let range = patch.range {
                var newLines = existingLines
                let startIndex = max(0, range.startLine - 1)
                let endIndex = min(range.endLine, newLines.count)
                newLines.removeSubrange(startIndex..<endIndex)
                return newLines.joined(separator: "\n")
            }
            return ""
        }
    }
    
    /// Apply patches to disk via single path (backup + write, or AtomicEditService for multi-file)
    func applyPatches(_ patches: [CodePatch], projectURL: URL?, onComplete: @escaping (ApplyResult) -> Void) {
        guard let projectURL = projectURL else {
            onComplete(ApplyResult(success: false, appliedCount: 0, failedCount: patches.count, errors: ["No project URL"], appliedFiles: []))
            return
        }
        var changes: [CodeChange] = []
        for patch in patches {
            let fileURL = resolveFileURL(for: patch.filePath, projectURL: projectURL)
            let existingContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? nil
            let newContent: String
            do {
                newContent = try applyPatchInMemory(patch, projectURL: projectURL)
            } catch {
                continue
            }
            let opType: FileOperation.OperationType = existingContent == nil ? .create : .update
            if newContent.isEmpty && patch.operation != .delete {
                continue
            }
            let change = CodeChange(
                id: patch.id,
                filePath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                operationType: opType,
                originalContent: existingContent,
                newContent: newContent,
                lineRange: patch.range.map { ($0.startLine, $0.endLine) },
                language: detectLanguage(from: fileURL)
            )
            changes.append(change)
        }
        if changes.isEmpty {
            onComplete(ApplyResult(success: true, appliedCount: 0, failedCount: 0, errors: [], appliedFiles: []))
            return
        }
        writeChanges(changes, workspaceURL: projectURL, onComplete: onComplete)
    }
    
    /// Resolve relative or absolute file path to URL
    func resolveFileURL(for filePath: String, projectURL: URL?) -> URL {
        if let projectURL = projectURL {
            if filePath.hasPrefix("/") {
                return URL(fileURLWithPath: filePath)
            }
            return projectURL.appendingPathComponent(filePath)
        }
        return URL(fileURLWithPath: filePath)
    }
    
    private func parseJSONPatches(from response: String, projectURL: URL?) -> [CodePatch]? {
        let jsonPattern = #"```json\s*\{[^`]+\}\s*```"#
        guard let regex = try? NSRegularExpression(pattern: jsonPattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: response, range: NSRange(location: 0, length: response.utf16.count)),
              let jsonRange = Range(match.range, in: response) else {
            return nil
        }
        let jsonString = String(response[jsonRange])
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let edits = json["edits"] as? [[String: Any]] else {
            return nil
        }
        var patches: [CodePatch] = []
        for edit in edits {
            guard let file = edit["file"] as? String,
                  let opString = edit["operation"] as? String,
                  let operation = CodePatch.PatchOperation(rawValue: opString) else {
                continue
            }
            var range: CodePatch.PatchRange? = nil
            if let rangeDict = edit["range"] as? [String: Any],
               let startLine = rangeDict["startLine"] as? Int,
               let endLine = rangeDict["endLine"] as? Int {
                range = CodePatch.PatchRange(
                    startLine: startLine,
                    endLine: endLine,
                    startColumn: rangeDict["startColumn"] as? Int,
                    endColumn: rangeDict["endColumn"] as? Int
                )
            }
            let content = edit["content"] as? [String] ?? []
            let description = edit["description"] as? String
            patches.append(CodePatch(filePath: file, operation: operation, range: range, content: content, description: description))
        }
        return patches
    }
    
    private func parseFileBlocksToPatches(from response: String, projectURL: URL?) -> [CodePatch] {
        var patches: [CodePatch] = []
        let filePattern = #"`([^`]+)`:\s*\n```(\w+)?\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: filePattern, options: []) else {
            return patches
        }
        let matches = regex.matches(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count))
        for match in matches {
            guard match.numberOfRanges >= 4,
                  let filePathRange = Range(match.range(at: 1), in: response),
                  let contentRange = Range(match.range(at: 3), in: response) else {
                continue
            }
            let filePath = String(response[filePathRange])
            let content = String(response[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let lines = content.components(separatedBy: .newlines)
            let fileURL = resolveFileURL(for: filePath, projectURL: projectURL)
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            let operation: CodePatch.PatchOperation = fileExists ? .replace : .insert
            patches.append(CodePatch(filePath: filePath, operation: operation, range: nil, content: lines, description: nil))
        }
        return patches
    }
    
    // MARK: - Deterministic Edits
    
    /// Generate deterministic replacement edits (simple string replace, no AI)
    func generateReplacementEdits(
        from: String,
        to: String,
        matchedFiles: [WorkspaceScanner.FileMatch],
        workspaceURL: URL,
        caseSensitive: Bool = false
    ) -> [DeterministicGeneratedEdit] {
        var edits: [DeterministicGeneratedEdit] = []
        for match in matchedFiles {
            guard let originalContent = try? String(contentsOf: match.fileURL, encoding: .utf8) else { continue }
            let newContent: String
            if caseSensitive {
                newContent = originalContent.replacingOccurrences(of: from, with: to)
            } else {
                newContent = performCaseInsensitiveReplacement(in: originalContent, from: from, to: to)
            }
            if newContent != originalContent {
                let relativePath = match.fileURL.path.replacingOccurrences(of: workspaceURL.path + "/", with: "")
                edits.append(DeterministicGeneratedEdit(
                    filePath: relativePath,
                    originalContent: originalContent,
                    newContent: newContent,
                    matchCount: match.matchCount
                ))
            }
        }
        return edits
    }
    
    /// Apply deterministic edits to disk via single path (transaction when multiple files)
    func applyDeterministicEdits(_ edits: [DeterministicGeneratedEdit], workspaceURL: URL, onComplete: @escaping (ApplyResult) -> Void) {
        var changes: [CodeChange] = []
        for edit in edits {
            let fileURL = workspaceURL.appendingPathComponent(edit.filePath)
            let change = CodeChange(
                id: UUID(),
                filePath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                operationType: .update,
                originalContent: edit.originalContent,
                newContent: edit.newContent,
                lineRange: nil,
                language: detectLanguage(from: fileURL)
            )
            changes.append(change)
        }
        if changes.isEmpty {
            onComplete(ApplyResult(success: true, appliedCount: 0, failedCount: 0, errors: [], appliedFiles: []))
            return
        }
        writeChanges(changes, workspaceURL: workspaceURL, onComplete: onComplete)
    }
    
    private func performCaseInsensitiveReplacement(in content: String, from: String, to: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: from)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        let range = NSRange(location: 0, length: content.utf16.count)
        let mutable = NSMutableString(string: content)
        regex.replaceMatches(in: mutable, options: [], range: range, withTemplate: to)
        return mutable as String
    }
    
    // MARK: - Streaming content parsing (inlined from StreamingContentParser)
    
    /// Parse streaming AI response into file list (JSON patches + fenced blocks + actions). Single entry for edit pipeline.
    func parseStreamingContent(
        _ content: String,
        isLoading: Bool,
        projectURL: URL?,
        actions: [AIAction]
    ) -> [StreamingFileInfo] {
        var newFiles: [StreamingFileInfo] = []
        var processedPaths = Set<String>()
        
        let jsonPatches = generatePatches(from: content, projectURL: projectURL).filter { $0.range != nil }
        if !jsonPatches.isEmpty {
            for patch in jsonPatches where !processedPaths.contains(patch.filePath) {
                processedPaths.insert(patch.filePath)
                if let newContent = try? applyPatchInMemory(patch, projectURL: projectURL) {
                    let (summary, added, removed) = streamingChangeSummary(filePath: patch.filePath, newContent: newContent, projectURL: projectURL)
                    newFiles.append(StreamingFileInfo(
                        id: patch.filePath,
                        path: patch.filePath,
                        name: URL(fileURLWithPath: patch.filePath).lastPathComponent,
                        language: detectLanguage(from: resolveFileURL(for: patch.filePath, projectURL: projectURL)),
                        content: newContent,
                        isStreaming: isLoading,
                        changeSummary: summary,
                        addedLines: added,
                        removedLines: removed
                    ))
                }
            }
        }
        
        for block in extractFencedCodeBlocks(from: content, allowIncomplete: isLoading) {
            guard let filePath = block.filePath, !processedPaths.contains(filePath) else { continue }
            let trimmedCode = block.code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isLoading && !block.isComplete { continue }
            if trimmedCode.count < 5 && !block.isComplete { continue }
            processedPaths.insert(filePath)
            let (summary, added, removed) = streamingChangeSummary(filePath: filePath, newContent: block.code, projectURL: projectURL)
            let fileInfo = StreamingFileInfo(
                id: filePath,
                path: filePath,
                name: URL(fileURLWithPath: filePath).lastPathComponent,
                language: block.language,
                content: block.code,
                isStreaming: !block.isComplete || isLoading,
                changeSummary: summary,
                addedLines: added,
                removedLines: removed
            )
            if let idx = newFiles.firstIndex(where: { $0.id == filePath }) {
                newFiles[idx] = fileInfo
            } else {
                newFiles.append(fileInfo)
            }
        }
        
        for action in actions {
            guard let path = action.filePath, !processedPaths.contains(path),
                  let content = action.fileContent ?? action.result else { continue }
            processedPaths.insert(path)
            let (summary, added, removed) = streamingChangeSummary(filePath: path, newContent: content, projectURL: projectURL)
            newFiles.append(StreamingFileInfo(
                id: path,
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                language: detectLanguage(from: URL(fileURLWithPath: path)),
                content: content,
                isStreaming: action.status == .executing,
                changeSummary: summary,
                addedLines: added,
                removedLines: removed
            ))
        }
        
        return newFiles
    }
    
    private struct FencedBlock {
        let filePath: String?
        let language: String
        let code: String
        let isComplete: Bool
    }
    
    private func extractFencedCodeBlocks(from content: String, allowIncomplete: Bool) -> [FencedBlock] {
        if !content.contains("```") { return [] }
        let lines = content.components(separatedBy: .newlines)
        var blocks: [FencedBlock] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let header = (i > 0 ? lines[i - 1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
                guard let filePath = extractFilePathFromHeader(header) else { i += 1; continue }
                let codeStart = i + 1
                var j = codeStart
                var found = false
                while j < lines.count {
                    if lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("```") { found = true; break }
                    j += 1
                }
                if found {
                    let code = lines[codeStart..<j].joined(separator: "\n")
                    blocks.append(FencedBlock(filePath: filePath, language: lang.isEmpty ? detectLanguage(from: URL(fileURLWithPath: filePath)) : lang, code: code, isComplete: true))
                    i = j + 1
                    continue
                }
                if allowIncomplete {
                    let code = lines[codeStart...].joined(separator: "\n")
                    blocks.append(FencedBlock(filePath: filePath, language: lang.isEmpty ? detectLanguage(from: URL(fileURLWithPath: filePath)) : lang, code: code, isComplete: false))
                }
                break
            }
            i += 1
        }
        return blocks
    }
    
    private func extractFilePathFromHeader(_ header: String) -> String? {
        var h = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasSuffix(":") { h = String(h.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let first = h.firstIndex(of: "`"), let last = h.lastIndex(of: "`"), first < last {
            let v = String(h[h.index(after: first)..<last]).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeFilePath(v)
        }
        if h.hasPrefix("**"), h.hasSuffix("**"), h.count > 4 {
            let v = String(h.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeFilePath(v)
        }
        if h.hasPrefix("###") {
            return normalizeFilePath(h.replacingOccurrences(of: "###", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return normalizeFilePath(h)
    }
    
    private func normalizeFilePath(_ value: String) -> String? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.contains(" ") || !t.contains(".") { return nil }
        return t
    }
    
    private func streamingChangeSummary(filePath: String, newContent: String, projectURL: URL?) -> (summary: String?, added: Int, removed: Int) {
        guard let projectURL = projectURL else {
            return ("New file", newContent.components(separatedBy: .newlines).count, 0)
        }
        let fileURL = projectURL.appendingPathComponent(filePath)
        let newLines = newContent.components(separatedBy: .newlines)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            let existingLines = existing.components(separatedBy: .newlines)
            let added = max(0, newLines.count - existingLines.count)
            let removed = max(0, existingLines.count - newLines.count)
            if added > 0 && removed > 0 { return ("Modified: +\(added) -\(removed) lines", added, removed) }
            if added > 0 { return ("Added \(added) line(s)", added, removed) }
            if removed > 0 { return ("Removed \(removed) line(s)", added, removed) }
            return ("No changes", 0, 0)
        }
        return ("New file: \(newLines.count) lines", newLines.count, 0)
    }
    
    /// Set pending changes for review
    func setPendingChanges(_ changes: [CodeChange]) {
        DispatchQueue.main.async {
            self.pendingChanges = changes
        }
    }
    
    /// Check if changes should be split into stacked PRs using Graphite
    func shouldUseGraphiteStacking(_ changes: [CodeChange]) -> Bool {
        let totalFiles = changes.count
        let totalLines = changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
        
        // Suggest Graphite if:
        // - More than 10 files, OR
        // - More than 500 lines, OR
        // - More than 5 files AND more than 200 lines
        return totalFiles > 10 || totalLines > 500 || (totalFiles > 5 && totalLines > 200)
    }
    
    /// Get recommendation for change management
    func getChangeRecommendation(_ changes: [CodeChange]) -> ChangeRecommendation {
        let totalFiles = changes.count
        let totalLines = changes.reduce(0) { $0 + $1.addedLines + $1.removedLines }
        
        if shouldUseGraphiteStacking(changes) {
            return .useGraphiteStacking(
                reason: "Large change set (\(totalFiles) files, \(totalLines) lines). Consider using Graphite to split into smaller, reviewable PRs.",
                estimatedPRs: max(1, (totalFiles / 5) + (totalLines / 200))
            )
        } else if totalFiles > 5 || totalLines > 200 {
            return .reviewCarefully(
                reason: "Moderate change set (\(totalFiles) files, \(totalLines) lines). Review carefully before applying."
            )
        } else {
            return .safeToApply(
                reason: "Small change set (\(totalFiles) files, \(totalLines) lines). Safe to apply."
            )
        }
    }
    
    // MARK: - Apply Changes
    
    /// Apply a single change with validation
    func applyChange(_ change: CodeChange, requestedScope: String? = nil) -> ApplyChangeResult {
        // Git-aware validation
        if let projectURL = findProjectURL(for: change.filePath) {
            let gitValidation = GitAwareService.shared.validateEdit(
                Edit(
                    file: change.filePath,
                    operation: .replace,
                    range: change.lineRange.map { EditRange(startLine: $0.start, endLine: $0.end) },
                    anchor: nil,
                    content: change.newContent.components(separatedBy: .newlines)
                ),
                in: projectURL
            )
            
            switch gitValidation {
            case .rejected(let reason):
                return ApplyChangeResult(
                    success: false,
                    error: "Git validation failed: \(reason)",
                    validationResult: nil
                )
            case .warning(let message):
                // Log warning but continue
                print("Git warning: \(message)")
            case .accepted:
                break
            }
        }
        
        // Validate before applying
        let validationService = CodeValidationService.shared
        let validation = validationService.validateChange(
            change,
            requestedScope: requestedScope ?? "Unknown",
            projectConfig: nil
        )
        
        // Block critical issues
        if validation.severity == .critical {
            return ApplyChangeResult(
                success: false,
                error: "Validation failed: \(validation.recommendation)",
                validationResult: validation
            )
        }
        
        let fileURL = URL(fileURLWithPath: change.filePath)
        
        // Create backup before applying
        let backupCreated = createBackup(fileURL: fileURL)
        
        do {
            // Create directory if needed
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            switch change.operationType {
            case .create, .update:
                try change.newContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
            case .append:
                var content = ""
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    content = try String(contentsOf: fileURL, encoding: .utf8)
                }
                content += "\n" + change.newContent
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
            case .delete:
                try FileManager.default.removeItem(at: fileURL)
            }
            
            return ApplyChangeResult(
                success: true,
                error: nil,
                validationResult: validation,
                backupCreated: backupCreated
            )
        } catch {
            // Restore backup on error
            if backupCreated {
                restoreBackup(fileURL: fileURL)
            }
            
            return ApplyChangeResult(
                success: false,
                error: "Failed to apply change: \(error.localizedDescription)",
                validationResult: validation,
                backupCreated: backupCreated
            )
        }
    }
    
    /// Create backup of file before modification
    private func createBackup(fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false // No file to backup
        }
        
        let backupURL = fileURL.appendingPathExtension("backup")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            return true
        } catch {
            print("Failed to create backup: \(error)")
            return false
        }
    }
    
    /// Restore backup if needed
    private func restoreBackup(fileURL: URL) {
        let backupURL = fileURL.appendingPathExtension("backup")
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: backupURL, to: fileURL)
        } catch {
            print("Failed to restore backup: \(error)")
        }
    }
    
    /// Apply all pending changes via unified transaction pipeline (EditorCore)
    func applyAllChangesWithRetry(
        _ changes: [CodeChange],
        in workspaceURL: URL,
        aiService: AIService,
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        setPendingChanges(changes)
        writeChanges(changes, workspaceURL: workspaceURL, onProgress: onProgress, onComplete: onComplete)
    }
    
    /// Apply all pending changes (unified pipeline; requires workspace URL)
    func applyAllChanges(
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        guard !pendingChanges.isEmpty else {
            onComplete(ApplyResult(success: true, appliedCount: 0, failedCount: 0, errors: [], appliedFiles: []))
            return
        }
        guard let workspaceURL = findProjectURL(for: pendingChanges[0].filePath) ?? pendingChanges.first.map({ URL(fileURLWithPath: $0.filePath).deletingLastPathComponent() }) else {
            onComplete(ApplyResult(success: false, appliedCount: 0, failedCount: pendingChanges.count, errors: ["No workspace URL for transaction pipeline"], appliedFiles: []))
            return
        }
        let toApply = pendingChanges
        writeChanges(toApply, workspaceURL: workspaceURL, onProgress: onProgress, onComplete: { [weak self] result in
            if result.success { self?.pendingChanges.removeAll() }
            onComplete(result)
        })
    }
    
    /// Apply selected changes only
    func applySelectedChanges(
        _ selectedIds: Set<UUID>,
        onComplete: @escaping (ApplyResult) -> Void
    ) {
        let selectedChanges = pendingChanges.filter { selectedIds.contains($0.id) }
        let tempPending = pendingChanges
        pendingChanges = selectedChanges
        
        applyAllChanges(
            onProgress: { _, _ in },
            onComplete: { result in
                // Remove applied changes from pending
                self.pendingChanges = tempPending.filter { !selectedIds.contains($0.id) }
                onComplete(result)
            }
        )
    }
    
    /// Reject a change (remove from pending)
    func rejectChange(_ change: CodeChange) {
        pendingChanges.removeAll { $0.id == change.id }
    }
    
    /// Reject all changes
    func rejectAllChanges() {
        pendingChanges.removeAll()
    }
    
    // MARK: - Diff Generation
    
    /// Generate a unified diff for a change
    func generateDiff(for change: CodeChange) -> String {
        guard let original = change.originalContent else {
            // New file - show all lines as additions
            return change.newContent.components(separatedBy: .newlines)
                .map { "+ \($0)" }
                .joined(separator: "\n")
        }
        
        let originalLines = original.components(separatedBy: .newlines)
        let newLines = change.newContent.components(separatedBy: .newlines)
        
        // Simple diff - show removed and added lines
        var diff = ""
        diff += "--- a/\(change.fileName)\n"
        diff += "+++ b/\(change.fileName)\n"
        
        // Use a simple line-by-line comparison
        let maxLines = max(originalLines.count, newLines.count)
        var diffLines: [String] = []
        
        for i in 0..<maxLines {
            let origLine = i < originalLines.count ? originalLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            
            if origLine == newLine {
                if let line = origLine {
                    diffLines.append("  \(line)")
                }
            } else {
                if let orig = origLine {
                    diffLines.append("- \(orig)")
                }
                if let new = newLine {
                    diffLines.append("+ \(new)")
                }
            }
        }
        
        return diff + diffLines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private func detectLanguage(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let languageMap: [String: String] = [
            "swift": "swift",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "jsx": "jsx",
            "tsx": "tsx",
            "html": "html",
            "css": "css",
            "json": "json",
            "md": "markdown",
            "rs": "rust",
            "go": "go",
            "java": "java",
            "kt": "kotlin",
            "c": "c",
            "cpp": "cpp",
            "h": "c",
            "hpp": "cpp",
            "yaml": "yaml",
            "yml": "yaml",
            "toml": "toml",
            "xml": "xml",
            "sh": "bash",
            "bash": "bash",
            "zsh": "bash"
        ]
        return languageMap[ext] ?? "text"
    }
}

// MARK: - Patch Types

/// Structured code edit (patch) parsed from AI response
struct CodePatch: Identifiable {
    let id = UUID()
    let filePath: String
    let operation: CodePatch.PatchOperation
    let range: CodePatch.PatchRange?
    let content: [String]
    let description: String?
    
    enum PatchOperation: String {
        case insert
        case replace
        case delete
    }
    
    struct PatchRange {
        let startLine: Int
        let endLine: Int
        let startColumn: Int?
        let endColumn: Int?
    }
}

// MARK: - Deterministic Edit Types

/// Generated edit for simple string replacement (deterministic, no AI)
struct DeterministicGeneratedEdit: Equatable {
    let filePath: String
    let originalContent: String
    let newContent: String
    let matchCount: Int
}

// MARK: - Supporting Types

struct CodeChange: Identifiable {
    let id: UUID
    let filePath: String
    let fileName: String
    let operationType: FileOperation.OperationType
    let originalContent: String?
    let newContent: String
    let lineRange: (start: Int, end: Int)?
    let language: String
    
    var isNewFile: Bool {
        originalContent == nil && operationType == .create
    }
    
    var isModification: Bool {
        originalContent != nil && operationType == .update
    }
    
    var isDeletion: Bool {
        operationType == .delete
    }
    
    var changeDescription: String {
        switch operationType {
        case .create: return "Create new file"
        case .update: return "Modify existing file"
        case .append: return "Append to file"
        case .delete: return "Delete file"
        }
    }
    
    var addedLines: Int {
        guard let original = originalContent else {
            return newContent.components(separatedBy: .newlines).count
        }
        let origCount = original.components(separatedBy: .newlines).count
        let newCount = newContent.components(separatedBy: .newlines).count
        return max(0, newCount - origCount)
    }
    
    var removedLines: Int {
        guard let original = originalContent else { return 0 }
        let origCount = original.components(separatedBy: .newlines).count
        let newCount = newContent.components(separatedBy: .newlines).count
        return max(0, origCount - newCount)
    }
}

struct ApplyResult {
    let success: Bool
    let appliedCount: Int
    let failedCount: Int
    let errors: [String]
    var appliedFiles: [URL] = []
}

enum ChangeRecommendation {
    case safeToApply(reason: String)
    case reviewCarefully(reason: String)
    case useGraphiteStacking(reason: String, estimatedPRs: Int)
    
    var message: String {
        switch self {
        case .safeToApply(let reason):
            return reason
            case .reviewCarefully(let reason):
            return reason
        case .useGraphiteStacking(let reason, let prs):
            return "\(reason) Estimated: \(prs) PRs"
        }
    }
    
    var shouldWarn: Bool {
        switch self {
        case .safeToApply:
            return false
        case .reviewCarefully, .useGraphiteStacking:
            return true
        }
    }
}

struct ApplyChangeResult {
    let success: Bool
    let error: String?
    let validationResult: ValidationResult?
    var backupCreated: Bool = false
    
    var canRollback: Bool {
        backupCreated && !success
    }
}

// MARK: - Helper Methods

extension ApplyCodeService {
    /// Find project URL for file path
    func findProjectURL(for filePath: String) -> URL? {
        let fileURL = URL(fileURLWithPath: filePath)
        // Try to find project root (look for .git, package.json, etc.)
        var current = fileURL.deletingLastPathComponent()
        while current.path != "/" {
            let gitPath = current.appendingPathComponent(".git")
            let packagePath = current.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: gitPath.path) ||
               FileManager.default.fileExists(atPath: packagePath.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return fileURL.deletingLastPathComponent() // Fallback to file's directory
    }
}
