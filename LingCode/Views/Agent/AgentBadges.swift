//
//  AgentBadges.swift
//  LingCode
//
//  Badge components for agent status display
//

import SwiftUI

// MARK: - Status Badge

struct StatusBadge: View {
    let status: AgentHistoryItem.AgentTaskStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(4)
    }
    
    private var statusLabel: String {
        switch status {
        case .running: return "In progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Steps Badge

struct StepsBadge: View {
    let stepsCount: Int

    var body: some View {
        HStack(spacing: 4) {
            PulseDot(color: .accentColor, size: 6, minScale: 0.8, maxScale: 1.0, minOpacity: 0.6, maxOpacity: 1.0, duration: 1.0)
            Text(stepsCount == 0 ? "Connecting..." : "\(stepsCount) step\(stepsCount == 1 ? "" : "s")")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Attached Image Thumbnail

struct AttachedImageThumbnail: View {
    let image: AttachedImage
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipped()
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 6, y: -6)
        }
        .frame(width: 60, height: 60)
    }
}
