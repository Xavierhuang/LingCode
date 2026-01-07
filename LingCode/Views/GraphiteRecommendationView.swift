//
//  GraphiteRecommendationView.swift
//  LingCode
//
//  Graphite recommendation view component
//

import SwiftUI

struct GraphiteRecommendationView: View {
    let parsedFiles: [StreamingFileInfo]
    let onCreateStack: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.blue)
                Text("Large Change Detected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            let recommendation = ApplyCodeService.shared.getChangeRecommendation(
                parsedFiles.map { file in
                    CodeChange(
                        id: UUID(),
                        filePath: file.path,
                        fileName: file.name,
                        operationType: .update,
                        originalContent: nil,
                        newContent: file.content,
                        lineRange: nil,
                        language: file.language
                    )
                }
            )
            
            Text(recommendation.message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if case .useGraphiteStacking(_, let prs) = recommendation {
                Button("Create Stacked PRs (\(prs) PRs)") {
                    onCreateStack()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

