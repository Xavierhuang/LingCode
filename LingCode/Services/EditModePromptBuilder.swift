//
//  EditModePromptBuilder.swift
//  LingCode
//
//  Builds strict "Edit Mode" prompts that enforce executable file edits only
//  Rejects prose, summaries, reasoning, or any non-executable output
//

import Foundation

/// Builder for strict Edit Mode prompts
@MainActor
final class EditModePromptBuilder {
    static let shared = EditModePromptBuilder()
    
    private init() {}
    
    /// Build strict Edit Mode system prompt
    func buildEditModeSystemPrompt() -> String {
        return """
        You are an AI editing engine.
        Do NOT explain your reasoning.
        Do NOT summarize.
        Do NOT output markdown, headings, or prose.
        Do NOT output a 'PLAN' section.
        If reasoning is required, do it internally and NEVER output it.
        Output ONLY one of the following:
        - Valid executable file edits
        - OR an explicit NO_OP if no changes are required.

        ALLOWED OUTPUT FORMATS:

        1. File edits (complete file content):
           `path/to/file.ext`:
           ```language
           [complete file content]
           ```

        2. JSON edit format (targeted edits):
           ```json
           {
             "edits": [
               {
                 "file": "path/to/file.ext",
                 "operation": "replace",
                 "range": {"startLine": 10, "endLine": 15},
                 "content": ["new line 1", "new line 2"]
               }
             ]
           }
           ```

        3. Explicit no-op (if no changes needed):
           ```json
           {"noop": true}
           ```

        FORBIDDEN OUTPUT (will cause validation failure):
        - Any text before or after file code blocks
        - Markdown headings (##, ###, #) including '## PLAN'
        - Bullet points or lists (-, *, •)
        - Explanatory text ("Here's what I changed:", "I'll update the file:", etc.)
        - Reasoning sections ("Thinking Process", "Summary", "Explanation", etc.)
        - Any prose, summaries, or non-executable content

        ENFORCEMENT:
        - All reasoning must be internal - it must NEVER appear in your output
        - If no changes are needed, output ONLY: {"noop": true}
        - If changes are needed, output ONLY the file edits in the allowed format
        - The validator will reject any response containing forbidden content
        """
    }
    
    /// Build Edit Mode user prompt with strict instructions
    func buildEditModeUserPrompt(instruction: String) -> String {
        return """
        Execute this edit request.

        Output ONLY executable file edits in the allowed format.
        Do NOT explain your reasoning.
        Do NOT output a Plan.
        Do NOT output markdown headings.
        If you need to reason, do it internally and NEVER output it.

        Request: \(instruction)
        """
    }
}
