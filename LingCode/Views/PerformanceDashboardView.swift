//
//  PerformanceDashboardView.swift
//  LingCode
//
//  Performance metrics dashboard
//

import SwiftUI

struct PerformanceDashboardView: View {
    @ObservedObject var metricsService = PerformanceMetricsService.shared
    @State private var selectedTimeRange: TimeRange = .today
    
    enum TimeRange {
        case today
        case week
        case month
        case all
    }
    
    var filteredMetrics: [PerformanceMetrics] {
        let cutoff: Date
        switch selectedTimeRange {
        case .today:
            cutoff = Calendar.current.startOfDay(for: Date())
        case .week:
            cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .all:
            return metricsService.metrics
        }
        return metricsService.getMetrics(since: cutoff)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Performance Metrics")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                
                // Time range picker
                Picker("Time Range", selection: $selectedTimeRange) {
                    Text("Today").tag(TimeRange.today)
                    Text("Week").tag(TimeRange.week)
                    Text("Month").tag(TimeRange.month)
                    Text("All").tag(TimeRange.all)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(DesignSystem.Spacing.md)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    // Summary cards
                    HStack(spacing: DesignSystem.Spacing.md) {
                        MetricCard(
                            title: "Total Tokens",
                            value: "\(filteredMetrics.reduce(0) { $0 + $1.tokenCount })",
                            icon: "number",
                            color: .blue
                        )
                        
                        MetricCard(
                            title: "Total Cost",
                            value: String(format: "$%.2f", filteredMetrics.compactMap { $0.cost }.reduce(0, +)),
                            icon: "dollarsign.circle",
                            color: .green
                        )
                        
                        MetricCard(
                            title: "Avg Latency",
                            value: String(format: "%.1fs", metricsService.averageLatency),
                            icon: "clock",
                            color: .orange
                        )
                        
                        MetricCard(
                            title: "Success Rate",
                            value: String(format: "%.1f%%", metricsService.successRate * 100),
                            icon: "checkmark.circle",
                            color: .purple
                        )
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    
                    // Recent metrics
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Recent Requests")
                            .font(DesignSystem.Typography.headline)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                        
                        ForEach(filteredMetrics.suffix(10).reversed()) { metric in
                            MetricRow(metric: metric)
                        }
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Text(value)
                .font(DesignSystem.Typography.title2)
                .foregroundColor(.primary)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct MetricRow: View {
    let metric: PerformanceMetrics
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.requestType)
                    .font(.system(size: 12, weight: .medium))
                
                if let model = metric.model {
                    Text(model)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(metric.tokenCount) tokens")
                    .font(.system(size: 11))
                
                HStack(spacing: 4) {
                    Text(String(format: "%.2fs", metric.latency))
                        .font(.system(size: 10))
                    if let cost = metric.cost {
                        Text("• $\(String(format: "%.4f", cost))")
                            .font(.system(size: 10))
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(metric.success ? Color.clear : Color.red.opacity(0.1))
        )
    }
}
