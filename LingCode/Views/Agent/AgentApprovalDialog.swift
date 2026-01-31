//
//  AgentApprovalDialog.swift
//  LingCode
//
//  Dialog for approving or denying agent actions
//

import SwiftUI

struct AgentApprovalDialog: View {
    let decision: AgentDecision
    let reason: String
    let onApprove: () -> Void
    let onDeny: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            headerView
            Divider()
            reasonView
            actionDetailsView
            Divider()
            buttonsView
        }
        .padding(24)
        .frame(width: 500)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 24))
            Text("Action Requires Approval")
                .font(.headline)
            Spacer()
        }
    }
    
    private var reasonView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reason:")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var actionDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action Details:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 6) {
                LabeledRow(label: "Type:", value: decision.action.capitalized)
                LabeledRow(label: "Description:", value: decision.displayDescription)
                
                if let command = decision.command {
                    LabeledRow(label: "Command:", value: command)
                }
                if let filePath = decision.filePath {
                    LabeledRow(label: "File:", value: filePath)
                }
                if let thought = decision.thought {
                    LabeledRow(label: "Reasoning:", value: thought)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var buttonsView: some View {
        HStack(spacing: 12) {
            Button("Deny") { onDeny() }
                .buttonStyle(.bordered)
                .tint(.red)
            
            Spacer()
            
            Button("Approve") { onApprove() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
    }
}

// MARK: - Labeled Row

struct LabeledRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}
