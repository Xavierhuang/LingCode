//
//  GraphiteRecommendationBadge.swift
//  LingCode
//
//  Badge recommending Graphite for large changes
//

import SwiftUI

struct GraphiteRecommendationBadge: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                Text("Stack PRs")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Create stacked PRs with Graphite")
    }
}





