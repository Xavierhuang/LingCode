//
//  AgentReviewPanel.swift
//  LingCode
//
//  Sheet presented from GitPanelView after "Agent Review" is tapped.
//  Shows score, per-severity issue groups, per-file drill-down, and
//  an "Auto-fix X issues" button for all canAutoFix items.
//

import SwiftUI

struct AgentReviewPanel: View {
    let review: PRReview
    let projectURL: URL
    var onDismiss: () -> Void

    @ObservedObject private var bugbot = BugbotService.shared
    @State private var selectedFile: String? = nil
    @State private var isFixing = false
    @State private var fixCount = 0
    @State private var showFixDone = false

    // Group issues by severity
    private var critical: [PRIssue] { review.issues.filter { $0.severity == .critical } }
    private var warnings: [PRIssue] { review.issues.filter { $0.severity == .warning } }
    private var info:    [PRIssue] { review.issues.filter { $0.severity == .info } }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "ant.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
                Text("Agent Review")
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss() }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── Score + summary ───────────────────────────────────────────
            HStack(spacing: 16) {
                scoreCircle(review.overallScore)

                VStack(alignment: .leading, spacing: 4) {
                    Text(review.summary.components(separatedBy: "\n").first ?? review.summary)
                        .font(.subheadline)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        severityBadge(count: critical.count, severity: .critical)
                        severityBadge(count: warnings.count, severity: .warning)
                        severityBadge(count: info.count,     severity: .info)
                    }
                }

                Spacer()

                if review.autoFixable > 0 {
                    Button {
                        applyFixes()
                    } label: {
                        if isFixing {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        } else if showFixDone {
                            Label("Fixed \(fixCount)", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Auto-fix \(review.autoFixable)", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isFixing || showFixDone)
                }
            }
            .padding(16)

            Divider()

            // ── Issues list ───────────────────────────────────────────────
            if review.issues.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("No issues found")
                        .font(.headline)
                    Text("Code looks good!")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        if !critical.isEmpty {
                            issueSection(title: "Critical", issues: critical, color: .red)
                        }
                        if !warnings.isEmpty {
                            issueSection(title: "Warnings", issues: warnings, color: .orange)
                        }
                        if !info.isEmpty {
                            issueSection(title: "Info", issues: info, color: .blue)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sub-views

    private func scoreCircle(_ score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(scoreColor(score).opacity(0.2), lineWidth: 6)
                .frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 52, height: 52)
            Text("\(score)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(scoreColor(score))
        }
    }

    private func severityBadge(count: Int, severity: PRIssue.IssueSeverity) -> some View {
        guard count > 0 else { return AnyView(EmptyView()) }
        let color: Color = severity == .critical ? .red : severity == .warning ? .orange : .blue
        return AnyView(
            HStack(spacing: 3) {
                Image(systemName: severity.icon)
                Text("\(count)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
        )
    }

    private func issueSection(title: String, issues: [PRIssue], color: Color) -> some View {
        Section {
            ForEach(issues) { issue in
                PRIssueRow(issue: issue, projectURL: projectURL)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                Divider().padding(.leading, 16)
            }
        } header: {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color)
                Text("(\(issues.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 80 ? .green : score >= 60 ? .orange : .red
    }

    // MARK: - Actions

    private func applyFixes() {
        isFixing = true
        Task {
            do {
                let n = try await bugbot.applyAutoFixes(for: review, projectURL: projectURL)
                await MainActor.run {
                    fixCount = n
                    isFixing = false
                    showFixDone = true
                }
            } catch {
                await MainActor.run { isFixing = false }
            }
        }
    }
}

// MARK: - Issue row

private struct PRIssueRow: View {
    let issue: PRIssue
    let projectURL: URL
    @State private var expanded = false

    var color: Color {
        switch issue.severity {
        case .critical: return .red
        case .warning:  return .orange
        case .info:     return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: issue.severity.icon)
                        .foregroundColor(color)
                        .font(.system(size: 12))
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(URL(fileURLWithPath: issue.file).lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                            if let line = issue.line {
                                Text(":\(line)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Text(issue.category.rawValue)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(3)
                            if issue.canAutoFix {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 9))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        Text(issue.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(expanded ? nil : 1)
                    }

                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if expanded, let suggestion = issue.suggestion {
                Text(suggestion)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(color.opacity(0.06))
                    .cornerRadius(6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
