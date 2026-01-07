//
//  CodeReviewView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct CodeReviewView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: EditorViewModel
    @StateObject private var reviewService = AICodeReviewService.shared
    
    @State private var reviewResult: CodeReviewResult?
    @State private var selectedIssue: CodeReviewIssue?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.shield")
                Text("AI Code Review")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if reviewService.isReviewing {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Analyzing code...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = reviewResult {
                // Results view
                HSplitView {
                    // Issues list
                    VStack(spacing: 0) {
                        // Score header
                        HStack {
                            ScoreGauge(score: result.score)
                            
                            VStack(alignment: .leading) {
                                Text("Code Score")
                                    .font(.headline)
                                Text("\(result.issues.count) issues found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        
                        // Summary
                        if !result.summary.isEmpty {
                            Text(result.summary)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.1))
                        }
                        
                        Divider()
                        
                        // Issues list
                        List {
                            ForEach(result.issues) { issue in
                                IssueRowView(issue: issue, isSelected: selectedIssue?.id == issue.id)
                                    .onTapGesture {
                                        selectedIssue = issue
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                    .frame(minWidth: 300)
                    
                    Divider()
                    
                    // Issue details
                    if let issue = selectedIssue {
                        IssueDetailView(issue: issue, onApplySuggestion: {
                            // Apply suggestion to code
                        })
                    } else {
                        VStack {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Select an issue to view details")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                // Initial state
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                    
                    Text("AI Code Review")
                        .font(.title)
                    
                    Text("Get AI-powered feedback on your code quality, security, and best practices")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    Button(action: startReview) {
                        Label("Start Review", systemImage: "play.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.editorState.activeDocument == nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 800, height: 600)
    }
    
    private func startReview() {
        guard let document = viewModel.editorState.activeDocument else { return }
        
        reviewService.reviewCode(
            document.content,
            language: document.language,
            fileName: document.displayName
        ) { result in
            switch result {
            case .success(let review):
                self.reviewResult = review
            case .failure(let error):
                print("Review failed: \(error)")
            }
        }
    }
}

struct ScoreGauge: View {
    let score: Int
    
    var color: Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text("\(score)")
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(width: 60, height: 60)
    }
}

struct IssueRowView: View {
    let issue: CodeReviewIssue
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: iconForSeverity(issue.severity))
                .foregroundColor(colorForSeverity(issue.severity))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message)
                    .font(.body)
                    .lineLimit(2)
                
                HStack {
                    Text(issue.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                    
                    if let line = issue.lineNumber {
                        Text("Line \(line)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
    
    private func iconForSeverity(_ severity: CodeReviewIssue.IssueSeverity) -> String {
        switch severity {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .style: return "paintbrush.fill"
        }
    }
    
    private func colorForSeverity(_ severity: CodeReviewIssue.IssueSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .style: return .purple
        }
    }
}

struct IssueDetailView: View {
    let issue: CodeReviewIssue
    let onApplySuggestion: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: iconForSeverity(issue.severity))
                        .font(.title)
                        .foregroundColor(colorForSeverity(issue.severity))
                    
                    VStack(alignment: .leading) {
                        Text(issue.severity.rawValue)
                            .font(.headline)
                        Text(issue.category.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Message
                VStack(alignment: .leading, spacing: 4) {
                    Text("Issue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(issue.message)
                        .font(.body)
                }
                
                // Location
                if let line = issue.lineNumber {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Line \(line)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                // Suggestion
                if let suggestion = issue.suggestion {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(suggestion)
                            .font(.body)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        
                        Button(action: onApplySuggestion) {
                            Label("Apply Suggestion", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func iconForSeverity(_ severity: CodeReviewIssue.IssueSeverity) -> String {
        switch severity {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .style: return "paintbrush.fill"
        }
    }
    
    private func colorForSeverity(_ severity: CodeReviewIssue.IssueSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .style: return .purple
        }
    }
}

