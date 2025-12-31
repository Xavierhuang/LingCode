//
//  UsageIndicatorView.swift
//  LingCode
//
//  Shows usage stats in status bar
//

import SwiftUI

struct UsageIndicatorView: View {
    @ObservedObject private var usageService = UsageTrackingService.shared
    @State private var showDashboard = false
    
    var body: some View {
        Button(action: { showDashboard = true }) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar")
                    .font(.caption)
                Text("\(usageService.currentUsage.requestCount)")
                    .font(.caption)
                
                if usageService.rateLimitStatus.isNearLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                }
            }
            .foregroundColor(usageService.rateLimitStatus.isAtLimit ? .red : .secondary)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Click to view usage dashboard")
        .sheet(isPresented: $showDashboard) {
            UsageDashboardView()
        }
    }
}





