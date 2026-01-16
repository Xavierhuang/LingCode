//
//  GraphiteStackView.swift
//  LingCode
//
//  Visualizes Graphite stack status and allows branch navigation
//  Beats Cursor by showing PR dependency graph and enabling instant branch switching
//

import SwiftUI

struct GraphiteStackView: View {
    let graphiteService = GraphiteService.shared
    let workspaceURL: URL
    @State private var stackStatus: StackStatus?
    @State private var isRefreshing = false
    @State private var selectedBranch: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stack Status")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Button(action: refreshStack) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRefreshing)
            }
            
            if let status = stackStatus, !status.branches.isEmpty {
                // Visual timeline of PRs
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(status.branches.enumerated()), id: \.offset) { index, branch in
                        StackNodeView(
                            branch: branch,
                            prNumber: index + 1,
                            totalPRs: status.totalPRs,
                            isSelected: selectedBranch == branch,
                            onSelect: {
                                checkoutBranch(branch)
                            }
                        )
                    }
                }
            } else {
                Text("No active stack")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            refreshStack()
        }
    }
    
    private func refreshStack() {
        isRefreshing = true
        stackStatus = graphiteService.getStackStatus(in: workspaceURL)
        isRefreshing = false
    }
    
    private func checkoutBranch(_ branch: String) {
        graphiteService.checkoutBranch(branch, in: workspaceURL) { result in
            switch result {
            case .success:
                selectedBranch = branch
                print("✅ Switched to branch: \(branch)")
            case .failure(let error):
                print("❌ Failed to checkout branch: \(error.localizedDescription)")
            }
        }
    }
}

struct StackNodeView: View {
    let branch: String
    let prNumber: Int
    let totalPRs: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator (circle)
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            // Branch name and PR number
            VStack(alignment: .leading, spacing: 2) {
                Text(branch)
                    .font(.system(size: 12, weight: .medium))
                
                Text("PR \(prNumber)/\(totalPRs)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
    }
    
    private var statusColor: Color {
        // In a real implementation, this would check PR status (merged, reviewing, local)
        // For now, use a simple color scheme
        if prNumber == 1 {
            return .green // Base PR (usually merged first)
        } else if prNumber == totalPRs {
            return .blue // Top PR (currently reviewing)
        } else {
            return .yellow // Middle PRs (in review)
        }
    }
}
