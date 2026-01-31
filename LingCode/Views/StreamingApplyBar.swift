//
//  StreamingApplyBar.swift
//  LingCode
//
//  Apply button bar extracted from CursorStreamingView
//

import SwiftUI

struct StreamingApplyBar: View {
    let fileCount: Int
    let keptFilesCount: Int
    let allFilesKept: Bool
    let shouldOfferStacking: Bool
    let isVerifying: Bool
    let isApplyingFiles: Bool
    let verificationStatus: CursorStreamingVerificationStatus?
    
    let onUndo: () -> Void
    let onToggleKeepAll: () -> Void
    let onReview: () -> Void
    let onStack: () -> Void
    let onApplyAll: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // File count badge
            fileCountBadge
            
            Spacer()
            
            // Undo button
            undoButton
            
            // Keep button
            keepButton
            
            // Review button
            reviewButton
            
            // Smart Stack badge
            if shouldOfferStacking && GraphiteService.shared.isGraphiteInstalled() {
                stackButton
            }
            
            // Verification badge (including in-progress)
            if isVerifying {
                verifyingInProgressBadge
            } else if let status = verificationStatus {
                verificationBadge(status)
            }
            
            // Apply All button
            applyAllButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var fileCountBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
            Text("\(fileCount) File\(fileCount == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .medium))
                Text("Undo")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("Remove all files from view")
    }
    
    private var keepButton: some View {
        Button(action: onToggleKeepAll) {
            HStack(spacing: 4) {
                Image(systemName: allFilesKept && fileCount > 0 ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 10, weight: .medium))
                Text(allFilesKept && fileCount > 0 ? "Unkeep" : "Keep")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(allFilesKept && fileCount > 0 ? .purple : .secondary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(allFilesKept && fileCount > 0 ? Color.purple.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(allFilesKept && fileCount > 0 ? "Unkeep all files" : "Keep files visible without applying")
    }
    
    private var reviewButton: some View {
        Button(action: onReview) {
            HStack(spacing: 4) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Review")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("Review all file changes")
    }
    
    private var stackButton: some View {
        Button(action: onStack) {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11, weight: .medium))
                Text("Stack it?")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var verifyingInProgressBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text("Lint check")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Shadow verifying...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    private func verificationBadge(_ status: CursorStreamingVerificationStatus) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .success(let verificationTimeMs):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Lint passed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                    Text(verificationTimeLabel(verificationTimeMs))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            case .failure(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Verification failed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .help(message)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    private func verificationTimeLabel(_ verificationTimeMs: Int?) -> String {
        guard let ms = verificationTimeMs, ms >= 0 else { return "Shadow verified" }
        if ms < 1000 { return "Shadow verified (\(ms)ms)" }
        let sec = Double(ms) / 1000.0
        return String(format: "Shadow verified (%.1fs)", sec)
    }

    private var applyAllButton: some View {
        Button(action: onApplyAll) {
            HStack(spacing: 6) {
                if isVerifying || isApplyingFiles {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isVerifying ? "Verifying..." : (isApplyingFiles ? "Applying..." : "Apply All"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill((isVerifying || isApplyingFiles) ? Color.accentColor.opacity(0.7) : Color.accentColor)
                    .shadow(color: (isVerifying || isApplyingFiles) ? Color.clear : Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isVerifying || isApplyingFiles)
        .scaleEffect(isVerifying || isApplyingFiles ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isVerifying || isApplyingFiles)
    }
}

// Shared verification status enum
enum CursorStreamingVerificationStatus {
    case success(verificationTimeMs: Int?)
    case failure(String)
}
