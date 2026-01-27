# AI Coding Assistant: Instruction & System-Prompt Architecture

A minimal, deterministic spec for assembling prompts. No agents, no theater. Three layers only; user rules are inspectable and win when they conflict.

---

## 1. Core System Prompt (≤150 words)

```
You are a coding assistant. You operate inside an editor. You can read files, edit files, run commands, and search the codebase.

Instruction precedence is: task instructions > workspace rules > this system prompt.

Rules:
- Answer only what was asked. Do not suggest extra tasks unless the user asks.
- Prefer editing existing code over explaining. When you change code, make the minimal edit that satisfies the request.
- If you need to run a command (build, test, lint), say what you will run and then run it. Do not assume it already happened.
- When uncertain about project structure or conventions, follow workspace rules (WORKSPACE.md) exactly. If workspace rules conflict with your default behavior, workspace rules win.
- Output code and user-facing text only. Do not output reasoning blocks, chain-of-thought, or internal scratchpad unless the user explicitly asks for it.
- If the task cannot be completed without violating these rules, ask one clarifying question or state that you cannot proceed.
```

*Word count: ~135.*

---

## 2. Workspace Rules File: WORKSPACE.md

**Purpose:** User-owned, version-controlled rules. One file per workspace. Plain Markdown. No hidden or generated sections.

**Location:** Repository root. Path is fixed: `WORKSPACE.md`.

**Format:**

```markdown
# Workspace: <ProjectName>

## Conventions
- Bullet or short paragraphs only.
- No code blocks that define "agent personas" or sub-agents.
- Sections are optional. Use only what you need.

## Language & Stack
- Primary language: Swift. Use Swift 5 concurrency; avoid Combine where async/await is enough.
- Build: Xcode, no custom Makefiles.

## Layout
- /LingCode = app target. /EditorCore = shared library. Do not move types across these without updating imports and project file.

## Editing Rules
- Prefer DesignSystem.Typography and DesignSystem.Colors over raw fonts/colors.
- New views go in Views/; new services in Services/. Match existing file命名.

## Out of Scope
- Do not add npm, web tooling, or new runtimes unless explicitly requested.
```

**Inspectability:** The user (and the app) always loads exactly this file path. No merging with cloud rules unless the user opts in to a separate “team rules” feature.

**Empty handling:** The loader trims whitespace and newlines. If the file exists but is empty or only whitespace after trim, it is not appended—so an empty file does not win precedence without meaningfully constraining behavior.

**Example of a bad rule:** “Let the code-review agent handle style.”  
**Good rule:** “Use 4 spaces. Line length ≤120. Run SwiftLint before commit.”

---

## 3. Runtime Task-Instruction Template

Each user turn is wrapped in a **task instruction**. One template for all requests; no “modes” or “personas” in the text.

```
## Task
<exact user message, untouched>

## Context (if any)
<optional: file path + line range or symbol the user had selected>
<optional: “User attached: filename” for pastes/uploads>

## Instructions
- Complete the task above.
- If WORKSPACE.md applies, follow it. Otherwise use default behavior.
- Reply with code edits, commands, or direct answers only. Do not explain unless asked.
```

**Concrete example:**

```
## Task
Use DesignSystem colors for the streaming panel background instead of NSColor.controlBackgroundColor.

## Context
File: LingCode/Views/CursorStreamingView.swift, around line 258.

## Instructions
- Complete the task above.
- If WORKSPACE.md applies, follow it. Otherwise use default behavior.
- Reply with code edits, commands, or direct answers only. Do not explain unless asked.
```

No “plan mode,” “run mode,” or “agent A vs B.” One task block per turn.

---

## 4. Instruction Precedence Order

Precedence is strict and document-based. Higher in the list wins.

1. **Task instruction “Instructions” block**  
   - E.g. “reply only with a patch” or “do not run tests.”  
   - Scoped to this turn only.

2. **WORKSPACE.md**  
   - Project conventions, layout, stack, editing rules, out-of-scope.  
   - Applies to every turn in this workspace.

3. **Core system prompt**  
   - Default behavior: minimal edits, run commands when needed, no unsolicited reasoning, workspace rules override defaults.

Nothing else is in the prompt. No “platform guidelines,” “safety layers,” or “agent instructions” injected between 1–3. If you add a fourth source (e.g. team rules), it must be explicitly documented and placed in this list (e.g. “1.5 Team rules” only when enabled).

---

## 5. Pseudocode: Final Prompt Assembly

```text
FUNCTION build_prompt(user_message, context_or_null, workspace_path):
    system_prompt = load_core_system_prompt()   // fixed string, same for all workspaces

    workspace_rules = ""
    IF file_exists(workspace_path + "/WORKSPACE.md"):
        workspace_rules = read_file(workspace_path + "/WORKSPACE.md")
        workspace_rules = "## Workspace Rules (you must follow these)\n\n" + workspace_rules

    task_block = "## Task\n" + user_message + "\n\n"
    task_block += "## Context (if any)\n"
    IF context_or_null != null:
        task_block += context_or_null.to_string() + "\n"
    task_block += "\n## Instructions\n"
    task_block += "- Complete the task above.\n"
    task_block += "- If workspace rules were provided, follow them. Otherwise use default behavior.\n"
    task_block += "- Reply with code edits, commands, or short answers. No meta-commentary unless asked.\n"

    // Order in the actual API call (deterministic)
    messages = [
        { role: "system", content: system_prompt + "\n\n" + workspace_rules },
        { role: "user", content: task_block }
    ]

    RETURN messages
```

**Single request per turn.** No multi-step “orchestration” in the prompt. Tool-use (read_file, edit, run_cmd, search) is described in the system prompt and invoked by the model in one or more tool rounds, but the **instruction stack** is built once per turn via this function.

---

## 6. Anti-Patterns (What to Avoid)

Based on typical “smart” assistants that sacrifice predictability:

| Anti-pattern | Why it hurts | Do this instead |
|--------------|--------------|------------------|
| **Implicit “modes”** (plan vs execute, “I’ll now search…”) | User doesn’t know which mode is active or how to change it. | One task block per turn. If you need a “plan first” flow, make it a user choice (e.g. “Plan only” checkbox) that adds one line to the Instructions block. |
| **Injecting second system prompts** (e.g. “Be concise”, “You are in debug mode”) | Overwrites or conflicts with core + workspace. | All behavioral overrides go into the task “Instructions” or WORKSPACE.md. |
| **Hidden or merged rules** (AGENTS.md + cloud + “best practices” blended) | User can’t see or edit what the model was told. | Only WORKSPACE.md (and optional explicit “team rules”). No silent merging. |
| **Named agents in the UI** (“Code agent”, “Test agent”, “Review agent”) | Suggests separate minds and makes precedence unclear. | One assistant. No agent names in prompts or UI. |
| **Auto-expanding context** (“I’ll pull in related files”) without disclosure | User doesn’t know what’s in the prompt; token use and behavior become unpredictable. | Explicit context: only attach files/symbols the user selected or that the model requested via a tool, and show that in “Context” or in the tool call log. |
| **“Orchestration” in natural language** (“First I will… then I will…”) | Non-deterministic; model can change the sequence. | Deterministic assembly (system + workspace + task). Sequence is “read task → use tools → respond.” |
| **Chain-of-thought by default** | Wastes tokens and makes “final answer” harder to parse. | No reasoning in the output unless the user asks (e.g. “explain your approach”). |

---

## Summary

- **Core system prompt:** One short, fixed text; same for every workspace.
- **WORKSPACE.md:** Single user-owned rules file, Markdown, at repo root; inspectable and versioned.
- **Task template:** Task + Context + Instructions, one block per turn; no modes or agents.
- **Precedence:** Task instructions > WORKSPACE.md > core system prompt.
- **Assembly:** Pure function: (user_message, context, workspace_path) → list of messages; no hidden layers.

This gives you a minimal, deterministic instruction and system-prompt architecture you can implement in production against Claude or GPT.
