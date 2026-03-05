//
//  CommandAllowlistService.swift
//  LingCode
//
//  Persists the agent command allowlist to UserDefaults.
//  Commands (or prefix patterns) on the allowlist skip the approval dialog
//  and execute immediately — same as Cursor's "Command Allowlist" setting.
//
//  Matching rules (same as Cursor):
//  - Exact match:   "npm install"  matches only "npm install"
//  - Prefix match:  "npm"          matches any command starting with "npm "
//  - Wildcard:      "git *"        matches any command starting with "git "
//

import Foundation
import Combine

final class CommandAllowlistService: ObservableObject {
    static let shared = CommandAllowlistService()

    private let key = "agent_command_allowlist"

    @Published private(set) var allowlist: [AllowlistEntry] = []

    struct AllowlistEntry: Identifiable, Codable, Equatable {
        let id: UUID
        let pattern: String
        let addedAt: Date
        let note: String

        init(id: UUID = UUID(), pattern: String, addedAt: Date = Date(), note: String = "") {
            self.id = id
            self.pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            self.addedAt = addedAt
            self.note = note
        }
    }

    private init() {
        load()
    }

    // MARK: - Check

    /// Returns true if `command` matches any allowlist entry — skip the approval dialog.
    func isAllowed(_ command: String) -> Bool {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allowlist.contains { entry in
            matches(cmd, pattern: entry.pattern.lowercased())
        }
    }

    private func matches(_ command: String, pattern: String) -> Bool {
        if pattern.hasSuffix(" *") || pattern.hasSuffix("*") {
            // Wildcard prefix
            let prefix = pattern.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            return command.hasPrefix(prefix)
        }
        // Exact or prefix match (e.g. "npm" matches "npm install")
        return command == pattern || command.hasPrefix(pattern + " ") || command.hasPrefix(pattern + "\t")
    }

    // MARK: - Mutations

    func add(pattern: String, note: String = "") {
        let entry = AllowlistEntry(pattern: pattern, note: note)
        guard !allowlist.contains(where: { $0.pattern.lowercased() == pattern.lowercased() }) else { return }
        allowlist.append(entry)
        save()
    }

    func remove(id: UUID) {
        allowlist.removeAll { $0.id == id }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted().reversed() {
            allowlist.remove(at: index)
        }
        save()
    }

    func clear() {
        allowlist.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(allowlist) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([AllowlistEntry].self, from: data) else { return }
        allowlist = entries
    }
}
