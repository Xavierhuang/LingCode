//
//  ThinkingProcessView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct ThinkingProcessView: View {
    @ObservedObject var viewModel: AIViewModel
    
    var body: some View {
        // Show thinking process when loading OR when there are steps/plan
        if viewModel.showThinkingProcess && (viewModel.isLoading || !viewModel.thinkingSteps.isEmpty || viewModel.currentPlan != nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                    Text("Thinking Process")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Cancel button when loading
                    if viewModel.isLoading {
                        Button(action: {
                            viewModel.cancelGeneration()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.caption2)
                                Text("Stop")
                                    .font(.caption)
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button(action: {
                        viewModel.showThinkingProcess.toggle()
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Show loading indicator if no steps yet
                        if viewModel.isLoading && viewModel.thinkingSteps.isEmpty && viewModel.currentPlan == nil {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("AI is thinking...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                        
                        // Show plan if available
                        if let plan = viewModel.currentPlan {
                            PlanView(plan: plan)
                        }
                        
                        // Show thinking steps
                        ForEach(viewModel.thinkingSteps) { step in
                            ThinkingStepView(step: step)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step.id)
                        }
                        
                        // Show streaming text if available
                        if viewModel.isLoading, let lastMessage = viewModel.conversation.messages.last(where: { $0.role == .assistant }),
                           !lastMessage.content.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "text.bubble")
                                        .foregroundColor(.blue)
                                    Text("Streaming Response")
                                        .font(.headline)
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                
                                ScrollView {
                                    Text(lastMessage.content)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 200)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .padding()
                        }
                        
                        // Show actions
                        if !viewModel.currentActions.isEmpty {
                            ActionsView(actions: viewModel.currentActions)
                        }
                        
                        // Show streaming indicator if still loading
                        if viewModel.isLoading && (!viewModel.thinkingSteps.isEmpty || viewModel.currentPlan != nil) {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Processing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}

struct PlanView: View {
    let plan: AIPlan
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.blue)
                Text("Plan")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text(step)
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                    .opacity(isVisible ? 1.0 : 0)
                    .offset(x: isVisible ? 0 : -20)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.05), value: isVisible)
                }
            }
            .padding(.leading, 8)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .onAppear {
            withAnimation {
                isVisible = true
            }
        }
    }
}

struct ThinkingStepView: View {
    let step: AIThinkingStep
    @State private var isVisible = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon based on step type with pulse animation
            Image(systemName: iconForStepType(step.type))
                .foregroundColor(colorForStepType(step.type))
                .frame(width: 20)
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.1), value: isVisible)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleForStepType(step.type))
                    .font(.headline)
                    .foregroundColor(colorForStepType(step.type))

                Text(step.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let result = step.actionResult {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    .transition(.scale.combined(with: .opacity))
                }

                if !step.isComplete && step.type == .action {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Executing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding()
        .background(backgroundColorForStepType(step.type))
        .cornerRadius(8)
        .opacity(isVisible ? 1.0 : 0)
        .offset(y: isVisible ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                isVisible = true
            }
        }
    }
    
    private func iconForStepType(_ type: ThinkingStepType) -> String {
        switch type {
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "brain.head.profile"
        case .action: return "gearshape"
        case .result: return "checkmark.circle"
        case .complete: return "checkmark.circle.fill"
        }
    }
    
    private func colorForStepType(_ type: ThinkingStepType) -> Color {
        switch type {
        case .planning: return .blue
        case .thinking: return .purple
        case .action: return .orange
        case .result: return .green
        case .complete: return .green
        }
    }
    
    private func backgroundColorForStepType(_ type: ThinkingStepType) -> Color {
        switch type {
        case .planning: return Color.blue.opacity(0.1)
        case .thinking: return Color.purple.opacity(0.1)
        case .action: return Color.orange.opacity(0.1)
        case .result: return Color.green.opacity(0.1)
        case .complete: return Color.green.opacity(0.1)
        }
    }
    
    private func titleForStepType(_ type: ThinkingStepType) -> String {
        switch type {
        case .planning: return "Planning"
        case .thinking: return "Thinking"
        case .action: return "Action"
        case .result: return "Result"
        case .complete: return "Complete"
        }
    }
}

struct ActionsView: View {
    let actions: [AIAction]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.2")
                    .foregroundColor(.orange)
                Text("Actions")
                    .font(.headline)
            }
            
            ForEach(actions) { action in
                ActionRowView(action: action)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ActionRowView: View {
    let action: AIAction
    @State private var pulseAnimation = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status indicator with animation
            Group {
                switch action.status {
                case .pending:
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                case .executing:
                    ProgressView()
                        .scaleEffect(0.7)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulseAnimation)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulseAnimation)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.name)
                    .font(.headline)

                Text(action.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let result = action.result {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.top, 2)
                        .transition(.scale.combined(with: .opacity))
                }

                if let error = action.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .onChange(of: action.status) { oldStatus, newStatus in
            if newStatus == .completed || newStatus == .failed {
                pulseAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pulseAnimation = false
                }
            }
        }
    }
}

