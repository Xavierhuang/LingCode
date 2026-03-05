//
//  AgentApprovalDialog.swift
//  LingCode
//
//  Dialog for approving or denying agent actions.
//  Includes an "Add to Allowlist & Run" button so the user can
//  permanently skip future approval for this command pattern.
//

import SwiftUI

struct AgentApprovalDialog: View {
    let decision: AgentDecision
    let reason: String
    let onApprove: () -> Void
    let onDeny: () -> Void
    /// Called with the pattern the user chose to allowlist, then approve.
    var onAllowlist: ((String) -> Void)? = nil

    @State private var addedToAllowlist = false

    // Extract the base command token for the default allowlist pattern
    private var suggestedPattern: String {
        guard let cmd = decision.command else { return "" }
        // Suggest the first word (e.g. "npm" from "npm run build")
        return cmd.components(separatedBy: .whitespaces).first ?? cmd
    }

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
        .frame(width: 520)
    }

    // MARK: - Header

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

    // MARK: - Reason

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

    // MARK: - Action details

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

    // MARK: - Buttons

    private var buttonsView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Deny
                Button("Deny") { onDeny() }
                    .buttonStyle(.bordered)
                    .tint(.red)

                Spacer()

                // Add to allowlist & Run (only for terminal commands)
                if decision.action == "terminal", !suggestedPattern.isEmpty, let onAllowlist = onAllowlist {
                    Button {
                        CommandAllowlistService.shared.add(pattern: suggestedPattern,
                            note: "Added from approval dialog")
                        addedToAllowlist = true
                        onAllowlist(suggestedPattern)
                        onApprove()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: addedToAllowlist ? "checkmark.circle.fill" : "plus.circle")
                            Text("Add \"\(suggestedPattern)\" to Allowlist & Run")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .help("Run now and never ask again for commands starting with \"\(suggestedPattern)\"")
                }

                // Approve once
                Button("Approve Once") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }

            // Allowlist hint
            if decision.action == "terminal" {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("You can manage the allowlist in Settings → Agent.")
                        .font(.caption2)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
