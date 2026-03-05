//
//  RulesManagementView.swift
//  LingCode
//
//  Structured rules panel — mirrors Cursor's Settings → Rules.
//  Shows all rules from all sources in a list with enable/disable toggles,
//  apply-mode selector, file-pattern display, and team rules URL configuration.
//

import SwiftUI

// MARK: - Main view

struct RulesManagementView: View {
    let projectURL: URL?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var rulesService = RulesService.shared
    @StateObject private var lingcodeRules = LingCodeRulesService.shared
    @StateObject private var teamRulesService = TeamRulesService.shared

    @State private var selectedTab: RulesTab = .project
    @State private var editingRule: AIRule? = nil
    @State private var showAddUserRule = false
    @State private var showTeamRulesConfig = false

    enum RulesTab: String, CaseIterable {
        case project = "Project"
        case user = "User"
        case team = "Team"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarList
        } detail: {
            detailPane
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                primaryToolbarButton
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rule: rule, onSave: { updated in
                saveEditedRule(updated)
            })
        }
        .sheet(isPresented: $showAddUserRule) {
            RuleEditorSheet(rule: nil, onSave: { newRule in
                rulesService.addUserRule(newRule)
            })
        }
        .sheet(isPresented: $showTeamRulesConfig) {
            TeamRulesConfigView()
        }
        .onAppear {
            if let url = projectURL {
                rulesService.loadProjectRules(from: url)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarList: some View {
        List(selection: $selectedTab) {
            ForEach(RulesTab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: iconName(for: tab))
                    .tag(tab)
                    .badge(badgeCount(for: tab))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Rules")
    }

    private func iconName(for tab: RulesTab) -> String {
        switch tab {
        case .project: return "folder.badge.gearshape"
        case .user: return "person.crop.circle"
        case .team: return "person.2"
        }
    }

    private func badgeCount(for tab: RulesTab) -> Int {
        switch tab {
        case .project: return rulesService.projectRules.filter { $0.isEnabled }.count
        case .user: return rulesService.userRules.filter { $0.isEnabled }.count
        case .team: return (teamRulesService.isEnabled && !teamRulesService.teamRules.isEmpty) ? 1 : 0
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        switch selectedTab {
        case .project: projectRulesPane
        case .user: userRulesPane
        case .team: teamRulesPane
        }
    }

    @ViewBuilder
    private var primaryToolbarButton: some View {
        switch selectedTab {
        case .project:
            EmptyView()
        case .user:
            Button(action: { showAddUserRule = true }) {
                Label("Add Rule", systemImage: "plus")
            }
        case .team:
            Button(action: { showTeamRulesConfig = true }) {
                Label("Configure", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Project Rules Pane

    private var projectRulesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectRulesHeader
            Divider()
            if rulesService.projectRules.isEmpty {
                emptyProjectRules
            } else {
                projectRulesList
            }
        }
    }

    private var projectRulesHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Project Rules")
                .font(.headline)
            Text("Rules loaded from \(projectURL?.lastPathComponent ?? "project"). Sources: .cursor/rules/*.mdc, .cursorrules, WORKSPACE.md, .lingcoderules.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var emptyProjectRules: some View {
        ContentUnavailableView {
            Label("No Project Rules", systemImage: "doc.text")
        } description: {
            Text("Open a project with a .cursor/rules/ directory, WORKSPACE.md, or .cursorrules file.")
        }
    }

    private var projectRulesList: some View {
        let grouped = Dictionary(grouping: rulesService.projectRules, by: { $0.source })
        return List {
            ForEach(RuleSource.allCases.filter { src in grouped[src] != nil }, id: \.self) { src in
                Section(sectionTitle(for: src)) {
                    ForEach(grouped[src] ?? []) { rule in
                        RuleRowView(rule: rule, onToggle: { toggled in
                            updateProjectRuleEnabled(id: toggled.id, isEnabled: toggled.isEnabled)
                        }, onEdit: { r in
                            editingRule = r
                        })
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionTitle(for source: RuleSource) -> String {
        switch source {
        case .builtin: return "Built-in"
        case .project: return "Project Files (.cursorrules / .lingcoderules)"
        case .cursorDir: return ".cursor/rules/"
        case .user: return "User"
        case .workspace: return "WORKSPACE.md"
        }
    }

    // MARK: - User Rules Pane

    private var userRulesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("User Rules")
                    .font(.headline)
                Text("Personal rules applied across all projects. Stored in ~/Library/Application Support/LingCode/.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            Divider()
            globalRulesBlock
            Divider()
            if rulesService.userRules.isEmpty {
                emptyUserRules
            } else {
                userRulesList
            }
        }
    }

    private var globalRulesBlock: some View {
        DisclosureGroup {
            TextEditor(text: Binding(
                get: { lingcodeRules.globalRules },
                set: { newVal in
                    try? lingcodeRules.saveGlobalRules(newVal)
                }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 80, maxHeight: 160)
            .padding(4)
        } label: {
            HStack {
                Label("global_rules.md", systemImage: "globe")
                    .font(.subheadline)
                Spacer()
                if !lingcodeRules.globalRules.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyUserRules: some View {
        ContentUnavailableView {
            Label("No User Rules", systemImage: "person.crop.circle")
        } description: {
            Text("Add personal rules that apply to all your projects.")
        } actions: {
            Button("Add Rule") { showAddUserRule = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var userRulesList: some View {
        List {
            ForEach(rulesService.userRules) { rule in
                RuleRowView(rule: rule, onToggle: { toggled in
                    rulesService.updateUserRule(toggled)
                }, onEdit: { r in
                    editingRule = r
                })
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        rulesService.deleteUserRule(rule.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Team Rules Pane

    private var teamRulesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Team Rules")
                        .font(.headline)
                    Text("Shared rules fetched from a URL (file or https). Applied to all team members.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { teamRulesService.isEnabled },
                    set: { newVal in
                        if newVal {
                            teamRulesService.loadTeamRules()
                        } else {
                            teamRulesService.disable()
                        }
                    }
                ))
                .labelsHidden()
            }
            .padding()
            Divider()

            if let url = teamRulesService.teamRulesURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Change") { showTeamRulesConfig = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            } else {
                Button(action: { showTeamRulesConfig = true }) {
                    Label("Configure Team Rules URL", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .padding()
            }

            if teamRulesService.isEnabled, !teamRulesService.teamRules.isEmpty {
                ScrollView {
                    Text(teamRulesService.teamRules)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if teamRulesService.isEnabled {
                ContentUnavailableView {
                    Label("No Team Rules Loaded", systemImage: "person.2")
                } description: {
                    Text("Configure a URL to load team rules from.")
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateProjectRuleEnabled(id: UUID, isEnabled: Bool) {
        if let idx = rulesService.projectRules.firstIndex(where: { $0.id == id }) {
            rulesService.projectRules[idx].isEnabled = isEnabled
        }
    }

    private func saveEditedRule(_ rule: AIRule) {
        if rule.source == .user {
            rulesService.updateUserRule(rule)
        } else {
            if let idx = rulesService.projectRules.firstIndex(where: { $0.id == rule.id }) {
                rulesService.projectRules[idx] = rule
            }
        }
    }
}

// MARK: - RuleSource CaseIterable (for ordered display)

extension RuleSource: CaseIterable {
    static var allCases: [RuleSource] {
        [.workspace, .cursorDir, .project, .user, .builtin]
    }
}

// MARK: - Rule Row

struct RuleRowView: View {
    let rule: AIRule
    let onToggle: (AIRule) -> Void
    let onEdit: (AIRule) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newVal in
                    var updated = rule
                    updated.isEnabled = newVal
                    onToggle(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .fontWeight(.medium)
                        .foregroundColor(rule.isEnabled ? .primary : .secondary)
                    applyModeBadge
                }
                if !rule.description.isEmpty {
                    Text(rule.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let pattern = rule.pattern {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(pattern)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if let fileName = rule.fileName {
                    Text(fileName)
                        .font(.caption2)
                        .foregroundColor(Color.accentColor.opacity(0.8))
                }
            }

            Spacer()

            if rule.source == .user || rule.source == .project {
                Button(action: { onEdit(rule) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.55)
    }

    @ViewBuilder
    private var applyModeBadge: some View {
        switch rule.applyMode {
        case .always:
            EmptyView()
        case .fileScoped:
            Text("file-scoped")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(4)
        case .manual:
            Text("manual")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(4)
        }
    }
}

// MARK: - Rule Editor Sheet

struct RuleEditorSheet: View {
    let rule: AIRule?
    let onSave: (AIRule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var pattern: String = ""
    @State private var content: String = ""
    @State private var applyMode: RuleApplyMode = .always

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Rule name", text: $name)
                }
                Section("Description (optional)") {
                    TextField("Short description", text: $description)
                }
                Section("Apply Mode") {
                    Picker("Apply Mode", selection: $applyMode) {
                        ForEach(RuleApplyMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if applyMode == .fileScoped {
                        TextField("Glob pattern (e.g. *.swift, src/**/*.ts)", text: $pattern)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Section("Rule Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = AIRule(
                            id: rule?.id ?? UUID(),
                            name: name.isEmpty ? "Untitled Rule" : name,
                            description: description,
                            pattern: applyMode == .fileScoped ? pattern : nil,
                            content: content,
                            isEnabled: rule?.isEnabled ?? true,
                            priority: rule?.priority ?? 0,
                            source: rule?.source ?? .user,
                            applyMode: applyMode,
                            fileName: rule?.fileName
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(content.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            if let r = rule {
                name = r.name
                description = r.description
                pattern = r.pattern ?? ""
                content = r.content
                applyMode = r.applyMode
            }
        }
    }
}

// MARK: - Team Rules Config Sheet

struct TeamRulesConfigView: View {
    @ObservedObject private var service = TeamRulesService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var isEnabled: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Team Rules", isOn: $isEnabled)
                }
                Section("Team Rules URL") {
                    TextField("https://example.com/rules.md or file:///path/rules.md", text: $urlText)
                        .font(.system(.body, design: .monospaced))
                }
                Section {
                    Text("Team rules are fetched from the URL above and injected into every AI prompt for this machine. Use a shared HTTPS URL or a local file URL accessible by all team members.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Team Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let url = URL(string: urlText), isEnabled {
                            service.configureTeamRules(url: url, enabled: true)
                        } else if !isEnabled {
                            service.disable()
                        }
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 280)
        .onAppear {
            urlText = service.teamRulesURL?.absoluteString ?? ""
            isEnabled = service.isEnabled
        }
    }
}
