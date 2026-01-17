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
        HStack(spacing: 12) {
            // Icon
            Image(systemName: progress.icon)
                .foregroundColor(progress.color)
                .font(.system(size: 14, weight: .medium))
            
            // Message
            Text(progress.message)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status badge
            if progress.status == .pending && (onApprove != nil || onReject != nil) {
                HStack(spacing: 8) {
                    if let onApprove = onApprove {
                        Button(action: onApprove) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if let onReject = onReject {
                        Button(action: onReject) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else if progress.status == .executing {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct ToolCallProgressListView: View {
    let progresses: [ToolCallProgress]
    let onApprove: ((String) -> Void)?
    let onReject: ((String) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !progresses.isEmpty {
                Text("Tool Calls")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                ForEach(progresses) { progress in
                    ToolCallProgressView(
                        progress: progress,
                        onApprove: onApprove != nil ? { onApprove?(progress.id) } : nil,
                        onReject: onReject != nil ? { onReject?(progress.id) } : nil
                    )
                }
            }
        }
    }
}
