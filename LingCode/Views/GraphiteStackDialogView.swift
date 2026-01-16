//
//  GraphiteStackDialogView.swift
//  LingCode
//
//  Dialog for creating and managing Graphite stacks
//

import SwiftUI

struct GraphiteStackDialogView: View {
    let plan: StackingPlan
    let workspaceURL: URL
    @Binding var isCreating: Bool
    let onDismiss: () -> Void
    let onStackCreated: ([StackedPR]) -> Void
    
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Create Stacked PRs")
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
            
            // Stack preview
            Text("This will split your changes into \(plan.layers.count) logical PRs:")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.layers.enumerated()), id: \.offset) { index, layer in
                        LayerPreviewView(
                            layer: layer,
                            prNumber: index + 1,
                            totalPRs: plan.layers.count,
                            changes: plan.getChangesForLayer(layer, from: plan.allChanges)
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
            
            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: createStack) {
                    if isCreating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Creating...")
                        }
                    } else {
                        Text("Create Stack")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
        }
        .padding(20)
        .frame(width: 600, height: 500)
    }
    
    private func createStack() {
        isCreating = true
        errorMessage = nil
        
        GraphiteService.shared.createStack(
            from: plan,
            baseBranch: "main",
            in: workspaceURL
        ) { result in
            DispatchQueue.main.async {
                isCreating = false
                
                switch result {
                case .success(let stackedPRs):
                    // Submit stack to GitHub
                    GraphiteService.shared.submitStack(in: workspaceURL) { submitResult in
                        DispatchQueue.main.async {
                            switch submitResult {
                            case .success:
                                onStackCreated(stackedPRs)
                            case .failure(let error):
                                errorMessage = "Failed to submit stack: \(error.localizedDescription)"
                            }
                        }
                    }
                case .failure(let error):
                    errorMessage = "Failed to create stack: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct LayerPreviewView: View {
    let layer: StackingLayer
    let prNumber: Int
    let totalPRs: Int
    let changes: [CodeChange]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PR \(prNumber)/\(totalPRs): \(layer.name)")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text("\(changes.count) files")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Text(layer.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            // File list
            VStack(alignment: .leading, spacing: 2) {
                ForEach(changes.prefix(5), id: \.id) { change in
                    Text("  • \(change.fileName)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if changes.count > 5 {
                    Text("  ... and \(changes.count - 5) more")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}
