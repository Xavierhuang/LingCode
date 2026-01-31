//
//  AgentSafetyGuard.swift
//  LingCode
//
//  Safety checks for agent decisions (extracted from AgentService).
//

import Foundation

enum SafetyCheckResult {
    case safe
    case needsApproval(reason: String)
    case blocked(reason: String)
}

class AgentSafetyGuard {
    static let shared = AgentSafetyGuard()

    private let dangerousCommands = [
        "rm", "del", "mkfs", "dd", "git push", "git reset", "sudo", "chmod", "format"
    ]

    private let blockedCommands = [
        "rm -rf /", "rm -rf /*", "mkfs", "dd if=/dev/zero", "format c:"
    ]

    func check(_ decision: AgentDecision) -> SafetyCheckResult {
        if decision.action == "terminal", let cmd = decision.command?.lowercased() {
            for blocked in blockedCommands {
                if cmd.contains(blocked.lowercased()) {
                    return .blocked(reason: "Catastrophic command detected: \(blocked)")
                }
            }
            for risk in dangerousCommands {
                if cmd.contains(risk.lowercased()) {
                    return .needsApproval(reason: "Risky command detected: \(risk)")
                }
            }
            if cmd.contains("git") {
                if cmd.contains("reset --hard") || cmd.contains("push --force") || cmd.contains("clean -fd") {
                    return .needsApproval(reason: "Destructive git operation")
                }
            }
            return .needsApproval(reason: "Terminal commands require your approval before running.")
        }

        if decision.action == "code", let path = decision.filePath?.lowercased() {
            let sensitivePatterns = [".env", "credentials", "secrets", "config.json", "package-lock.json", ".git/config"]
            for pattern in sensitivePatterns {
                if path.contains(pattern) {
                    return .needsApproval(reason: "Editing sensitive file: \(pattern)")
                }
            }
        }
        return .safe
    }
}
