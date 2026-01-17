# Agent Mode Implementation Guide

## Overview

LingCode now supports **Agent Mode** with tool execution capabilities, enabling the AI to:
- Search the codebase (`codebase_search`)
- Read files (`read_file`)
- Write/edit files (`write_file`)

This enables "Composer" mode for multi-file editing, similar to Cursor's Composer feature.

## Architecture

### 1. Tool Definitions (`AITool.swift`)
- `AITool` struct defines tool schemas
- Predefined tools: `codebaseSearch()`, `readFile()`, `writeFile()`
- Uses `AnyCodable` for flexible JSON schema encoding

### 2. Tool Execution Service (`ToolExecutionService.swift`)
- Executes tool calls from AI
- Handles file operations via `FileService`
- Uses `SemanticSearchService` for codebase search
- Resolves relative/absolute file paths

### 3. Tool Call Handler (`ToolCallHandler.swift`)
- Detects tool calls in AI streaming responses
- Processes tool call markers (`🔧 TOOL_CALL:id:name:input`)
- Manages tool execution and results

### 4. ModernAIService Integration
- Detects `content_block_start` events with `type: "tool_use"`
- Encodes tool calls as special markers in stream
- Enables tools when `projectMode = true`

### 5. ComposerView Integration
- Listens for `ToolFileWritten` notifications
- Automatically adds/updates files in Composer UI
- Shows diff view for each file
- Supports "Apply All" and "Discard All"

## Usage

### Enabling Agent Mode

1. **In ComposerView**: Automatically enabled when using Composer mode
   ```swift
   viewModel.projectMode = true  // Enables tools
   ```

2. **In AIViewModel**: Tools are automatically included when `projectMode = true`
   ```swift
   let tools: [AITool]? = projectMode ? [
       .codebaseSearch(),
       .readFile(),
       .writeFile()
   ] : nil
   ```

### Tool Execution Flow

1. **AI sends tool call** → Detected in `ModernAIService.streamAnthropicMessage`
2. **Tool call marker** → `🔧 TOOL_CALL:id:name:base64Input` yielded in stream
3. **ToolCallHandler processes** → Extracts tool call, executes via `ToolExecutionService`
4. **Result notification** → `ToolFileWritten` notification sent for `write_file` operations
5. **ComposerView updates** → Files automatically appear in Composer UI

### Example: Multi-File Edit

User: "Create a login page with authentication"

1. AI calls `codebase_search("authentication")` → Finds auth-related files
2. AI calls `read_file("AuthService.swift")` → Reads existing auth code
3. AI calls `write_file("LoginView.swift", content: "...")` → Creates new file
4. AI calls `write_file("AuthService.swift", content: "...")` → Updates existing file
5. ComposerView shows both files with diffs
6. User clicks "Apply All" → Files written to disk

## Current Limitations

### Tool Result Feedback (Future Enhancement)

Currently, tool results are shown to the user but not sent back to the AI in a follow-up request. For complete agent capabilities, implement:

1. Collect all tool calls during streaming
2. Execute all tools
3. Send follow-up request with tool results:
   ```swift
   messages.append([
       "role": "user",
       "content": [
           ["type": "tool_result", "tool_use_id": id, "content": result]
       ]
   ])
   ```

This enables the AI to:
- Use search results to make informed decisions
- Read files before editing them
- Chain tool calls (search → read → write)

## Files Created/Modified

### New Files
- `LingCode/Services/AITool.swift` - Tool definitions
- `LingCode/Services/ToolExecutionService.swift` - Tool execution
- `LingCode/Services/ToolCallHandler.swift` - Tool call processing

### Modified Files
- `LingCode/Services/ModernAIService.swift` - Tool call detection
- `LingCode/Services/AIProviderProtocol.swift` - Added tools parameter
- `LingCode/ViewModels/AIViewModel.swift` - Tool execution in streaming
- `LingCode/Views/ComposerView.swift` - Tool file write handling

## Testing

To test agent mode:

1. Open ComposerView
2. Type: "Search for authentication code and create a login page"
3. AI should:
   - Call `codebase_search("authentication")`
   - Call `read_file` on found files
   - Call `write_file` to create new files
4. Files should appear in Composer UI
5. Click "Apply All" to write files to disk

## Next Steps

1. **Tool Result Feedback**: Send tool results back to AI for chained tool calls
2. **More Tools**: Add `run_terminal_command`, `search_web`, `read_directory`
3. **Tool Call UI**: Show tool calls in progress (e.g., "🔍 Searching codebase...")
4. **Error Handling**: Better error messages for tool failures
5. **Tool Permissions**: Allow users to approve/reject tool calls
