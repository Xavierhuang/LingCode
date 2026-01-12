//
//  PlanModeView.swift
//  LingCode
//
//  Plan Mode - Shows planning and thinking process
//

import SwiftUI

struct PlanModeView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.blue)
                Text("Plan Mode")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Show current plan if available
                    if let plan = viewModel.currentPlan {
                        PlanCard(plan: plan)
                    }
                    
                    // Show thinking steps
                    if !viewModel.thinkingSteps.isEmpty {
                        ThinkingStepsCard(steps: viewModel.thinkingSteps)
                    }
                    
                    // Empty state
                    if viewModel.currentPlan == nil && viewModel.thinkingSteps.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("Plan Mode")
                                .font(.headline)
                            
                            Text("Ask the AI to plan a task, and you'll see the planning process here.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Input area
            StreamingInputView(
                viewModel: viewModel,
                editorViewModel: editorViewModel,
                activeMentions: .constant([]),
                onSendMessage: { },
                onImageDrop: { _ in false }
            )
        }
    }
}

struct PlanCard: View {
    let plan: AIPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.blue)
                Text("Plan")
                    .font(.headline)
                Spacer()
            }
            
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                    Text(step)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ThinkingStepsCard: View {
    let steps: [AIThinkingStep]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("Thinking Process")
                    .font(.headline)
                Spacer()
            }
     
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: step.type == .thinking ? "brain.head.profile" : "list.bullet.rectangle")
                        .font(.system(size: 11))
                        .foregroundColor(step.type == .thinking ? .purple : .blue)
                        .frame(width: 16)
                    Text(step.content)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
}
