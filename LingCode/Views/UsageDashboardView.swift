//
//  UsageDashboardView.swift
//  LingCode
//
//  Complete usage transparency dashboard
//  Addresses Cursor's "broken transparency" issues
//

import SwiftUI

struct UsageDashboardView: View {
    @ObservedObject private var usageService = UsageTrackingService.shared
    @State private var selectedPeriod: TimePeriod = .today
    @State private var showExportSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    periodSelector
                    overviewCards
                    rateLimitStatus
                    costBreakdown
                    usageHistory
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.blue)
            Text("Usage Dashboard")
                .font(.headline)
            Spacer()
            Button(action: { showExportSheet = true }) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
    
    private var periodSelector: some View {
        Picker("Period", selection: $selectedPeriod) {
            Text("Today").tag(TimePeriod.today)
            Text("This Week").tag(TimePeriod.thisWeek)
            Text("This Month").tag(TimePeriod.thisMonth)
            Text("All Time").tag(TimePeriod.allTime)
        }
        .pickerStyle(.segmented)
    }
    
    private var overviewCards: some View {
        let stats = usageService.getUsageStats(period: selectedPeriod)
        
        return HStack(spacing: 16) {
            StatCard(
                title: "Requests",
                value: "\(stats.requestCount)",
                icon: "arrow.clockwise",
                color: .blue
            )
            StatCard(
                title: "Tokens",
                value: formatNumber(stats.totalTokens),
                icon: "number",
                color: .green
            )
            StatCard(
                title: "Cost",
                value: String(format: "$%.2f", stats.totalCost),
                icon: "dollarsign.circle",
                color: .orange
            )
        }
    }
    
    private var rateLimitStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rate Limit Status")
                .font(.headline)
            
            let status = usageService.rateLimitStatus
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(status.provider.rawValue.capitalized)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(status.requestsUsed) / \(status.maxRequests)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                ProgressView(value: status.percentageUsed)
                    .tint(status.isNearLimit ? .orange : (status.isAtLimit ? .red : .green))
                
                if status.isNearLimit {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Approaching rate limit")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                if status.isAtLimit {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Rate limit reached. Resets at \(formatTime(status.resetTime))")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var costBreakdown: some View {
        let breakdown = usageService.getCostBreakdown(period: selectedPeriod)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Cost Breakdown")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                if !breakdown.byProvider.isEmpty {
                    Text("By Provider")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(breakdown.byProvider.keys.sorted()), id: \.self) { provider in
                        HStack {
                            Text(provider.capitalized)
                            Spacer()
                            Text(String(format: "$%.2f", breakdown.byProvider[provider] ?? 0))
                                .fontWeight(.medium)
                        }
                    }
                }
                
                Divider()
                
                if !breakdown.byModel.isEmpty {
                    Text("By Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(breakdown.byModel.keys.sorted()), id: \.self) { model in
                        HStack {
                            Text(model)
                                .font(.caption)
                            Spacer()
                            Text(String(format: "$%.2f", breakdown.byModel[model] ?? 0))
                                .fontWeight(.medium)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var usageHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage History")
                .font(.headline)
            
            Text("Detailed request history coming soon...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000.0)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000.0)
        }
        return "\(number)"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}





