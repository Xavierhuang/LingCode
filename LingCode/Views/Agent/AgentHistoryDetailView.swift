//
//  AgentHistoryDetailView.swift
//  LingCode
//
//  Detail view for viewing completed agent task history
//

import SwiftUI

struct AgentHistoryDetailView: View {
    let agent: AgentHistoryItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                agentInfoView
                stepsView
            }
            .padding()
        }
    }
    
    private var agentInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(agent.description)
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Text(agent.startTime, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()

                if agent.status == .running {
                    StepsBadge(stepsCount: agent.steps.count)
                } else {
                    StatusBadge(status: agent.status)
                }
            }
            
            if !agent.filesChanged.isEmpty {
                HStack {
                    Text("+\(agent.linesAdded) -\(agent.linesRemoved)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(".")
                        .foregroundColor(.secondary)
                    Text("\(agent.filesChanged.count) File\(agent.filesChanged.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var stepsView: some View {
        if !agent.steps.isEmpty {
            Text("Steps")
                .font(.headline)
                .padding(.horizontal)
            
            ForEach(agent.steps) { step in
                AgentStepHistoryRow(step: step)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Agent Step History Row

struct AgentStepHistoryRow: View {
    let step: AgentStepHistory
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            expandedOutputView
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            HistoryStatusIndicator(status: step.status)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(step.description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if let output = step.output, !output.isEmpty {
                    Text(output)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
    }
    
    @ViewBuilder
    private var expandedOutputView: some View {
        if isExpanded, let output = step.output, !output.isEmpty {
            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - History Status Indicator

struct HistoryStatusIndicator: View {
    let status: String
    
    var body: some View {
        Group {
            switch status.lowercased() {
            case "pending":
                Circle()
                    .strokeBorder(Color.gray, lineWidth: 2)
                    .frame(width: 16, height: 16)
            case "running":
                PulseDot(color: Color.accentColor.opacity(0.8), size: 10)
            case "completed":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            case "failed":
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
            case "cancelled":
                Image(systemName: "slash.circle")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
            default:
                Circle()
                    .strokeBorder(Color.gray, lineWidth: 2)
                    .frame(width: 16, height: 16)
            }
        }
    }
}
