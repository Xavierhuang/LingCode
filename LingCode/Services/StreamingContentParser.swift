//
//  StreamingContentParser.swift
//  LingCode
//
//  Service for parsing streaming content and extracting file information
//  DEBUG VERSION: Prints raw AI output and traces every parsing step.
//

import Foundation

class StreamingContentParser {
    static let shared = StreamingContentParser()
    
    private init() {}
    
    func parseContent(
        _ content: String,
        isLoading: Bool,
        projectURL: URL?,
        actions: [AIAction]
    ) -> [StreamingFileInfo] {
        // 1. PRINT RAW OUTPUT (Crucial for debugging)
        print("\n-------- 🔍 AI RAW RESPONSE PREVIEW (First 500 chars) --------")
        print(content.prefix(500))
        print("-------------------------------------------------------------\n")
        print("🔍 [Parser] Total Length: \(content.count) chars | Loading: \(isLoading)")
        
        var newFiles: [StreamingFileInfo] = []
        var processedPaths = Set<String>()
        
        // 2. Try JSON Edits first
        if let jsonPatches = parseJSONEdits(content: content, projectURL: projectURL) {
            print("🔍 [Parser] Found \(jsonPatches.count) JSON patches.")
            for patch in jsonPatches {
                if !processedPaths.contains(patch.filePath) {
                    processedPaths.insert(patch.filePath)
                    let patchGenerator = PatchGeneratorService.shared
                    if let newContent = try? patchGenerator.applyPatch(patch, projectURL: projectURL) {
                        let (summary, added, removed) = calculateChangeSummary(filePath: patch.filePath, newContent: newContent, projectURL: projectURL)
                        
                        newFiles.append(StreamingFileInfo(
                            id: patch.filePath,
                            path: patch.filePath,
                            name: URL(fileURLWithPath: patch.filePath).lastPathComponent,
                            language: detectLanguage(from: patch.filePath),
                            content: newContent,
                            isStreaming: isLoading,
                            changeSummary: summary,
                            addedLines: added,
                            removedLines: removed
                        ))
                        print("✅ [Parser] Accepted JSON file: \(patch.filePath)")
                    }
                }
            }
        } else {
            print("🔍 [Parser] No JSON patches found. Checking Regex patterns...")
        }
        
        // 3. Fence-based parsing (NO REGEX BACKTRACKING)
        // This avoids catastrophic regex behavior on large inputs and guarantees termination.
        let completeBlocks = extractFencedCodeBlocks(from: content, allowIncomplete: false)
        if !completeBlocks.isEmpty {
            print("🔍 [Parser] Found \(completeBlocks.count) complete fenced blocks.")
        }
        for block in completeBlocks where block.isComplete {
            processFencedBlock(
                block,
                isLoading: isLoading,
                projectURL: projectURL,
                newFiles: &newFiles,
                processedPaths: &processedPaths,
                isRescue: false
            )
        }

        // Process incomplete blocks while loading (streaming)
        if isLoading {
            let streamingBlocks = extractFencedCodeBlocks(from: content, allowIncomplete: true)
            let incompleteCount = streamingBlocks.filter { !$0.isComplete }.count
            if incompleteCount > 0 {
                print("🔍 [Parser] Found \(incompleteCount) incomplete fenced blocks (streaming).")
            }
            for block in streamingBlocks where !block.isComplete {
                processFencedBlock(
                    block,
                    isLoading: isLoading,
                    projectURL: projectURL,
                    newFiles: &newFiles,
                    processedPaths: &processedPaths,
                    isRescue: false
                )
            }
        }

        // 4. RESCUE MODE (If content exists but 0 files found)
        if !isLoading && newFiles.isEmpty && content.count > 100 {
            print("⚠️ [Parser] RESCUE MODE: No complete blocks found. Attempting to parse truncated content...")
            let rescueBlocks = extractFencedCodeBlocks(from: content, allowIncomplete: true)
            for block in rescueBlocks {
                processFencedBlock(
                    block,
                    isLoading: isLoading,
                    projectURL: projectURL,
                    newFiles: &newFiles,
                    processedPaths: &processedPaths,
                    isRescue: true
                )
            }
        }
        
        // Check actions
        for action in actions {
             if let path = action.filePath,
                !processedPaths.contains(path),
                let content = action.fileContent ?? action.result {
                 processedPaths.insert(path)
                 let (summary, added, removed) = calculateChangeSummary(filePath: path, newContent: content, projectURL: projectURL)
                 newFiles.append(StreamingFileInfo(
                     id: path,
                     path: path,
                     name: URL(fileURLWithPath: path).lastPathComponent,
                     language: detectLanguage(from: path),
                     content: content,
                     isStreaming: isLoading && action.status == .executing,
                     changeSummary: summary,
                     addedLines: added,
                     removedLines: removed
                 ))
                 print("✅ [Parser] Accepted Action file: \(path)")
             }
         }

        print("📊 [Parser] Finished. Total files found: \(newFiles.count)")
        return newFiles
    }

    // MARK: - Fence-based parsing

    private struct FencedCodeBlock {
        let headerLine: String
        let filePath: String
        let language: String
        let code: String
        let isComplete: Bool
    }

    private func extractFencedCodeBlocks(from content: String, allowIncomplete: Bool) -> [FencedCodeBlock] {
        // Fast exit if no fences
        if !content.contains("```") {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var blocks: [FencedCodeBlock] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Opening fence
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let header = findHeaderLine(before: i, in: lines) ?? ""
                guard let filePath = extractFilePathCandidate(from: header) else {
                    i += 1
                    continue
                }

                let codeStart = i + 1
                var j = codeStart
                var foundClosingFence = false
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("```") {
                        foundClosingFence = true
                        break
                    }
                    j += 1
                }

                if foundClosingFence {
                    let code = lines[codeStart..<j].joined(separator: "\n")
                    blocks.append(FencedCodeBlock(
                        headerLine: header,
                        filePath: filePath,
                        language: language.isEmpty ? detectLanguage(from: filePath) : language,
                        code: code,
                        isComplete: true
                    ))
                    i = j + 1
                    continue
                } else if allowIncomplete {
                    let code = lines[codeStart...].joined(separator: "\n")
                    blocks.append(FencedCodeBlock(
                        headerLine: header,
                        filePath: filePath,
                        language: language.isEmpty ? detectLanguage(from: filePath) : language,
                        code: code,
                        isComplete: false
                    ))
                    break
                } else {
                    break
                }
            }

            i += 1
        }

        return blocks
    }

    private func findHeaderLine(before fenceLineIndex: Int, in lines: [String]) -> String? {
        // Look up to 3 lines above for a plausible header
        var idx = fenceLineIndex - 1
        var attempts = 0
        while idx >= 0 && attempts < 3 {
            let candidate = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
            idx -= 1
            attempts += 1
        }
        return nil
    }

    private func extractFilePathCandidate(from headerLine: String) -> String? {
        var header = headerLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.hasSuffix(":") {
            header.removeLast()
            header = header.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // `path/to/file.ext`
        if let first = header.firstIndex(of: "`"), let last = header.lastIndex(of: "`"), first < last {
            let inside = header.index(after: first)..<last
            let value = String(header[inside]).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeFilePath(value)
        }

        // **path/to/file.ext**
        if header.hasPrefix("**"), header.hasSuffix("**"), header.count > 4 {
            let inside = header.index(header.startIndex, offsetBy: 2)..<header.index(header.endIndex, offsetBy: -2)
            let value = String(header[inside]).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeFilePath(value)
        }

        // ### path/to/file.ext
        if header.hasPrefix("###") {
            let value = header.replacingOccurrences(of: "###", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeFilePath(value)
        }

        // Plain header
        return normalizeFilePath(header)
    }

    private func normalizeFilePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        // Avoid obvious prose headers
        if trimmed.contains(" ") { return nil }
        // Must look like a filename
        if !trimmed.contains(".") { return nil }
        return trimmed
    }

    private func processFencedBlock(
        _ block: FencedCodeBlock,
        isLoading: Bool,
        projectURL: URL?,
        newFiles: inout [StreamingFileInfo],
        processedPaths: inout Set<String>,
        isRescue: Bool
    ) {
        let filePath = block.filePath
        guard !processedPaths.contains(filePath) else { return }

        let trimmedCode = block.code.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔍 [Parser] Examining candidate: '\(filePath)' (Length: \(trimmedCode.count))")

        // Safety check
        if !isRescue && trimmedCode.count < 5 {
            print("❌ [Parser] Rejected '\(filePath)': Content too short (< 5 chars)")
            return
        }

        // Streaming check (Unless rescuing)
        if !isLoading && !block.isComplete && !isRescue {
            print("❌ [Parser] Rejected '\(filePath)': Incomplete block but loading finished (Truncated?)")
            return
        }

        processedPaths.insert(filePath)

        let (summary, added, removed) = calculateChangeSummary(filePath: filePath, newContent: block.code, projectURL: projectURL)
        let finalStreamingState = isRescue ? false : (!block.isComplete || isLoading)

        let fileInfo = StreamingFileInfo(
            id: filePath,
            path: filePath,
            name: URL(fileURLWithPath: filePath).lastPathComponent,
            language: block.language,
            content: block.code,
            isStreaming: finalStreamingState,
            changeSummary: summary,
            addedLines: added,
            removedLines: removed
        )

        if let existingIndex = newFiles.firstIndex(where: { $0.id == filePath }) {
            if !finalStreamingState || newFiles[existingIndex].isStreaming {
                newFiles[existingIndex] = fileInfo
                print("✅ [Parser] Updated existing file: \(filePath)")
            }
        } else {
            newFiles.append(fileInfo)
            print("✅ [Parser] Added new file: \(filePath)")
        }
    }
    
    private func parseJSONEdits(content: String, projectURL: URL?) -> [CodePatch]? {
        let patchGenerator = PatchGeneratorService.shared
        let patches = patchGenerator.generatePatches(from: content, projectURL: projectURL)
        return patches.filter { $0.range != nil }.isEmpty ? nil : patches
    }
    
    // NOTE: Regex-based match processing removed in favor of fence-based parsing above.
    
    func detectLanguage(from path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        case "yml", "yaml": return "yaml"
        case "c": return "c"
        case "cpp", "cc": return "cpp"
        case "h": return "c"
        case "java": return "java"
        case "go": return "go"
        case "rs": return "rust"
        default: return "text"
        }
    }
    
    func calculateChangeSummary(filePath: String, newContent: String, projectURL: URL?) -> (summary: String?, added: Int, removed: Int) {
        guard let projectURL = projectURL else {
            return ("New file", newContent.components(separatedBy: .newlines).count, 0)
        }
        
        let fileURL = projectURL.appendingPathComponent(filePath)
        let newLines = newContent.components(separatedBy: .newlines)
        
        if FileManager.default.fileExists(atPath: fileURL.path),
           let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            let existingLines = existingContent.components(separatedBy: .newlines)
            let added = max(0, newLines.count - existingLines.count)
            let removed = max(0, existingLines.count - newLines.count)
            
            if added > 0 && removed > 0 {
                return ("Modified: +\(added) -\(removed) lines", added, removed)
            } else if added > 0 {
                return ("Added \(added) line\(added == 1 ? "" : "s")", added, removed)
            } else if removed > 0 {
                return ("Removed \(removed) line\(removed == 1 ? "" : "s")", added, removed)
            } else {
                return ("No changes", 0, 0)
            }
        } else {
            return ("New file: \(newLines.count) lines", newLines.count, 0)
        }
    }
}
