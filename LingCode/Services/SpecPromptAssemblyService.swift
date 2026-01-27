//
//  SpecPromptAssemblyService.swift
//  LingCode
//
//  Minimal, deterministic prompt assembly per docs/PROMPT_ARCHITECTURE.md.
//  Three layers: core system prompt, WORKSPACE.md, task template. No agents, no hidden rules.
//

import Foundation

/// Assembles the final prompt from core system prompt + WORKSPACE.md + task block.
/// Precedence: task instructions > workspace rules > core.
enum SpecPromptAssemblyService {

    /// Core system prompt (≤150 words). Same for all workspaces.
    /// Instruction precedence is: task instructions > workspace rules > this system prompt.
    static let coreSystemPrompt = """
    You are a coding assistant. You operate inside an editor. You can read files, edit files, run commands, and search the codebase.

    Instruction precedence is: task instructions > workspace rules > this system prompt.

    Rules:
    - Answer only what was asked. Do not suggest extra tasks unless the user asks.
    - Prefer editing existing code over explaining. When you change code, make the minimal edit that satisfies the request.
    - If you need to run a command (build, test, lint), say what you will run and then run it. Do not assume it already happened.
    - When uncertain about project structure or conventions, follow workspace rules (WORKSPACE.md) exactly. If workspace rules conflict with your default behavior, workspace rules win.
    - Output code and user-facing text only. Do not output reasoning blocks, chain-of-thought, or internal scratchpad unless the user explicitly asks for it.
    - If the task cannot be completed without violating these rules, ask one clarifying question or state that you cannot proceed.
    """

    static let workspaceFileName = "WORKSPACE.md"
    // Backwards compatibility: also check .cursorrules (Cursor's format)
    static let cursorRulesFileName = ".cursorrules"
    // Also support .lingcode and .lingrules for legacy compatibility
    static let legacyRuleFileNames = [".lingcode", ".lingrules"]

    /// Load workspace rules from repo root. Checks WORKSPACE.md first, then .cursorrules, then legacy formats.
    /// Returns nil if no rules file found or unreadable.
    static func loadWorkspaceRules(workspaceRootURL: URL?) -> String? {
        guard let root = workspaceRootURL else { return nil }
        
        // Priority order: WORKSPACE.md > .cursorrules > .lingcode > .lingrules
        let fileNames = [workspaceFileName, cursorRulesFileName] + legacyRuleFileNames
        
        for fileName in fileNames {
            let fileURL = root.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let content = try? String(contentsOf: fileURL, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }
        
        return nil
    }

    /// Build the runtime task block (Task + Context + Instructions).
    static func buildTaskBlock(task: String, context: String?) -> String {
        var block = "## Task\n\(task)\n\n## Context (if any)\n"
        if let ctx = context, !ctx.isEmpty {
            block += ctx
            block += "\n"
        }
        block += """
        \n## Instructions
        - Complete the task above.
        - If workspace rules were provided, follow them. Otherwise use default behavior.
        - Reply with code edits, commands, or short answers. No meta-commentary unless asked.
        """
        return block
    }

    /// Assemble (systemPrompt, userMessage) per spec. Pass context into the task block; do not pass it again as the `context` param to streamMessage.
    /// - Parameters:
    ///   - userMessage: Exact user input.
    ///   - context: Editor/selection/attachments etc. Injected into ## Context (if any).
    ///   - workspaceRootURL: Project root for loading WORKSPACE.md.
    /// - Returns: (systemPrompt, userMessage). Use userMessage as the single user turn and pass context: nil to the AI service.
    static func buildPrompt(
        userMessage: String,
        context: String?,
        workspaceRootURL: URL?
    ) -> (systemPrompt: String, userMessage: String) {
        var system = coreSystemPrompt
        
        // Add team rules first (lowest precedence in system prompt, but still in system)
        if let teamRules = TeamRulesService.shared.getTeamRulesForAI() {
            system += "\n\n\(teamRules)"
        }
        
        // Add workspace rules (higher precedence than team rules)
        if let raw = loadWorkspaceRules(workspaceRootURL: workspaceRootURL) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                system += "\n\n## Workspace Rules (you must follow these)\n\n\(trimmed)"
            }
        }
        
        let user = buildTaskBlock(task: userMessage, context: context)
        return (system, user)
    }
}
