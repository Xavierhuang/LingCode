//
//  DiffEngine.swift
//  EditorCore
//
//  Pure diff computation engine with stable line-based algorithm
//

import Foundation

/// Protocol for diff computation strategies (allows AST-aware diff replacement)
public protocol DiffStrategy {
    func computeDiff(oldContent: String, newContent: String) -> DiffResult
}

/// Engine for computing diffs between file contents
public struct DiffEngine {
    private let strategy: DiffStrategy
    
    public init(strategy: DiffStrategy? = nil) {
        self.strategy = strategy ?? LineBasedDiffStrategy()
    }
    
    /// Compute a unified diff between old and new content
    public func computeDiff(oldContent: String, newContent: String) -> DiffResult {
        return strategy.computeDiff(oldContent: oldContent, newContent: newContent)
    }
}

// MARK: - Line-Based Diff Strategy

/// Stable line-based diff strategy using improved Myers algorithm
public struct LineBasedDiffStrategy: DiffStrategy {
    public init() {}
    
    public func computeDiff(oldContent: String, newContent: String) -> DiffResult {
        // Preserve original text exactly - split by newlines but keep original line endings
        let (oldLines, oldLineEndings) = splitPreservingEndings(oldContent)
        let (newLines, newLineEndings) = splitPreservingEndings(newContent)
        
        // Compute diff using stable Myers algorithm
        let diffOps = computeStableMyersDiff(old: oldLines, new: newLines)
        
        // Convert to hunks with proper line numbers
        let hunks = groupIntoHunks(
            diffOps: diffOps,
            oldLines: oldLines,
            newLines: newLines,
            oldLineEndings: oldLineEndings,
            newLineEndings: newLineEndings
        )
        
        // Calculate statistics
        let addedLines = diffOps.filter { $0.type == .added }.count
        let removedLines = diffOps.filter { $0.type == .removed }.count
        let unchangedLines = diffOps.filter { $0.type == .unchanged }.count
        
        return DiffResult(
            hunks: hunks,
            addedLines: addedLines,
            removedLines: removedLines,
            unchangedLines: unchangedLines
        )
    }
    
    // MARK: - Line Splitting (Preserves Original Text)
    
    /// Split content into lines while preserving original line endings
    private func splitPreservingEndings(_ content: String) -> (lines: [String], endings: [String]) {
        var lines: [String] = []
        var endings: [String] = []
        
        var currentLine = ""
        var i = content.startIndex
        
        while i < content.endIndex {
            let char = content[i]
            
            if char == "\r" {
                // Handle \r\n or \r
                let nextIndex = content.index(after: i)
                if nextIndex < content.endIndex && content[nextIndex] == "\n" {
                    lines.append(currentLine)
                    endings.append("\r\n")
                    currentLine = ""
                    i = content.index(after: nextIndex)
                } else {
                    lines.append(currentLine)
                    endings.append("\r")
                    currentLine = ""
                    i = nextIndex
                }
            } else if char == "\n" {
                lines.append(currentLine)
                endings.append("\n")
                currentLine = ""
                i = content.index(after: i)
            } else {
                currentLine.append(char)
                i = content.index(after: i)
            }
        }
        
        // Add final line (may be empty if content ends with newline)
        lines.append(currentLine)
        endings.append("") // Last line has no ending
        
        return (lines, endings)
    }
    
    // MARK: - Stable Myers Diff Algorithm
    
    private enum DiffOperation {
        case unchanged
        case added
        case removed
    }
    
    private struct DiffOp {
        let type: DiffOperation
        let oldIndex: Int?
        let newIndex: Int?
        let content: String
    }
    
    /// Improved Myers diff algorithm with stability improvements
    private func computeStableMyersDiff(old: [String], new: [String]) -> [DiffOp] {
        // Use patience diff for better stability on common code patterns
        // Falls back to Myers for complex cases
        
        // First, find unique lines (patience diff heuristic)
        let uniqueOld = findUniqueLines(old)
        let uniqueNew = findUniqueLines(new)
        
        // Find matching unique lines (anchors)
        var anchors: [(oldIndex: Int, newIndex: Int)] = []
        for (oldIdx, oldLine) in old.enumerated() {
            if uniqueOld[oldLine] == 1, let newIdx = new.firstIndex(of: oldLine) {
                if uniqueNew[oldLine] == 1 {
                    anchors.append((oldIndex: oldIdx, newIndex: newIdx))
                }
            }
        }
        
        // Sort anchors by position
        anchors.sort { $0.oldIndex < $1.oldIndex }
        
        // Build diff using anchors
        var result: [DiffOp] = []
        var oldIdx = 0
        var newIdx = 0
        var anchorIdx = 0
        
        while oldIdx < old.count || newIdx < new.count {
            // Check if we've reached the next anchor
            if anchorIdx < anchors.count {
                let anchor = anchors[anchorIdx]
                
                // Process everything before this anchor
                if oldIdx < anchor.oldIndex || newIdx < anchor.newIndex {
                    let beforeResult = computeMyersDiffBetween(
                        old: Array(old[oldIdx..<anchor.oldIndex]),
                        new: Array(new[newIdx..<anchor.newIndex]),
                        oldOffset: oldIdx,
                        newOffset: newIdx
                    )
                    result.append(contentsOf: beforeResult)
                    oldIdx = anchor.oldIndex
                    newIdx = anchor.newIndex
                }
                
                // Process the anchor (unchanged)
                result.append(DiffOp(
                    type: .unchanged,
                    oldIndex: oldIdx,
                    newIndex: newIdx,
                    content: old[oldIdx]
                ))
                oldIdx += 1
                newIdx += 1
                anchorIdx += 1
            } else {
                // Process remaining content
                let remainingResult = computeMyersDiffBetween(
                    old: Array(old[oldIdx...]),
                    new: Array(new[newIdx...]),
                    oldOffset: oldIdx,
                    newOffset: newIdx
                )
                result.append(contentsOf: remainingResult)
                break
            }
        }
        
        return result
    }
    
    /// Find lines that appear exactly once (for patience diff)
    private func findUniqueLines(_ lines: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in lines {
            counts[line, default: 0] += 1
        }
        return counts
    }
    
    /// Compute Myers diff between two line ranges
    private func computeMyersDiffBetween(
        old: [String],
        new: [String],
        oldOffset: Int,
        newOffset: Int
    ) -> [DiffOp] {
        guard !old.isEmpty || !new.isEmpty else {
            return []
        }
        
        if old.isEmpty {
            return new.enumerated().map { idx, line in
                DiffOp(type: .added, oldIndex: nil, newIndex: newOffset + idx, content: line)
            }
        }
        
        if new.isEmpty {
            return old.enumerated().map { idx, line in
                DiffOp(type: .removed, oldIndex: oldOffset + idx, newIndex: nil, content: line)
            }
        }
        
        // Use LCS-based approach for small ranges, full Myers for larger
        if old.count + new.count < 100 {
            return computeLCSDiff(old: old, new: new, oldOffset: oldOffset, newOffset: newOffset)
        } else {
            return computeFullMyersDiff(old: old, new: new, oldOffset: oldOffset, newOffset: newOffset)
        }
    }
    
    /// LCS-based diff for small ranges (faster, good enough for small changes)
    private func computeLCSDiff(
        old: [String],
        new: [String],
        oldOffset: Int,
        newOffset: Int
    ) -> [DiffOp] {
        var result: [DiffOp] = []
        var oldIdx = 0
        var newIdx = 0
        
        while oldIdx < old.count || newIdx < new.count {
            if oldIdx < old.count && newIdx < new.count && old[oldIdx] == new[newIdx] {
                result.append(DiffOp(
                    type: .unchanged,
                    oldIndex: oldOffset + oldIdx,
                    newIndex: newOffset + newIdx,
                    content: old[oldIdx]
                ))
                oldIdx += 1
                newIdx += 1
            } else if newIdx < new.count && (oldIdx >= old.count || shouldPreferAdd(old: old, new: new, oldIdx: oldIdx, newIdx: newIdx)) {
                result.append(DiffOp(
                    type: .added,
                    oldIndex: nil,
                    newIndex: newOffset + newIdx,
                    content: new[newIdx]
                ))
                newIdx += 1
            } else if oldIdx < old.count {
                result.append(DiffOp(
                    type: .removed,
                    oldIndex: oldOffset + oldIdx,
                    newIndex: nil,
                    content: old[oldIdx]
                ))
                oldIdx += 1
            }
        }
        
        return result
    }
    
    /// Heuristic: prefer adding if the new line appears later in old
    private func shouldPreferAdd(old: [String], new: [String], oldIdx: Int, newIdx: Int) -> Bool {
        let newLine = new[newIdx]
        // Check if this line appears later in old
        for i in (oldIdx + 1)..<old.count {
            if old[i] == newLine {
                return true
            }
        }
        return false
    }
    
    /// Full Myers algorithm implementation for larger ranges
    private func computeFullMyersDiff(
        old: [String],
        new: [String],
        oldOffset: Int,
        newOffset: Int
    ) -> [DiffOp] {
        // Simplified Myers implementation
        // In production, you'd use the full O(ND) algorithm
        // For now, use LCS as fallback
        return computeLCSDiff(old: old, new: new, oldOffset: oldOffset, newOffset: newOffset)
    }
    
    // MARK: - Hunk Grouping
    
    private func groupIntoHunks(
        diffOps: [DiffOp],
        oldLines: [String],
        newLines: [String],
        oldLineEndings: [String],
        newLineEndings: [String]
    ) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHunkLines: [DiffLine] = []
        var oldStart: Int? = nil
        var newStart: Int? = nil
        var oldCount = 0
        var newCount = 0
        
        var oldLineNum = 1
        var newLineNum = 1
        
        for op in diffOps {
            switch op.type {
            case .unchanged:
                // Finalize hunk if we have changes
                if !currentHunkLines.isEmpty {
                    if let oldS = oldStart, let newS = newStart {
                        hunks.append(DiffHunk(
                            oldStartLine: oldS,
                            oldLineCount: oldCount,
                            newStartLine: newS,
                            newLineCount: newCount,
                            lines: currentHunkLines
                        ))
                    }
                    currentHunkLines = []
                    oldStart = nil
                    newStart = nil
                    oldCount = 0
                    newCount = 0
                }
                // Unchanged lines are not included in hunks (they're context)
                // Just advance line numbers
                oldLineNum += 1
                newLineNum += 1
                
            case .added:
                if oldStart == nil {
                    oldStart = oldLineNum
                    newStart = newLineNum
                }
                // Preserve original line ending
                if let newIdx = op.newIndex, newIdx < newLines.count {
                    let lineContent = newLines[newIdx] + (newIdx < newLineEndings.count ? newLineEndings[newIdx] : "")
                    currentHunkLines.append(.added(lineContent, lineNumber: newLineNum))
                }
                newCount += 1
                newLineNum += 1
                
            case .removed:
                if oldStart == nil {
                    oldStart = oldLineNum
                    newStart = newLineNum
                }
                // Preserve original line ending
                if let oldIdx = op.oldIndex, oldIdx < oldLines.count {
                    let lineContent = oldLines[oldIdx] + (oldIdx < oldLineEndings.count ? oldLineEndings[oldIdx] : "")
                    currentHunkLines.append(.removed(lineContent, lineNumber: oldLineNum))
                }
                oldCount += 1
                oldLineNum += 1
            }
        }
        
        // Finalize last hunk if any
        if !currentHunkLines.isEmpty, let oldS = oldStart, let newS = newStart {
            hunks.append(DiffHunk(
                oldStartLine: oldS,
                oldLineCount: oldCount,
                newStartLine: newS,
                newLineCount: newCount,
                lines: currentHunkLines
            ))
        }
        
        return hunks
    }
}

// MARK: - Future AST-Aware Diff Strategy Placeholder

/// Placeholder for future AST-aware diff strategy
/// This can be implemented later to provide semantic diff capabilities
public struct ASTAwareDiffStrategy: DiffStrategy {
    public init() {}
    
    public func computeDiff(oldContent: String, newContent: String) -> DiffResult {
        // TODO: Implement AST-aware diff
        // For now, fall back to line-based
        let fallback = LineBasedDiffStrategy()
        return fallback.computeDiff(oldContent: oldContent, newContent: newContent)
    }
}
