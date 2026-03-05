# Async Subagents vs Cursor 2.5

Comparison of LingCode's subagent system with Cursor 2.5's async subagents.

## What Cursor 2.5 Describes

- **Async subagents:** Subagents run asynchronously; the **parent agent** keeps working while subagents run in the background.
- **Tree of work:** Subagents can spawn their own subagents, forming a coordinated tree (multi-file features, large refactors, complex bugs).

## What LingCode Has (After Implementation)

### Main agent delegates and continues (parent continues while subagents run)

- **Tool: `spawn_subagent`** – The main ReAct agent can call this tool with `subagent_type`, `description`, optional `file_paths`, and optional `parent_task_id`.
- Execution creates a `SubagentTask` via `SubagentService.shared.createTask(..., parentTaskId: agentTaskId or parent_task_id)` and **returns immediately** with a message like "Subagent [Coder] started in background. Task ID: ... You can continue with other work."
- The agent then continues to the next iteration (more tool calls, etc.) without waiting for the subagent to finish. So the **parent agent continues while subagents run**.

### Tree of work

- **Optional `parent_task_id`** – When the main agent (or a subagent) spawns a subagent, it can pass another subagent task's UUID as `parent_task_id` so the new task is that task's child. `getSubtasks(for: parentId)` returns the tree.
- **Subagents spawning children** – While a subagent runs, it can output a single line:  
  `DELEGATE_SUBAGENT:<type>:<description>`  
  The stream is parsed for this line; when seen, a child task is created with `parentTaskId: current subagent task.id`. The child runs in the background (same queue, up to 3 concurrent). So subagents can spawn their own subagents and form a tree.

### SubagentService

| Feature | Status |
|--------|--------|
| Subagents run asynchronously | Yes (`Task { await executeTask }`; up to 3 concurrent) |
| Main agent spawns subagents and continues | Yes (`spawn_subagent` tool; non-blocking) |
| Parent/child and tree | Yes (`parent_task_id`, `getSubtasks(for:)`, DELEGATE_SUBAGENT in subagent output) |
| Subagents spawning subagents | Yes (DELEGATE_SUBAGENT line during stream) |

### CLI

- Still creates one subagent and polls until completion; that flow is unchanged.

## Summary

| Cursor 2.5 | LingCode |
|------------|----------|
| Subagents run async | Yes |
| Parent agent continues while subagents run | Yes (main agent uses `spawn_subagent`; returns immediately) |
| Subagents can spawn subagents (tree) | Yes (DELEGATE_SUBAGENT or main agent passes `parent_task_id`) |
| Tree of coordinated work | Yes |
