//
//  GraphiteRecommendationView.swift
//  LingCode
//
//  Advisory info banner for large changes (non-blocking, low-emphasis)
//

import SwiftUI

struct GraphiteRecommendationView: View {
    let parsedFiles: [StreamingFileInfo]
    let onCreateStack: () -> Void
    
    var body: some View {
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
        
        // Only show for large changes that would benefit from stacking
        if case .useGraphiteStacking(_, _) = recommendation {
            largeChangeBanner
        } else {
            EmptyView()
        }
    }
    
    private var largeChangeBanner: some View {
        // Calculate file and line counts
        let fileCount = parsedFiles.count
        // Use actual added/removed lines if available, otherwise estimate from content
        let lineCount = parsedFiles.reduce(0) { total, file in
            let fileLines = (file.addedLines > 0 || file.removedLines > 0) 
                ? file.addedLines + file.removedLines
                : file.content.components(separatedBy: .newlines).count
            return total + fileLines
        }
        
        return HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Large change detected (\(fileCount) files, ~\(lineCount) lines). Consider splitting if creating PRs.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Split into stacked changes…") {
                onCreateStack()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

