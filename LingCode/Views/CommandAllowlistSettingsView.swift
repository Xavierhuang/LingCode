//
//  CommandAllowlistSettingsView.swift
//  LingCode
//
//  Settings screen for managing the agent command allowlist.
//  Pushed from SettingsView → Agent → Command Allowlist.
//

import SwiftUI

struct CommandAllowlistSettingsView: View {
    @ObservedObject private var allowlist = CommandAllowlistService.shared
    @State private var newPattern: String = ""
    @State private var showAddField = false
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        List {
            // ── About ──────────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commands on the allowlist run immediately without an approval dialog. Use command prefixes (e.g. \"npm\") to allow all matching commands, or exact strings for specific ones.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 16) {
                        infoChip("npm → allows any npm command")
                        infoChip("git status → exact match only")
                    }
                }
                .padding(.vertical, 4)
            }

            // ── Add entry ──────────────────────────────────────────────────
            Section("Add to Allowlist") {
                if showAddField {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        TextField("Command or prefix (e.g. npm, git status, python)", text: $newPattern)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(.body, design: .monospaced))
                            .focused($addFieldFocused)
                            .onSubmit { commitAdd() }
                        Button("Add") { commitAdd() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") {
                            newPattern = ""
                            showAddField = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showAddField = true
                        addFieldFocused = true
                    } label: {
                        Label("Add Command Pattern...", systemImage: "plus.circle")
                    }
                }
            }

            // ── Existing entries ───────────────────────────────────────────
            if !allowlist.allowlist.isEmpty {
                Section("Allowed Patterns (\(allowlist.allowlist.count))") {
                    ForEach(allowlist.allowlist) { entry in
                        AllowlistEntryRow(entry: entry) {
                            allowlist.remove(id: entry.id)
                        }
                    }
                    .onDelete { offsets in
                        allowlist.remove(at: offsets)
                    }
                }
            }

            // ── Blocked (always) ──────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Always blocked (cannot be allowlisted)", systemImage: "xmark.shield.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                    Text("rm -rf /, mkfs, dd if=/dev/zero, format c:")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Command Allowlist")
        .toolbar {
            if !allowlist.allowlist.isEmpty {
                ToolbarItem {
                    Button(role: .destructive) {
                        allowlist.clear()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func commitAdd() {
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        CommandAllowlistService.shared.add(pattern: pattern)
        newPattern = ""
        showAddField = false
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
    }
}

// MARK: - Entry row

private struct AllowlistEntryRow: View {
    let entry: CommandAllowlistService.AllowlistEntry
    let onRemove: () -> Void

    private var df: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.pattern)
                    .font(.system(.body, design: .monospaced))
                HStack(spacing: 8) {
                    Text("Added \(df.string(from: entry.addedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !entry.note.isEmpty {
                        Text("·")
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text(entry.note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Remove from allowlist")
        }
        .padding(.vertical, 2)
    }
}
