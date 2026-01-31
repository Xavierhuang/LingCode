//
//  ThinkingProcessCard.swift
//  LingCode
//
//  Thinking process card extracted from CursorStreamingView
//

import SwiftUI

struct ThinkingProcessCard: View {
    @Binding var isExpanded: Bool
    let isLoading: Bool
    let thinkingSummary: String
    let thinkingSteps: [AIThinkingStep]
    let currentPlan: AIPlan?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                expandedContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    private var header: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                    .font(.system(size: 13))
                
                Text("Thinking Process")
                    .font(.system(size: 13, weight: .semibold))
                
                if !isExpanded {
                    Spacer()
                    Text(thinkingSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 4)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let plan = currentPlan {
                        planView(plan: plan)
                    }
                    
                    thinkingStepsView
                    
                    if thinkingSteps.count > 10 {
                        Text("... and \(thinkingSteps.count - 10) more thinking steps")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
        }
    }
    
    private func planView(plan: AIPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.blue)
                    .font(.system(size: 11))
                Text("Plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    
                    Text(step)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
    
    private var thinkingStepsView: some View {
        ForEach(Array(thinkingSteps.prefix(10))) { step in
            AIThinkingStepRow(step: step)
        }
    }
}

// MARK: - Thinking Step Row

struct AIThinkingStepRow: View {
    let step: AIThinkingStep
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(stepColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(step.content)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                
                if let result = step.actionResult {
                    Text(result)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    
    private var stepColor: Color {
        switch step.type {
        case .planning: return .blue
        case .thinking: return .purple
        case .action: return .green
        case .result: return .orange
        case .complete: return .gray
        }
    }
}
