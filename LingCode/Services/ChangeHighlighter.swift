//
//  ChangeHighlighter.swift
//  LingCode
//
//  Detects and highlights changes between original and modified code
//

import Foundation
import AppKit

/// One line in a line-level diff (for red/green display in main editor)
enum LineDiffEntry: Equatable {
    case unchanged(String)
    case removed(String)
    case added(String)
}

/// One contiguous block of changes (removed + added lines) for per-hunk Undo/Keep.
struct DiffHunk {
    let oldText: String
    let newText: String
    let rangeInOriginal: NSRange
    let rangeInModified: NSRange
    let displayLineStart: Int
    /// Number of display lines this hunk spans (e.g. 2 for one removed + one added).
    let displayLineCount: Int
}

class ChangeHighlighter {
    /// Detect changed ranges between original and modified text using line-based diff
    static func detectChangedRanges(original: String, modified: String) -> [NSRange] {
        guard !original.isEmpty else {
            // Entire file is new
            return modified.isEmpty ? [] : [NSRange(location: 0, length: modified.count)]
        }

        guard !modified.isEmpty else {
            return []
        }

        let originalLines = original.components(separatedBy: .newlines)
        let modifiedLines = modified.components(separatedBy: .newlines)

        // Simple line-based diff
        var changedRanges: [NSRange] = []
        var currentPosition = 0

        for (index, modifiedLine) in modifiedLines.enumerated() {
            let lineStart = currentPosition
            let lineLength = modifiedLine.count
            let lineEnd = lineStart + lineLength

            // Check if this line exists in the original
            let isNewOrModified: Bool
            if index < originalLines.count {
                isNewOrModified = originalLines[index] != modifiedLine
            } else {
                // This line is beyond the original content
                isNewOrModified = true
            }

            if isNewOrModified {
                // Include the newline character if not the last line
                let rangeLength = index < modifiedLines.count - 1 ? lineLength + 1 : lineLength
                if rangeLength > 0 {
                    changedRanges.append(NSRange(location: lineStart, length: rangeLength))
                }
            }

            // Move to next line (include newline character)
            currentPosition = lineEnd + 1
        }

        // Merge adjacent or overlapping ranges
        return mergeRanges(changedRanges)
    }

    /// Merge adjacent or overlapping ranges for cleaner highlighting
    private static func mergeRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }

        let sorted = ranges.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        var current = sorted[0]

        for next in sorted.dropFirst() {
            if NSMaxRange(current) >= next.location {
                // Ranges overlap or are adjacent - merge them
                let end = max(NSMaxRange(current), NSMaxRange(next))
                current = NSRange(location: current.location, length: end - current.location)
            } else {
                // No overlap - save current and move to next
                merged.append(current)
                current = next
            }
        }

        merged.append(current)
        return merged
    }

    /// Apply change highlighting to attributed string
    static func applyHighlighting(
        to attributedString: NSMutableAttributedString,
        ranges: [NSRange],
        baseFont: NSFont,
        theme: CodeTheme
    ) {
        // Highlight changed ranges with background color
        for range in ranges {
            // Ensure range is valid
            guard range.location >= 0,
                  range.location + range.length <= attributedString.length else {
                continue
            }

            // Apply background color for changes (subtle yellow/green tint)
            let highlightColor = NSColor.systemYellow.withAlphaComponent(0.15)
            attributedString.addAttribute(
                .backgroundColor,
                value: highlightColor,
                range: range
            )

            // Optionally add a subtle border effect using underline
            attributedString.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )

            attributedString.addAttribute(
                .underlineColor,
                value: NSColor.systemYellow.withAlphaComponent(0.4),
                range: range
            )
        }
    }

    // MARK: - Line-level diff for red/green in main editor

    /// Line-level diff (LCS-based) for unified red/green display.
    static func lineDiff(original: String, modified: String) -> [LineDiffEntry] {
        let oldLines = original.components(separatedBy: .newlines)
        let newLines = modified.components(separatedBy: .newlines)
        let lcsPairs = longestCommonSubsequenceIndices(old: oldLines, new: newLines)
        var result: [LineDiffEntry] = []
        var i = 0
        var j = 0
        for (mi, mj) in lcsPairs {
            while i < mi {
                result.append(.removed(oldLines[i]))
                i += 1
            }
            while j < mj {
                result.append(.added(newLines[j]))
                j += 1
            }
            if mi < oldLines.count {
                result.append(.unchanged(oldLines[mi]))
            }
            i = mi + 1
            j = mj + 1
        }
        while i < oldLines.count {
            result.append(.removed(oldLines[i]))
            i += 1
        }
        while j < newLines.count {
            result.append(.added(newLines[j]))
            j += 1
        }
        return result
    }

    /// Returns ordered (i,j) pairs of matching line indices (LCS).
    private static func longestCommonSubsequenceIndices(old: [String], new: [String]) -> [(Int, Int)] {
        let n = old.count
        let m = new.count
        guard n > 0, m > 0 else { return [] }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        var pairs: [(Int, Int)] = []
        var i = n
        var j = m
        while i > 0, j > 0 {
            if old[i - 1] == new[j - 1] {
                pairs.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return pairs.reversed()
    }

    /// Build display string and ranges for red (removed) and green (added) for use in the main editor. Ranges are UTF-16 for NSTextView.
    static func buildRedGreenDiffDisplay(original: String, modified: String) -> (displayString: String, removedRanges: [NSRange], addedRanges: [NSRange]) {
        let diff = lineDiff(original: original, modified: modified)
        var displayLines: [String] = []
        var removedRanges: [NSRange] = []
        var addedRanges: [NSRange] = []
        var pos: Int = 0
        for entry in diff {
            let line: String
            switch entry {
            case .unchanged(let s), .removed(let s), .added(let s):
                line = s
            }
            let lineWithNewline = line + "\n"
            let fullLineNS = lineWithNewline as NSString
            let fullLineLen = fullLineNS.length
            let range = NSRange(location: pos, length: fullLineLen)
            switch entry {
            case .unchanged:
                break
            case .removed:
                removedRanges.append(range)
            case .added:
                addedRanges.append(range)
            }
            displayLines.append(lineWithNewline)
            pos += fullLineLen
        }
        let displayString = displayLines.joined()
        return (displayString, mergeRanges(removedRanges), mergeRanges(addedRanges))
    }

    /// Returns hunks for per-change Undo/Keep. Each hunk is a contiguous block of removed and/or added lines with ranges in original and modified.
    static func diffHunks(original: String, modified: String) -> [DiffHunk] {
        let diff = lineDiff(original: original, modified: modified)
        let originalNS = original as NSString
        let modifiedNS = modified as NSString
        var hunks: [DiffHunk] = []
        var posOrig: Int = 0
        var posMod: Int = 0
        var displayLine: Int = 0
        var i = 0
        while i < diff.count {
            switch diff[i] {
            case .unchanged(let s):
                let line = s + "\n"
                posOrig += (line as NSString).length
                posMod += (line as NSString).length
                displayLine += 1
                i += 1
            case .removed, .added:
                let startOrig = posOrig
                let startMod = posMod
                let startDisplayLine = displayLine
                var oldLines: [String] = []
                var newLines: [String] = []
                while i < diff.count {
                    switch diff[i] {
                    case .unchanged:
                        break
                    case .removed(let s):
                        oldLines.append(s)
                        posOrig += (s + "\n" as NSString).length
                        displayLine += 1
                        i += 1
                    case .added(let s):
                        newLines.append(s)
                        posMod += (s + "\n" as NSString).length
                        displayLine += 1
                        i += 1
                    }
                    if i >= diff.count { break }
                    if case .unchanged = diff[i] { break }
                }
                let oldText = oldLines.joined(separator: "\n") + (oldLines.isEmpty ? "" : "\n")
                let newText = newLines.joined(separator: "\n") + (newLines.isEmpty ? "" : "\n")
                let rangeOrig = NSRange(location: startOrig, length: posOrig - startOrig)
                let rangeMod = NSRange(location: startMod, length: posMod - startMod)
                if rangeOrig.length > 0 || rangeMod.length > 0 {
                    let displayLineCount = displayLine - startDisplayLine
                    hunks.append(DiffHunk(
                        oldText: oldText,
                        newText: newText,
                        rangeInOriginal: rangeOrig,
                        rangeInModified: rangeMod,
                        displayLineStart: startDisplayLine,
                        displayLineCount: max(1, displayLineCount)
                    ))
                }
            }
        }
        return hunks
    }

    /// Apply red (removed) and green (added) highlighting to an attributed string.
    static func applyRedGreenHighlighting(
        to attributedString: NSMutableAttributedString,
        removedRanges: [NSRange],
        addedRanges: [NSRange],
        baseFont: NSFont,
        theme: CodeTheme
    ) {
        let redColor = NSColor.systemRed.withAlphaComponent(0.2)
        let greenColor = NSColor.systemGreen.withAlphaComponent(0.2)
        for range in removedRanges {
            guard range.location >= 0, range.location + range.length <= attributedString.length else { continue }
            attributedString.addAttribute(.backgroundColor, value: redColor, range: range)
        }
        for range in addedRanges {
            guard range.location >= 0, range.location + range.length <= attributedString.length else { continue }
            attributedString.addAttribute(.backgroundColor, value: greenColor, range: range)
        }
    }

    /// Create a gutter indicator for changed lines
    static func changedLineNumbers(ranges: [NSRange], in text: String) -> Set<Int> {
        var lineNumbers = Set<Int>()

        for range in ranges {
            let substring = (text as NSString).substring(with: NSRange(location: 0, length: min(range.location + range.length, text.count)))
            let lineNumber = substring.components(separatedBy: .newlines).count
            lineNumbers.insert(lineNumber)
        }

        return lineNumbers
    }
}
