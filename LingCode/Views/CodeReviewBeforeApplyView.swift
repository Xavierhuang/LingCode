//
//  CodeReviewBeforeApplyView.swift
//  LingCode
//
//  Shows code review results before applying changes
//

import SwiftUI

struct CodeReviewBeforeApplyView: View {
    let reviewResult: CodeReviewResult
    let filePath: String
    let onDismiss: () -> Void
    let onApplyAnyway: () -> Void
    
    var criticalIssues: [CodeReviewIssue] {
        reviewResult.issues.filter { $0.severity == .critical }
    }
    
    var warnings: [CodeReviewIssue] {
        reviewResult.issues.filter { $0.severity == .warning }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(scoreColor)
                    Text("Code Review")
                        .font(DesignSystem.Typography.headline)
                }
                
                Spacer()
                
                // Score badge
                HStack(spacing: 4) {
                    Text("\(reviewResult.score)/100")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: scoreIcon)
                        .font(.system(size: 12))
                }
                .foregroundColor(scoreColor)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(scoreColor.opacity(0.1))
                )
            }
            .padding(DesignSystem.Spacing.md)
            
            Divider()
            
            // Summary
            if !reviewResult.summary.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Summary")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(.secondary)
                    Text(reviewResult.summary)
                        .font(DesignSystem.Typography.body)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            
            // Issues
            if !reviewResult.issues.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        // Critical issues
                        if !criticalIssues.isEmpty {
                            IssueSection(title: "Critical Issues", issues: criticalIssues, color: .red)
                        }
                        
                        // Warnings
                        if !warnings.isEmpty {
                            IssueSection(title: "Warnings", issues: warnings, color: .orange)
                        }
                        
                        // Other issues
                        let otherIssues = reviewResult.issues.filter { $0.severity != .critical && $0.severity != .warning }
                        if !otherIssues.isEmpty {
                            IssueSection(title: "Suggestions", issues: otherIssues, color: .blue)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
                .frame(maxHeight: 300)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if !criticalIssues.isEmpty {
                    Button("Apply Anyway") {
                        onApplyAnyway()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Apply") {
                        onApplyAnyway()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
        .frame(width: 500, height: 500)
        .background(DesignSystem.Colors.primaryBackground)
    }
    
    private var scoreColor: Color {
        if reviewResult.score >= 80 { return .green }
        if reviewResult.score >= 60 { return .orange }
        return .red
    }
    
    private var scoreIcon: String {
        if reviewResult.score >= 80 { return "checkmark.circle.fill" }
        if reviewResult.score >= 60 { return "exclamationmark.triangle.fill" }
        return "xmark.circle.fill"
    }
}

struct IssueSection: View {
    let title: String
    let issues: [CodeReviewIssue]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(color)
            
            ForEach(issues) { issue in
                IssueRow(issue: issue, color: color)
            }
        }
    }
}

struct IssueRow: View {
    let issue: CodeReviewIssue
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(issue.category.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(color)
                        
                        if let line = issue.lineNumber {
                            Text("• Line \(line)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(issue.message)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    
                    if let suggestion = issue.suggestion {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                            Text(suggestion)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(color.opacity(0.1))
        )
    }
}
