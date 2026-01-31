# LingCode vs Cursor: Investigation and How to Get Better

## 1. Where LingCode Already Wins

### 1.1 Tiered Validation (Linter → Shadow Workspace)
- **LingCode:** `ValidationCoordinator` runs Linter first, then Shadow Workspace build. `ShadowWorkspaceService` pre-warms a hidden workspace and keeps it in sync via `FileWatcherService`, so validation latency drops from seconds to milliseconds.
- **Cursor:** Typically runs lint/build in the main workspace or a single validation step; no equivalent “pre-warmed shadow + file watcher sync” in the codebase you’d see.
- **Verdict:** This is a strong differentiator. Keep investing here (e.g. ensure all apply paths use tiered validation where appropriate).

### 1.2 Single-Path Write Integrity
- **LingCode:** All disk writes go through `ApplyCodeService` as the sole broker. It builds an `EditTransaction` and uses EditorCore’s `executeToDisk` (snapshot → apply via `DiskWriteAdapter` → restore on failure). No separate “fast path” or legacy apply; one pipeline.
- **Cursor:** Multiple code paths can touch the FS (Composer, agents, refactors); consistency depends on product discipline.
- **Verdict:** LingCode’s single pipeline is a strength. Avoid adding alternate write paths that bypass the transaction pipeline.

### 1.3 Local / Offline-First
- **LingCode:** `LocalModelService` and `LocalOnlyService` support Ollama, offline mode, low-battery mode, and local model selection for autocomplete and inline edit. Privacy and on-prem are explicit goals.
- **Cursor:** Cloud-first; local/self-hosted options are more limited.
- **Verdict:** Clear advantage for privacy-sensitive and offline use. Keep surfacing “local vs cloud” and “offline” in UI and defaults.

### 1.4 Deterministic Prompt and Workspace Rules
- **LingCode:** `SpecPromptAssemblyService` and `PROMPT_ARCHITECTURE.md`: three layers only (core system prompt, `WORKSPACE.md`, task block). Precedence is explicit: task instructions > workspace rules > core. No hidden agents or merged cloud rules; user can inspect and version `WORKSPACE.md`.
- **Cursor:** Rules via `.cursorrules` and cloud; less emphasis on a single, inspectable precedence order.
- **Verdict:** LingCode is stronger on predictability and auditability. Keep strict precedence and avoid injecting extra “modes” or second system prompts.

### 1.5 Native macOS and EditorCore
- **LingCode:** Native Swift/SwiftUI app; EditorCore is a pure Swift transaction engine (propose → transaction → commit/rollback) with no Electron layer.
- **Cursor:** VS Code / Electron; different performance and integration story.
- **Verdict:** Native + EditorCore is a structural advantage for performance and UX on Mac. Leverage it (e.g. tighter editor integration, responsiveness).

---

## 2. Parity and Remaining Gaps

### 2.1 Agent / Composer UX and Management (parity)
- **Cursor:** Rich agent list: Pinned section, search, context menu (Unpin, Duplicate, Mark as Unread, Delete, Rename), clear status, relative time.
- **LingCode (current):** `AgentListView` has search, “New Agent,” **Pinned** section, **Pin/Unpin**, **Duplicate**, **Rename**, **Mark as Unread**, and Delete/Mark as failed. Context menu and list layout match Cursor-style management; unread dot and custom names are supported.
- **Verdict:** Parity for agent list management.

### 2.2 Discoverability of Rules and Context (parity)
- **Cursor:** Rules and context surfaced in Composer/agent UI.
- **LingCode (current):** **Streaming header** shows the loaded rules file name (e.g. `WORKSPACE.md`, `.cursorrules`) and a **Local** / **Cloud** chip. **Agent header** (AgentModeView) shows the same rules chip and Local/Cloud chip. Users see what’s governing the run in both streaming and agent modes.
- **Verdict:** Parity for rules and context visibility.

### 2.3 Multi-File Edit and Apply UX (parity)
- **Cursor:** Composer multi-file edits, apply all, diff review.
- **LingCode (current):** `CursorStreamingView` and EditorCore support multi-file apply; shadow verification runs before apply. **Verification badge** shows “Lint passed” and “Shadow verified” on success, and “Verification failed” plus message on failure, so tiered validation is explicit.
- **Verdict:** Parity for apply/verification feedback.

### 2.4 Terminal and Long-Running Tasks (parity)
- **LingCode:** `TerminalExecutionService` has `executeInBackground` so long-running tasks don’t block validation; `ToolExecutionService` routes tool calls to FileService or Terminal.
- **Cursor:** Mature terminal integration and background execution.
- **Verdict:** Parity for visibility of running/background commands. Status bar shows "Command running" or "1 background job" when active, with tooltips that validation may be delayed.

---

## 3. Strategic Recommendations

### 3.1 Double Down on “Cursor Killers”
- **Tiered validation:** Ensure every apply path that can use it goes through ValidationCoordinator + pre-warmed shadow where applicable. Document “Linter → Shadow” in UI or docs.
- **Single write path:** Do not reintroduce fast path or legacy apply; keep one transaction pipeline and one broker (`ApplyCodeService` + EditorCore).
- **Local/offline:** Make “Local” and “Offline” visible and easy to toggle; optimize latency for Ollama/local models.

### 3.2 Parity (done)
- **Agent list:** Pin/Unpin, Pinned section, Duplicate, Rename, Mark as Unread are implemented in `AgentListView` and `AgentHistoryService`.
- **Transparency:** Rules file name and Local/Cloud chips in streaming and agent headers; “Lint passed, Shadow verified” badge after apply.

### 3.3 Avoid Cursor’s Pitfalls
- **No hidden modes:** Keep “one task block per turn” and avoid implicit plan/execute or “agent A vs B” in the prompt (per PROMPT_ARCHITECTURE).
- **No silent rule merge:** Keep workspace rules as a single, versioned file (`WORKSPACE.md`); any team/cloud rules should be opt-in and documented in the precedence list.

### 3.4 Metrics to Watch
- **Validation latency:** Time from “Apply” to “Verified” (target: leverage pre-warm so most runs are near-instant after first sync).
- **Apply failure rate:** Track how often apply or shadow verification fails; use this to tune scope validation and messaging.
- **Local vs cloud usage:** If local/offline is a differentiator, track adoption and ensure it stays smooth.

---

## 4. Summary Table (current state)

| Area                  | LingCode                                      | Cursor                 | Status        |
|-----------------------|-----------------------------------------------|------------------------|---------------|
| Validation            | Tiered Linter → Shadow; pre-warmed sync       | Single-step typical    | LingCode ahead |
| Disk writes           | Single broker + EditorCore transaction        | Multiple paths         | LingCode ahead |
| Local / privacy        | Ollama, offline, Local/Cloud chip in headers  | Cloud-first            | LingCode ahead |
| Prompt / rules         | Deterministic; WORKSPACE.md + rules chip       | .cursorrules + cloud   | LingCode ahead |
| Agent list UX          | Pinned section, Pin/Unpin, Duplicate, Rename, Mark as Unread, Delete | Same                   | Parity        |
| Rules/context visibility | Rules file + Local/Cloud in streaming and agent headers | Similar                 | Parity        |
| Apply/verification feedback | Lint passed, Shadow verified + timing + in-progress badge | Apply + diff           | Parity        |
| Running commands / jobs     | Command running / 1 background job in status bar          | Terminal integration   | Parity        |
| Native app             | Swift/SwiftUI, EditorCore                     | Electron/VS Code       | LingCode ahead |

---

## 5. Bottom line

- **Where you’re ahead of Cursor:** Tiered validation (pre-warmed shadow + file watcher), single write pipeline (EditorCore transaction), local/offline (Ollama, chips in UI), deterministic prompt and WORKSPACE.md, native macOS.
- **Where you’re at parity:** Agent list (pin, duplicate, rename, mark unread), rules and Local/Cloud visibility in headers, apply/verification feedback (“Lint passed, Shadow verified”).
- **Done:** Running commands / background jobs indicator in status bar; verification timing in badge; in-progress "Verifying..." badge. No mandatory next; optional: deeper diff/apply polish or more validation metrics.

This doc is a living comparison; update it as either product changes.
