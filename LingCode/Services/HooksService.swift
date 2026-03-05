//
//  HooksService.swift
//  LingCode
//
//  Cursor-compatible agent hooks system.
//  Loads hooks.json from (in priority order):
//    1. <workspace>/.cursor/hooks.json  (project-level)
//    2. ~/.cursor/hooks.json            (user-level)
//
//  Supported hook events:
//    sessionStart       — new agent session; can inject context or block
//    sessionEnd         — session finished (fire-and-forget)
//    beforeShellExecution — gate terminal commands; can allow/deny/ask
//    afterShellExecution — post-command audit (fire-and-forget)
//    afterFileEdit      — post-edit formatter (fire-and-forget)
//    beforeReadFile     — gate file reads; can allow/deny
//    beforeSubmitPrompt — validate prompt before AI call; can block
//    stop               — session loop ended; can inject follow-up message
//    preToolUse         — fires before any tool; can allow/deny/modify
//    postToolUse        — fires after any successful tool
//    subagentStart      — before spawning a subagent; can allow/deny
//    subagentStop       — after subagent completes
//
//  Each hook is a shell command executed with the event JSON on stdin.
//  Exit code 0 → use JSON output. Exit code 2 → deny/block. Other → fail-open.
//  Prompt-based hooks (type: "prompt") use the AI to evaluate a condition.
//

import Foundation
import Combine

// MARK: - Hook config types

struct HookDefinition: Codable {
    let command: String?
    let type: HookType?
    let prompt: String?
    let timeout: Double?
    let matcher: String?
    let loopLimit: Int?

    enum HookType: String, Codable {
        case command
        case prompt
    }

    enum CodingKeys: String, CodingKey {
        case command, type, prompt, timeout, matcher
        case loopLimit = "loop_limit"
    }
}

struct HooksConfig: Codable {
    let version: Int?
    let hooks: [String: [HookDefinition]]?
}

// MARK: - Claude Code settings format

/// Claude Code uses a different JSON layout:
/// { "hooks": { "PreToolUse": [ { "matcher": "Shell", "hooks": [ { "type": "command", "command": "..." } ] } ] } }
private struct ClaudeSettings: Codable {
    let hooks: [String: [ClaudeHookGroup]]?
}

private struct ClaudeHookGroup: Codable {
    let matcher: String?
    let hooks: [ClaudeHookStep]
}

private struct ClaudeHookStep: Codable {
    let type: String?
    let command: String?
    let prompt: String?
    let timeout: Double?
}

// MARK: - Hook execution results

enum HookDecision {
    case allow
    case deny(reason: String)
    case ask(userMessage: String, agentMessage: String)
    case modify(updatedInput: [String: Any])
    case followUp(message: String)
    case additionalContext(String)
    case noOutput
}

// MARK: - Service

@MainActor
final class HooksService: ObservableObject {
    static let shared = HooksService()

    @Published var isEnabled: Bool = true
    @Published var lastHookOutput: String = ""
    /// When true, also loads hooks from .claude/settings.json (Claude Code compatibility)
    @Published var thirdPartyHooksEnabled: Bool = true

    private var projectHooks: HooksConfig?
    private var userHooks: HooksConfig?
    // Claude Code config files (three locations, loaded in order)
    private var claudeProjectLocalHooks: ClaudeSettings?   // .claude/settings.local.json
    private var claudeProjectHooks: ClaudeSettings?        // .claude/settings.json
    private var claudeUserHooks: ClaudeSettings?           // ~/.claude/settings.json
    private var projectURL: URL?
    private var stopLoopCount: Int = 0

    // Env vars injected by sessionStart hooks, passed to all subsequent hooks
    private var sessionEnv: [String: String] = [:]

    private init() {
        loadUserHooks()
    }

    // MARK: - Loading

    func setProjectURL(_ url: URL?) {
        projectURL = url
        stopLoopCount = 0
        sessionEnv = [:]
        if let url = url {
            loadProjectHooks(from: url)
            loadClaudeProjectHooks(from: url)
        }
    }

    private func loadProjectHooks(from projectURL: URL) {
        let path = projectURL.appendingPathComponent(".cursor/hooks.json")
        projectHooks = loadConfig(from: path)
    }

    private func loadUserHooks() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".cursor/hooks.json")
        userHooks = loadConfig(from: path)
        // Claude user hooks
        let claudePath = home.appendingPathComponent(".claude/settings.json")
        claudeUserHooks = loadClaudeConfig(from: claudePath)
    }

    private func loadClaudeProjectHooks(from projectURL: URL) {
        let localPath   = projectURL.appendingPathComponent(".claude/settings.local.json")
        let projectPath = projectURL.appendingPathComponent(".claude/settings.json")
        claudeProjectLocalHooks = loadClaudeConfig(from: localPath)
        claudeProjectHooks      = loadClaudeConfig(from: projectPath)
    }

    private func loadConfig(from url: URL) -> HooksConfig? {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(HooksConfig.self, from: data) else {
            return nil
        }
        return config
    }

    private func loadClaudeConfig(from url: URL) -> ClaudeSettings? {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ClaudeSettings.self, from: data) else {
            return nil
        }
        return config
    }

    // MARK: - Hook definitions for an event

    /// Returns all hook definitions for a given event name.
    /// Priority order (highest → lowest):
    ///   1. project .cursor/hooks.json
    ///   2. user    ~/.cursor/hooks.json
    ///   3. claude  .claude/settings.local.json
    ///   4. claude  .claude/settings.json
    ///   5. claude  ~/.claude/settings.json
    private func definitions(for event: String) -> [(definition: HookDefinition, workingDir: URL)] {
        var results: [(HookDefinition, URL)] = []

        let projectDir  = projectURL ?? FileManager.default.homeDirectoryForCurrentUser
        let userCursor  = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor")
        let userClaude  = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")

        // 1. Cursor project hooks
        if let hooks = projectHooks?.hooks?[event] {
            results.append(contentsOf: hooks.map { ($0, projectDir) })
        }
        // 2. Cursor user hooks
        if let hooks = userHooks?.hooks?[event] {
            results.append(contentsOf: hooks.map { ($0, userCursor) })
        }

        // 3–5. Claude hooks (only when third-party hooks are enabled)
        if thirdPartyHooksEnabled {
            let claudeEvent = cursorToClaude(event)
            [
                (claudeProjectLocalHooks, projectDir),
                (claudeProjectHooks,      projectDir),
                (claudeUserHooks,         userClaude),
            ].forEach { settings, dir in
                guard let groups = settings?.hooks?[claudeEvent] else { return }
                for group in groups {
                    for step in group.hooks {
                        let def = HookDefinition(
                            command: step.command,
                            type: step.type.flatMap { HookDefinition.HookType(rawValue: $0) } ?? .command,
                            prompt: step.prompt,
                            timeout: step.timeout,
                            matcher: group.matcher,
                            loopLimit: nil
                        )
                        results.append((def, dir))
                    }
                }
            }
        }

        return results
    }

    // MARK: - Name mappings

    /// Map Cursor event name → Claude Code event name.
    private func cursorToClaude(_ cursorEvent: String) -> String {
        let map: [String: String] = [
            "preToolUse":        "PreToolUse",
            "postToolUse":       "PostToolUse",
            "beforeSubmitPrompt":"UserPromptSubmit",
            "stop":              "Stop",
            "subagentStop":      "SubagentStop",
            "sessionStart":      "SessionStart",
            "sessionEnd":        "SessionEnd",
            "preCompact":        "PreCompact",
        ]
        return map[cursorEvent] ?? cursorEvent
    }

    /// Map Claude tool name → Cursor tool name (for matcher normalisation).
    static func normaliseTool(_ name: String) -> String {
        let map: [String: String] = [
            "bash":    "Shell",
            "Bash":    "Shell",
            "read":    "Read",
            "Read":    "Read",
            "write":   "Write",
            "Write":   "Write",
            "edit":    "Write",
            "Edit":    "Write",
            "grep":    "Grep",
            "Grep":    "Grep",
            "task":    "Task",
            "Task":    "Task",
        ]
        return map[name] ?? name
    }

    // MARK: - Matcher filtering

    private func matches(_ text: String, pattern: String?) -> Bool {
        guard let pattern = pattern, !pattern.isEmpty else { return true }
        // Normalise tool name before matching (e.g. Claude "Bash" → Cursor "Shell")
        let normText = HooksService.normaliseTool(text)
        // Pattern is a regex or pipe-separated alternatives
        let parts = pattern.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.contains { part in
            let normPart = HooksService.normaliseTool(part)
            if let regex = try? NSRegularExpression(pattern: normPart, options: .caseInsensitive) {
                return regex.firstMatch(in: normText, range: NSRange(normText.startIndex..., in: normText)) != nil
            }
            return normText.localizedCaseInsensitiveContains(normPart)
        }
    }

    // MARK: - Core execution

    /// Run a command hook. Returns the JSON-decoded output or an error decision.
    private func runCommandHook(_ definition: HookDefinition,
                                 input: [String: Any],
                                 workingDir: URL) async -> HookDecision {
        guard let command = definition.command else { return .noOutput }

        let timeout = definition.timeout ?? 30.0
        let inputJSON = (try? JSONSerialization.data(withJSONObject: input))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let proc = Process()
                let inPipe  = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()

                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = ["-c", command]
                proc.currentDirectoryURL = workingDir
                proc.standardInput  = inPipe
                proc.standardOutput = outPipe
                proc.standardError  = errPipe

                // Merge session env with process env
                var env = ProcessInfo.processInfo.environment
                self?.sessionEnv.forEach { env[$0.key] = $0.value }
                env["CURSOR_PROJECT_DIR"] = self?.projectURL?.path ?? workingDir.path
                env["CLAUDE_PROJECT_DIR"] = env["CURSOR_PROJECT_DIR"]!
                proc.environment = env

                let timer = DispatchWorkItem { proc.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                do {
                    try proc.run()
                    if let data = inputJSON.data(using: .utf8) {
                        inPipe.fileHandleForWriting.write(data)
                    }
                    inPipe.fileHandleForWriting.closeFile()
                    proc.waitUntilExit()
                    timer.cancel()
                } catch {
                    timer.cancel()
                    continuation.resume(returning: .noOutput)
                    return
                }

                let code = proc.terminationStatus
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()

                // Exit code 2 = deny
                if code == 2 {
                    continuation.resume(returning: .deny(reason: "Hook denied action"))
                    return
                }
                // Other non-zero = fail-open (except beforeMCPExecution / beforeReadFile which are fail-closed)
                if code != 0 {
                    continuation.resume(returning: .noOutput)
                    return
                }

                guard let outputStr = String(data: outData, encoding: .utf8),
                      !outputStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let jsonData = outputStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continuation.resume(returning: .noOutput)
                    return
                }

                continuation.resume(returning: HooksService.parseOutput(json))
            }
        }
    }

    /// Run a prompt-based hook — ask the AI to evaluate a condition.
    private func runPromptHook(_ definition: HookDefinition,
                                input: [String: Any]) async -> HookDecision {
        guard let promptTemplate = definition.prompt else { return .noOutput }
        let inputJSON = (try? JSONSerialization.data(withJSONObject: input))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let prompt = promptTemplate.replacingOccurrences(of: "$ARGUMENTS", with: inputJSON)
            + (promptTemplate.contains("$ARGUMENTS") ? "" : "\n\nInput: \(inputJSON)")

        do {
            let response = try await AIService.shared.sendMessage(
                prompt + "\n\nRespond with JSON only: {\"ok\": true|false, \"reason\": \"optional\"}",
                context: nil
            )
            if let data = response.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let ok = json["ok"] as? Bool ?? true
                let reason = json["reason"] as? String ?? ""
                return ok ? .allow : .deny(reason: reason)
            }
        } catch { }
        return .noOutput
    }

    private static func parseOutput(_ json: [String: Any]) -> HookDecision {
        // preToolUse / beforeShellExecution / beforeReadFile style
        if let decision = json["decision"] as? String ?? json["permission"] as? String {
            switch decision {
            case "deny":
                let reason = json["reason"] as? String ?? json["user_message"] as? String ?? "Hook denied"
                return .deny(reason: reason)
            case "ask":
                let user  = json["user_message"]  as? String ?? "Approval required"
                let agent = json["agent_message"] as? String ?? user
                return .ask(userMessage: user, agentMessage: agent)
            case "allow":
                if let updated = json["updated_input"] as? [String: Any] { return .modify(updatedInput: updated) }
                return .allow
            default:
                break
            }
        }
        // beforeSubmitPrompt style
        if let cont = json["continue"] as? Bool, !cont {
            let msg = json["user_message"] as? String ?? "Blocked by hook"
            return .deny(reason: msg)
        }
        // stop style
        if let followup = json["followup_message"] as? String, !followup.isEmpty {
            return .followUp(message: followup)
        }
        // sessionStart style
        if let context = json["additional_context"] as? String, !context.isEmpty {
            return .additionalContext(context)
        }
        // env injection (handled by caller)
        return .noOutput
    }

    // MARK: - Public fire methods (fail-open except where noted)

    /// Runs all hooks for `event`. Returns the first non-noOutput decision, or .allow.
    func run(event: String,
             input: [String: Any],
             matcher: String? = nil,
             failClosed: Bool = false) async -> HookDecision {
        guard isEnabled else { return .allow }
        let defs = definitions(for: event)
        guard !defs.isEmpty else { return .allow }

        let matchText = (input["command"] as? String)
            ?? (input["tool_name"] as? String)
            ?? (input["subagent_type"] as? String)
            ?? ""

        for (def, dir) in defs {
            if let m = def.matcher ?? matcher, !matches(matchText, pattern: m) { continue }

            let base = commonInput(event: event)
            let merged = base.merging(input) { $1 }

            let decision: HookDecision
            if def.type == .prompt {
                decision = await runPromptHook(def, input: merged)
            } else {
                decision = await runCommandHook(def, input: merged, workingDir: dir)
            }

            switch decision {
            case .noOutput: continue
            default: return decision
            }
        }
        return .allow
    }

    /// Fire-and-forget version — runs all hooks without waiting for block decisions.
    func fire(event: String, input: [String: Any]) {
        guard isEnabled else { return }
        let defs = definitions(for: event)
        guard !defs.isEmpty else { return }
        let base = commonInput(event: event)
        let merged = base.merging(input) { $1 }
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            for (def, dir) in defs {
                if def.type == .prompt {
                    _ = await self.runPromptHook(def, input: merged)
                } else {
                    _ = await self.runCommandHook(def, input: merged, workingDir: dir)
                }
            }
        }
    }

    // MARK: - Convenience wrappers

    /// sessionStart — returns additional context string if any hook provides it.
    func fireSessionStart(task: String, mode: String) async -> String? {
        stopLoopCount = 0
        let input: [String: Any] = [
            "session_id": UUID().uuidString,
            "is_background_agent": false,
            "composer_mode": mode,
            "task": task
        ]
        let decision = await run(event: "sessionStart", input: input)
        // Capture env vars if hook returned them (not in HookDecision — parse separately)
        if case .additionalContext(let ctx) = decision { return ctx }
        return nil
    }

    /// sessionEnd — fire and forget.
    func fireSessionEnd(status: String, durationMs: Int) {
        let input: [String: Any] = [
            "session_id": UUID().uuidString,
            "reason": status,
            "duration_ms": durationMs,
            "is_background_agent": false,
            "final_status": status
        ]
        fire(event: "sessionEnd", input: input)
    }

    /// beforeShellExecution — returns HookDecision (.allow / .deny / .ask).
    func beforeShellExecution(command: String, cwd: URL?) async -> HookDecision {
        let input: [String: Any] = [
            "command": command,
            "cwd": cwd?.path ?? projectURL?.path ?? "",
            "timeout": 30
        ]
        return await run(event: "beforeShellExecution", input: input, matcher: command)
    }

    /// afterShellExecution — fire and forget.
    func afterShellExecution(command: String, output: String, durationMs: Int) {
        let input: [String: Any] = [
            "command": command,
            "output": output,
            "duration": durationMs
        ]
        fire(event: "afterShellExecution", input: input)
    }

    /// afterFileEdit — fire and forget (e.g. run formatter).
    func afterFileEdit(filePath: String, edits: [[String: String]]) {
        let input: [String: Any] = [
            "file_path": filePath,
            "edits": edits
        ]
        fire(event: "afterFileEdit", input: input)
    }

    /// beforeReadFile — returns HookDecision.
    func beforeReadFile(filePath: String, content: String) async -> HookDecision {
        let input: [String: Any] = [
            "file_path": filePath,
            "content": String(content.prefix(8000)),
            "attachments": []
        ]
        // Fail-closed — block if hook crashes
        return await run(event: "beforeReadFile", input: input, failClosed: true)
    }

    /// beforeSubmitPrompt — returns true if submission should proceed.
    func beforeSubmitPrompt(prompt: String) async -> Bool {
        let input: [String: Any] = ["prompt": prompt, "attachments": []]
        let decision = await run(event: "beforeSubmitPrompt", input: input)
        if case .deny = decision { return false }
        return true
    }

    /// preToolUse — returns HookDecision.
    func preToolUse(toolName: String, toolInput: [String: Any]) async -> HookDecision {
        let input: [String: Any] = [
            "tool_name": toolName,
            "tool_input": toolInput,
            "tool_use_id": UUID().uuidString
        ]
        return await run(event: "preToolUse", input: input, matcher: toolName)
    }

    /// postToolUse — fire and forget.
    func postToolUse(toolName: String, toolInput: [String: Any], output: String, durationMs: Int) {
        let input: [String: Any] = [
            "tool_name": toolName,
            "tool_input": toolInput,
            "tool_output": output,
            "tool_use_id": UUID().uuidString,
            "duration": durationMs
        ]
        fire(event: "postToolUse", input: input)
    }

    /// subagentStart — returns true if allowed.
    func subagentStart(type: String, prompt: String) async -> Bool {
        let input: [String: Any] = ["subagent_type": type, "prompt": prompt]
        let decision = await run(event: "subagentStart", input: input, matcher: type)
        if case .deny = decision { return false }
        return true
    }

    /// subagentStop — fire and forget.
    func subagentStop(type: String, status: String, result: String, durationMs: Int) {
        let input: [String: Any] = [
            "subagent_type": type,
            "status": status,
            "result": result,
            "duration": durationMs
        ]
        fire(event: "subagentStop", input: input)
    }

    /// stop — returns optional follow-up message.
    func fireStop(status: String) async -> String? {
        let loopLimit = 5
        guard stopLoopCount < loopLimit else { return nil }

        let input: [String: Any] = ["status": status, "loop_count": stopLoopCount]
        let decision = await run(event: "stop", input: input)
        if case .followUp(let msg) = decision {
            stopLoopCount += 1
            return msg
        }
        return nil
    }

    // MARK: - Helpers

    private func commonInput(event: String) -> [String: Any] {
        [
            "conversation_id": UUID().uuidString,
            "generation_id": UUID().uuidString,
            "hook_event_name": event,
            "workspace_roots": [projectURL?.path ?? ""].filter { !$0.isEmpty }
        ]
    }

    /// Returns true if any hooks are configured for the given event.
    func hasHooks(for event: String) -> Bool {
        return !(definitions(for: event).isEmpty)
    }
}
