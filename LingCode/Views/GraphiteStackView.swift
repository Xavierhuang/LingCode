//
//  GraphiteStackView.swift
//  LingCode
//
//  UI for managing Graphite stacked PRs
//  Solves "massive unreviewable PRs" problem
//

import SwiftUI

struct GraphiteStackView: View {
    let changes: [CodeChange]
    @State private var stackedPRs: [StackedPR] = []
    @State private var isCreating = false
    @State private var showRecommendation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            if showRecommendation {
                recommendationView
            }
            
            if !stackedPRs.isEmpty {
                stackVisualization
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            checkRecommendation()
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch")
                .foregroundColor(.blue)
            Text("Graphite Stack Manager")
                .font(.headline)
            Spacer()
            Button("Close") {
                // Close action
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var recommendationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Recommendation")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            let recommendation = ApplyCodeService.shared.getChangeRecommendation(changes)
            
            Text(recommendation.message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if case .useGraphiteStacking(_, let prs) = recommendation {
                Button("Create Stacked PRs (\(prs) PRs)") {
                    createStackedPRs()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var stackVisualization: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stack Visualization")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stackedPRs.enumerated()), id: \.element.branch) { index, pr in
                        PRCard(pr: pr, index: index, total: stackedPRs.count)
                    }
                }
            }
        }
    }
    
    private func checkRecommendation() {
        let recommendation = ApplyCodeService.shared.getChangeRecommendation(changes)
        showRecommendation = recommendation.shouldWarn
    }
    
    private func createStackedPRs() {
        isCreating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Get project URL (would come from view model)
            let projectURL = FileManager.default.homeDirectoryForCurrentUser
            
            let result = GraphiteService.shared.createStackedPR(
                changes: changes,
                baseBranch: "main",
                in: projectURL,
                maxFilesPerPR: 5,
                maxLinesPerPR: 200
            )
            
            DispatchQueue.main.async {
                isCreating = false
                switch result {
                case .success(let prs):
                    stackedPRs = prs
                case .failure(let error):
                    print("Failed to create stacked PRs: \(error)")
                }
            }
        }
    }
}

struct PRCard: View {
    let pr: StackedPR
    let index: Int
    let total: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PR \(pr.prNumber)/\(pr.totalPRs)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(pr.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "arrow.up.circle")
                .foregroundColor(.blue)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}





