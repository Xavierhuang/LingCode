//
//  DiffBarView.swift
//  LingCode
//
//  Floating bar over the main editor when showing red/green diff: Undo (revert) and Keep (accept).
//

import SwiftUI

struct DiffBarView: View {
    let onUndo: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUndo) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                    Text("Undo")
                        .font(.system(size: 12, weight: .medium))
                    Text("Z")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(2)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .keyboardShortcut("z", modifiers: .command)
            .help("Revert file to original content (Undo)")

            Button(action: onKeep) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                    Text("Keep")
                        .font(.system(size: 12, weight: .medium))
                    Text("Y")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .keyboardShortcut("y", modifiers: .command)
            .help("Accept changes and clear diff (Keep)")
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

/// Compact Undo/Keep pair for one diff hunk (no shortcut labels).
struct DiffHunkBarView: View {
    let index: Int
    let onUndo: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onUndo) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                    Text("Undo")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Revert this change")

            Button(action: onKeep) {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10))
                    Text("Keep")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Accept this change")
        }
    }
}

private struct HunkRow: Identifiable {
    let id: Int
    let spacerHeight: CGFloat
    let index: Int
}

/// Column of per-hunk Undo/Keep buttons positioned by line (same scroll as diff). Uses lineYPositions when provided for exact alignment.
struct DiffHunkButtonsColumnView: View {
    let hunks: [DiffHunk]
    let lineHeight: CGFloat
    let totalLines: Int
    var topOffset: CGFloat = 0
    var lineYPositions: [CGFloat]? = nil
    let onHunkUndo: (Int) -> Void
    let onHunkKeep: (Int) -> Void
    private let buttonRowHeight: CGFloat = 32

    private var rows: [HunkRow] {
        var result: [HunkRow] = []
        var y: CGFloat = 0
        let useExactY = lineYPositions != nil && lineYPositions!.count == hunks.count
        for (index, hunk) in hunks.enumerated() {
            let lineTop: CGFloat
            if useExactY, let ys = lineYPositions, index < ys.count {
                lineTop = ys[index]
            } else {
                lineTop = CGFloat(hunk.displayLineStart) * lineHeight + topOffset
            }
            let blockHeight = CGFloat(max(1, hunk.displayLineCount)) * lineHeight
            let blockCenterY = lineTop + blockHeight / 2
            let targetY = blockCenterY - buttonRowHeight / 2
            let spacer = max(0, targetY - y)
            result.append(HunkRow(id: index, spacerHeight: spacer, index: index))
            y = targetY + buttonRowHeight
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if row.spacerHeight > 0 {
                    Color.clear
                        .frame(height: row.spacerHeight)
                }
                DiffHunkBarView(
                    index: row.index,
                    onUndo: { onHunkUndo(row.index) },
                    onKeep: { onHunkKeep(row.index) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(width: 118, height: max(CGFloat(totalLines) * lineHeight, 400))
        .background(Color(NSColor.windowBackgroundColor).opacity(0.92))
    }
}
