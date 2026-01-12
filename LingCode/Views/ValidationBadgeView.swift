//
//  ValidationBadgeView.swift
//  LingCode
//
//  Shows validation status for code changes
//  Prevents "unintended deletions" issues
//

import SwiftUI

struct ValidationBadgeView: View {
    let validationResult: ValidationResult
    
    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(validationResult.recommendation)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .cornerRadius(4)
    }
    
    private var icon: some View {
        Group {
            switch validationResult.severity {
            case .critical:
                Image(systemName: "xmark.circle.fill")
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
            case .info:
                Image(systemName: "info.circle.fill")
            }
        }
    }
    
    private var backgroundColor: Color {
        switch validationResult.severity {
        case .critical:
            return Color.red.opacity(0.2)
        case .warning:
            return Color.orange.opacity(0.2)
        case .info:
            return Color.blue.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch validationResult.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}

struct ValidationIssuesView: View {
    let issues: [ValidationIssue]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.severity == .critical ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(issue.severity == .critical ? .red : .orange)
                    Text(issue.message)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}





