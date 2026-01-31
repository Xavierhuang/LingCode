//
//  StreamingStateViews.swift
//  LingCode
//
//  State views extracted from CursorStreamingView to reduce file size
//

import SwiftUI

// MARK: - Generating View

struct StreamingGeneratingView: View {
    let streamingText: String
    let toolCallProgresses: [ToolCallProgress]
    let onApprove: (String) -> Void
    let onReject: (String) -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Animated progress indicator
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.blue)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Generating...")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("AI is writing code")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            // Pending tool calls
            if !toolCallProgresses.isEmpty {
                ToolCallProgressListView(
                    progresses: toolCallProgresses,
                    onApprove: onApprove,
                    onReject: onReject
                )
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
            }

            // Show live streaming text
            if !streamingText.isEmpty {
                StreamingLivePreview(text: streamingText)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
}

// MARK: - Live Preview

struct StreamingLivePreview: View {
    let text: String
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("Live Preview")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    // Content
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.sm)
                        .id("streaming-live")
                }
            }
            .frame(maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
            .onChange(of: text.count) { _, _ in
                withAnimation(.none) {
                    proxy.scrollTo("streaming-live", anchor: .bottom)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Validating View

struct StreamingValidatingView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.orange)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Validating output...")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Checking code safety and correctness")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
}

// MARK: - Empty Output View

struct StreamingEmptyOutputView: View {
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No code changes detected")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("The AI response didn't include any file edits")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text("Try Again")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color.blue)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
}

// MARK: - Empty State View

struct StreamingEmptyStateView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.blue.opacity(0.7))
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Ready to assist")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Type a message to start")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
}

// MARK: - Blocked View

struct StreamingBlockedView: View {
    let reason: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Action Required")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(reason)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color.blue)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
}

// MARK: - Ready View

struct StreamingReadyView: View {
    let editCount: Int
    let onApplyAll: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Ready to apply")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("\(editCount) edit\(editCount == 1 ? "" : "s") ready")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Button(action: onApplyAll) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text("Apply All")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color.green)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
    }
}

// MARK: - Parse Failure View

struct StreamingParseFailureView: View {
    let rawOutput: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Parse Failed")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            
            Text("The AI output could not be parsed into executable edits. This may happen when the AI responds with explanations instead of code blocks.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !rawOutput.isEmpty {
                DisclosureGroup("Raw Output") {
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .padding()
    }
}
