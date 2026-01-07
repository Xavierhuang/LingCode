//
//  GitStatusView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct GitStatusView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var gitStatus: [GitFileStatus] = []
    @State private var isRefreshing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Git Status")
                    .font(.headline)
                Spacer()
                Button(action: {
                    refreshStatus()
                }) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            if gitStatus.isEmpty {
                VStack {
                    Spacer()
                    Text("No changes")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(gitStatus) { status in
                    GitStatusRow(status: status) {
                        if let url = viewModel.rootFolderURL {
                            let fileURL = url.appendingPathComponent(status.path)
                            viewModel.openFile(at: fileURL)
                        }
                    }
                }
            }
        }
        .frame(width: 250)
        .onAppear {
            refreshStatus()
        }
        .onChange(of: viewModel.rootFolderURL) { oldValue, newValue in
            refreshStatus()
        }
    }
    
    private func refreshStatus() {
        guard let rootURL = viewModel.rootFolderURL,
              GitService.shared.isGitRepository(rootURL) else {
            gitStatus = []
            return
        }
        
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let status = GitService.shared.getStatus(for: rootURL)
            DispatchQueue.main.async {
                self.gitStatus = status
                self.isRefreshing = false
            }
        }
    }
}

extension GitFileStatus: Identifiable {
    var id: String { path }
}

struct GitStatusRow: View {
    let status: GitFileStatus
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .frame(width: 16)
                
                Text(status.path)
                    .font(.system(size: 12))
                    .lineLimit(1)
                
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var statusIcon: String {
        switch status.status {
        case .modified: return "circle.fill"
        case .added: return "plus.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .untracked: return "questionmark.circle.fill"
        case .clean: return "checkmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status.status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .untracked: return .blue
        case .clean: return .gray
        }
    }
}

