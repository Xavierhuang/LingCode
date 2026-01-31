//
//  ToolCallProgressView.swift
//  LingCode
//
//  UI for showing tool call progress and approval
//

import SwiftUI

struct ToolCallProgressView: View {
    let progress: ToolCallProgress
    let onApprove: (() -> Void)?
    let onReject: (() -> Void)?

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: progress.icon)
                .foregroundColor(progress.color)
                .font(.system(size: 14, weight: .medium))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(progress.message.isEmpty ? progress.displayMessage : progress.message)
                    .font(DesignSystem.Typography.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                if !progress.message.isEmpty {
                    Text(progress.displayMessage)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            if progress.status == .pending && (onApprove != nil || onReject != nil) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let onApprove = onApprove {
                        Button(action: {
                            withAnimation(DesignSystem.Animation.quick) {
                                onApprove()
                            }
                        }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(DesignSystem.Colors.success)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if let onReject = onReject {
                        Button(action: {
                            withAnimation(DesignSystem.Animation.quick) {
                                onReject()
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(DesignSystem.Colors.error)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else if progress.status == .executing {
                ProgressView()
                    .scaleEffect(0.7)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .animation(DesignSystem.Animation.smooth, value: progress.status)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .leading)),
            removal: .opacity.combined(with: .move(edge: .trailing))
        ))
    }
}

struct ToolCallProgressListView: View {
    let progresses: [ToolCallProgress]
    let onApprove: ((String) -> Void)?
    let onReject: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if !progresses.isEmpty {
                Text("Tool Calls")
                    .font(DesignSystem.Typography.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.sm)

                ForEach(progresses) { progress in
                    ToolCallProgressView(
                        progress: progress,
                        onApprove: onApprove != nil ? { onApprove?(progress.id) } : nil,
                        onReject: onReject != nil ? { onReject?(progress.id) } : nil
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                }
                .animation(DesignSystem.Animation.smooth, value: progresses.map(\.id))
            }
        }
    }
}
