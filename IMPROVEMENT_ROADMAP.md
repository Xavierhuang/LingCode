# LingCode Improvement Roadmap: Surpassing Cursor

This document outlines high-impact improvements to make LingCode surpass the "Cursor-style" experience.

## 🎯 Strategic Priorities

### 1. Deepen AST Integration (High Impact, Medium Effort)
**Current State**: GraphRAGService uses hybrid approach (AST + string matching) for non-Swift languages
**Goal**: 100% TreeSitter SCM queries for all supported languages

**Implementation Plan**:
- [ ] Create TreeSitterQuery SCM files for each language:
  - Python: `call` nodes with `attribute` expressions
  - JavaScript/TypeScript: `new_expression` and `call_expression` nodes
  - Go: `call_expression` and `composite_literal` nodes
- [ ] Refactor `extractRelationshipsFromTreeSitterSymbols` in `GraphRAGService.swift` to use SCM queries
- [ ] Eliminate string matching fallback (lines 273-300 in GraphRAGService.swift)
- [ ] Add unit tests for each language's AST extraction

**Files to Modify**:
- `LingCode/Services/GraphRAGService.swift` (lines 228-303)
- `EditorCore/Sources/EditorParsers/TreeSitterManager.swift` (add SCM query support)
- Create new SCM query files in `EditorCore/Sources/EditorParsers/queries/`

**Expected Impact**: Eliminates "hallucinated" relationships, 100% AST-based precision

---

### 2. Speculative Execution Layer (High Impact, High Effort)
**Current State**: LocalOnlyService exists but not used for inline autocomplete
**Goal**: Instant "Ghost Text" feel using local models while cloud validates

**Implementation Plan**:
- [ ] Create `SpeculativeCompletionService` that:
  - Uses fast local model (Qwen-Coder/Llama-3-8B) for instant predictions
  - Runs cloud model (Claude 3.5 Sonnet) in parallel for validation
  - Merges results when cloud model confirms
- [ ] Integrate with `GhostTextEditor.swift` for inline autocomplete
- [ ] Add model selection logic: use local for simple completions, cloud for complex
- [ ] Implement cancellation when user types ahead

**Files to Create/Modify**:
- `LingCode/Services/SpeculativeCompletionService.swift` (new)
- `LingCode/Components/GhostTextEditor.swift` (integrate speculative service)
- `LingCode/Services/LocalOnlyService.swift` (add fast model support)

**Expected Impact**: Sub-100ms inline autocomplete, "instant" feel like Cursor

---

### 3. Contextual Self-Healing (Medium Impact, Low Effort)
**Current State**: `validateCodeAfterWrite` sends errors back to agent
**Goal**: Automatically attach GraphRAG results for failing symbols

**Implementation Plan**:
- [ ] Modify `validateCodeAfterWrite` in `AgentService.swift` to:
  - Extract failing symbol names from error messages
  - Query `GraphRAGService` for related files/symbols
  - Attach GraphRAG results to error prompt automatically
- [ ] Update self-healing loop to include GraphRAG context
- [ ] Cache GraphRAG results to avoid redundant queries

**Files to Modify**:
- `LingCode/Services/AgentService.swift` (lines 1015-1046)
- `LingCode/Services/GraphRAGService.swift` (add quick lookup method)

**Expected Impact**: Agent fixes errors faster, fewer iterations needed

---

### 4. Shadow Workspace (Medium Impact, Medium Effort)
**Current State**: Validation runs in project directory
**Goal**: Run validation in temporary directory before showing "Proposed" state

**Implementation Plan**:
- [ ] Create `ShadowWorkspaceService` that:
  - Creates temporary directory for validation
  - Copies modified files to shadow workspace
  - Runs tests/builds in shadow workspace
  - Only applies to project if validation passes
- [ ] Integrate with `validateCodeAfterWrite`
- [ ] Add cleanup logic for shadow workspaces

**Files to Create/Modify**:
- `LingCode/Services/ShadowWorkspaceService.swift` (new)
- `LingCode/Services/AgentService.swift` (integrate shadow workspace)

**Expected Impact**: Safer validation, can run destructive tests without risk

---

### 5. Model Context Protocol (MCP) (High Impact, High Effort)
**Current State**: Custom `AITool` definitions
**Goal**: MCP-compliant tools for extensibility

**Implementation Plan**:
- [ ] Research MCP specification and Swift implementation
- [ ] Create `MCPToolAdapter` to convert MCP tools to `AITool`
- [ ] Refactor `AITool` to support MCP schema format
- [ ] Add MCP server discovery and connection
- [ ] Create example MCP tool integrations (Google Search, Slack, etc.)

**Files to Create/Modify**:
- `LingCode/Services/MCPToolAdapter.swift` (new)
- `LingCode/Services/AITool.swift` (add MCP support)
- `LingCode/Services/MCPServerManager.swift` (new)

**Expected Impact**: Instant access to hundreds of community tools, massive extensibility

---

## 📊 Priority Matrix

| Improvement | Impact | Effort | Priority |
|------------|--------|--------|----------|
| Contextual Self-Healing | Medium | Low | **1st** ⭐ |
| Deepen AST Integration | High | Medium | **2nd** ⭐⭐ |
| Shadow Workspace | Medium | Medium | **3rd** |
| Speculative Execution | High | High | **4th** |
| MCP Protocol | High | High | **5th** |

---

## 🚀 Quick Wins (Start Here)

1. **Contextual Self-Healing** (Low effort, immediate value)
   - Modify `validateCodeAfterWrite` to attach GraphRAG results
   - ~50 lines of code, significant improvement to agent effectiveness

2. **AST Integration** (Medium effort, high precision)
   - Start with Python (most common), then expand to JS/TS
   - Eliminates string matching, 100% AST-based

---

## 📝 Implementation Notes

### TreeSitterQuery SCM Format
Example for Python instantiation:
```scm
(call
  function: (identifier) @class
  (#match? @class "^[A-Z]"))
```

### Speculative Execution Architecture
```
User types → Local model (50ms) → Show prediction
           → Cloud model (500ms) → Validate/refine
```

### MCP Tool Schema
```json
{
  "name": "tool_name",
  "description": "...",
  "inputSchema": {
    "type": "object",
    "properties": {...}
  }
}
```

---

## ✅ Completion Checklist

- [ ] Contextual Self-Healing implemented
- [ ] AST Integration for Python complete
- [ ] AST Integration for JavaScript/TypeScript complete
- [ ] AST Integration for Go complete
- [ ] Shadow Workspace implemented
- [ ] Speculative Execution layer implemented
- [ ] MCP Protocol support added
- [ ] All improvements tested and documented
