//
//  EditModePromptBuilder.swift
//  LingCode
//
//  Builds strict "Edit Mode" prompts that enforce executable file edits only
//  Rejects prose, summaries, reasoning, or any non-executable output
//
//  ARCHITECTURAL INVARIANT: HARD SEPARATION OF PHASES
//  - Thinking/planning MUST be internal to the model and never streamed
//  - Only executable edit output may reach the parser
//  - The parser must never see reasoning, plans, headings, or summaries
//  - UI "Thinking..." state is driven by session state, NOT model text
//  - Timeline events are derived from state transitions, NOT AI output
//

import Foundation

/// Builder for strict Edit Mode prompts
///
/// EDIT MODE CONTRACT:
/// - AI response MUST contain ONLY file edits, file creations, or explicit no-op
/// - Absolutely NO prose, summaries, or reasoning text allowed
/// - Reject responses containing markdown headings, bullet points, or explanations
///
/// HARD SEPARATION OF PHASES:
/// - The prompt explicitly forbids reasoning output
/// - If reasoning is required, it must be internal to the model and NEVER output
/// - This ensures the parser never sees reasoning, plans, headings, or summaries
@MainActor
final class EditModePromptBuilder {
    static let shared = EditModePromptBuilder()
    
    private init() {}
    
    /// Build strict Edit Mode system prompt
    ///
    /// HARD SEPARATION OF PHASES:
    /// - Thinking/planning MUST be internal to the model and never streamed
    /// - Only executable edit output may reach the parser
    /// - The parser must never see reasoning, plans, headings, or summaries
    ///
    /// ARCHITECTURAL INVARIANT:
    /// "You are an AI editing engine. Do NOT explain your reasoning.
    /// Do NOT summarize. Do NOT output markdown, headings, or prose.
    /// If reasoning is required, do it internally and NEVER output it."
    func buildEditModeSystemPrompt() -> String {
        return """
        You are an AI editing engine.
        Do NOT explain your reasoning.
        Do NOT summarize.
        Do NOT output markdown, headings, or prose.
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
        - Markdown headings (##, ###, #)
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
    ///
    /// HARD SEPARATION: This prompt ensures the model outputs ONLY executable edits.
    /// No reasoning, planning, or explanation text is allowed.
    ///
    /// - Parameter instruction: User's edit instruction
    /// - Returns: Prompt that enforces edit-only output
    func buildEditModeUserPrompt(instruction: String) -> String {
        return """
        Execute this edit request.

        Output ONLY executable file edits in the allowed format.
        Do NOT explain your reasoning.
        Do NOT summarize.
        Do NOT output markdown, headings, or prose.
        If you need to reason, do it internally and NEVER output it.

        Request: \(instruction)
        """
    }
}
