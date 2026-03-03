//
//  TerminalSessionManager.swift
//  LingCode
//
//  Manages multiple terminal sessions (tabs): id and name only.
//  Run actions send commands via commandToSend to the active terminal.
//

import Foundation
import Combine

final class TerminalSession: Identifiable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String = "zsh") {
        self.id = id
        self.name = name
    }
}

final class TerminalSessionManager: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published var activeSessionId: UUID?
    @Published var commandToSend: String?

    var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return sessions.first }
        return sessions.first { $0.id == id }
    }

    func addTerminal(workingDirectory: URL?) {
        let session = TerminalSession()
        sessions.append(session)
        activeSessionId = session.id
    }

    func removeTerminal(id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.first?.id
        }
    }

    func selectSession(id: UUID) {
        activeSessionId = id
    }

    func ensureOneTerminal(workingDirectory: URL?) {
        if sessions.isEmpty {
            addTerminal(workingDirectory: workingDirectory)
        }
    }

    func sendCommand(_ command: String) {
        commandToSend = command
    }
}
