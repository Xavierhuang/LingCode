//
//  ChangeHighlighter.swift
//  LingCode
//
//  Detects and highlights changes between original and modified code
//

import Foundation
import AppKit

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
