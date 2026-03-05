//
//  MagicPushService.swift
//  LingCode
//
//  Bare-minimum: write a bash script → run it → stream output.
//  No AI, no multi-step state, just git.
//

import Foundation
import Combine

// MARK: - State

enum MagicPushState: Equatable {
    case idle
    case running
    case needsRemote
    case success(branch: String, commitHash: String)
    case failed(message: String)

    var isInProgress: Bool { self == .running }

    var displayText: String {
        switch self {
        case .idle:                   return "Ready"
        case .running:                return "Pushing..."
        case .needsRemote:            return "No remote configured"
        case .success(let b, _):      return "Pushed to \(b)"
        case .failed:                 return "Push failed"
        }
    }
}

// MARK: - Service

final class MagicPushService: ObservableObject {
    static let shared = MagicPushService()
    private init() {}

    @Published var state: MagicPushState = .idle
    @Published var gitLog: String = ""
    @Published var generatedMessage: String = ""   // kept for UI compat

    // MARK: - Push

    @MainActor
    func push(
        in projectURL: URL,
        customMessage: String? = nil,
        remote: String = "origin",
        branch: String,
        onStep: @escaping (String) -> Void
    ) async {
        state = .running
        gitLog = ""
        generatedMessage = ""
        onStep("Running push script...")

        let commitMsg = customMessage.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? "Update files"

        let script = buildScript(projectURL: projectURL, message: commitMsg, remote: remote, branch: branch)
        let result = await runScript(script, in: projectURL)

        if result.exitCode == 0 {
            let hash = gitLog.components(separatedBy: .newlines)
                .last { $0.hasPrefix("[push] HEAD") }
                .flatMap { $0.components(separatedBy: " ").last } ?? ""
            state = .success(branch: "\(remote)/\(branch)", commitHash: hash)
        } else {
            let out = result.output.lowercased()
            let isNoRemote = out.contains("no configured push destination")
                || out.contains("does not appear to be a git repository")
            if isNoRemote {
                state = .needsRemote
            } else {
                if out.contains("could not read username") || out.contains("device not configured") {
                    appendLog("\n[hint] Auth failed — use SSH or https://<token>@github.com/...")
                }
                state = .failed(message: result.output)
            }
        }
    }

    @MainActor
    func addRemoteAndPush(
        remoteURL: String,
        remoteName: String = "origin",
        projectURL: URL,
        branch: String,
        onStep: @escaping (String) -> Void
    ) async {
        state = .running
        onStep("Adding remote and pushing...")

        let script = """
        #!/usr/bin/env bash
        set -eo pipefail
        cd '\(projectURL.path)'
        git remote add \(remoteName) '\(remoteURL)' 2>/dev/null || git remote set-url \(remoteName) '\(remoteURL)'
        echo "[push] Remote set to \(remoteURL)"
        git push -u \(remoteName) \(branch.isEmpty ? "$(git rev-parse --abbrev-ref HEAD)" : branch)
        echo "[push] ✓ Done"
        """

        let result = await runScript(script, in: projectURL)
        if result.exitCode == 0 {
            state = .success(branch: "\(remoteName)/\(branch)", commitHash: "")
        } else {
            if result.output.lowercased().contains("could not read username") {
                appendLog("\n[hint] Auth failed — use SSH or https://<token>@github.com/...")
            }
            state = .failed(message: result.output)
        }
    }

    func reset() {
        state = .idle
        gitLog = ""
        generatedMessage = ""
    }

    // MARK: - Script builder

    private func buildScript(projectURL: URL, message: String, remote: String, branch: String) -> String {
        let safeMsg = message.replacingOccurrences(of: "'", with: "'\"'\"'")
        let safePath = projectURL.path.replacingOccurrences(of: "'", with: "'\"'\"'")
        return """
        #!/usr/bin/env bash
        set -eo pipefail
        cd '\(safePath)'

        echo "[push] git add -A"
        git add -A

        if git diff --cached --quiet; then
          echo "[push] Nothing new to stage."
        else
          echo "[push] git commit -m '\(safeMsg)'"
          git commit -m '\(safeMsg)'
        fi

        BRANCH=\(branch.isEmpty ? "$(git rev-parse --abbrev-ref HEAD)" : branch)
        REMOTE=\(remote.isEmpty ? "origin" : remote)

        echo "[push] git push $REMOTE $BRANCH"
        git push "$REMOTE" "$BRANCH" || git push -u "$REMOTE" "$BRANCH"

        echo "[push] HEAD $(git rev-parse --short HEAD)"
        echo "[push] ✓ Pushed to $REMOTE/$BRANCH"
        """
    }

    // MARK: - Run (direct bash, no login shell, no readabilityHandler spin)

    private func runScript(_ script: String, in directory: URL) async -> (exitCode: Int32, output: String) {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lc_push_\(UUID().uuidString).sh")
        do {
            try script.write(to: tmpURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpURL.path)
        } catch {
            return (-1, "Failed to write script: \(error.localizedDescription)")
        }

        return await withCheckedContinuation { continuation in
            // Run entirely on a background thread — no main actor involvement
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                let outPipe = Pipe()
                let errPipe = Pipe()

                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [tmpURL.path]
                proc.currentDirectoryURL = directory

                var env: [String: String] = [
                    "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                ]
                if let v = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                    env["SSH_AUTH_SOCK"] = v
                }
                proc.environment = env
                proc.standardOutput = outPipe
                proc.standardError  = errPipe

                do { try proc.run() } catch {
                    try? FileManager.default.removeItem(at: tmpURL)
                    continuation.resume(returning: (-1, "Could not start: \(error.localizedDescription)"))
                    return
                }

                // Stream stdout line-by-line while process runs
                let outHandle = outPipe.fileHandleForReading
                let errHandle = errPipe.fileHandleForReading

                // Use a separate thread to read stderr
                let errQueue = DispatchQueue(label: "lc.push.err")
                errQueue.async {
                    while true {
                        let data = errHandle.availableData
                        if data.isEmpty { break }
                        if let s = String(data: data, encoding: .utf8) {
                            Task { @MainActor in self.appendLog(s) }
                        }
                    }
                }

                var fullOutput = ""
                while true {
                    let data = outHandle.availableData
                    if data.isEmpty { break }
                    if let s = String(data: data, encoding: .utf8) {
                        fullOutput += s
                        Task { @MainActor in self.appendLog(s) }
                    }
                }

                proc.waitUntilExit()
                let code = proc.terminationStatus

                // Drain any remaining stderr
                let remaining = errHandle.readDataToEndOfFile()
                if let s = String(data: remaining, encoding: .utf8), !s.isEmpty {
                    fullOutput += s
                    Task { @MainActor in self.appendLog(s) }
                }

                try? FileManager.default.removeItem(at: tmpURL)
                continuation.resume(returning: (code, fullOutput))
            }
        }
    }

    private func appendLog(_ text: String) {
        let t = text.trimmingCharacters(in: .newlines)
        guard !t.isEmpty else { return }
        Task { @MainActor in self.gitLog += t + "\n" }
    }
}
