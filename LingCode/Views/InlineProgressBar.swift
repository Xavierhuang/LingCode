//
//  InlineProgressBar.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct InlineProgressBar: View {
    @ObservedObject var viewModel: AIViewModel
    
    private var progress: Double {
        guard !viewModel.currentActions.isEmpty else { return 0 }
        let completed = Double(viewModel.currentActions.filter { $0.status == .completed }.count)
        return completed / Double(viewModel.currentActions.count)
    }
    
    private var currentFileName: String {
        if let executing = viewModel.currentActions.first(where: { $0.status == .executing }) {
            return executing.name.replacingOccurrences(of: "Create ", with: "")
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Creating files...")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if !currentFileName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text(currentFileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Text("\(viewModel.currentActions.filter { $0.status == .completed }.count)/\(viewModel.currentActions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { viewModel.cancelGeneration() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
    }
}



