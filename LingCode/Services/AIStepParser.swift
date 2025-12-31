//
//  AIStepParser.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

class AIStepParser {
    static let shared = AIStepParser()
    
    private init() {}
    
    func parseResponse(_ response: String) -> (steps: [AIThinkingStep], plan: AIPlan?, actions: [AIAction]) {
        var steps: [AIThinkingStep] = []
        var plan: AIPlan?
        var actions: [AIAction] = []
        
        // Look for structured markers in the response
        let lines = response.components(separatedBy: .newlines)
        var currentStep: AIThinkingStep?
        var currentSection: String?
        var planSteps: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detect planning section
            if trimmed.lowercased().contains("plan:") || 
               trimmed.lowercased().contains("planning:") ||
               trimmed.lowercased().hasPrefix("## plan") ||
               trimmed.lowercased().hasPrefix("### plan") {
                currentSection = "planning"
                if let step = currentStep {
                    steps.append(step)
                }
                currentStep = AIThinkingStep(type: .planning, content: "")
                continue
            }
            
            // Detect thinking section
            if trimmed.lowercased().contains("thinking:") ||
               trimmed.lowercased().contains("reasoning:") ||
               trimmed.lowercased().hasPrefix("## thinking") ||
               trimmed.lowercased().hasPrefix("### thinking") {
                currentSection = "thinking"
                if let step = currentStep {
                    steps.append(step)
                }
                currentStep = AIThinkingStep(type: .thinking, content: "")
                continue
            }
            
            // Detect action section
            if trimmed.lowercased().contains("action:") ||
               trimmed.lowercased().contains("executing:") ||
               trimmed.lowercased().hasPrefix("## action") ||
               trimmed.lowercased().hasPrefix("### action") ||
               trimmed.lowercased().hasPrefix("step ") ||
               trimmed.lowercased().hasPrefix("creating file:") ||
               trimmed.lowercased().hasPrefix("create file:") {
                currentSection = "action"
                if let step = currentStep {
                    steps.append(step)
                }
                currentStep = AIThinkingStep(type: .action, content: trimmed)
                continue
            }
            
            // Detect result section
            if trimmed.lowercased().contains("result:") ||
               trimmed.lowercased().contains("completed:") ||
               trimmed.lowercased().hasPrefix("## result") ||
               trimmed.lowercased().hasPrefix("### result") {
                currentSection = "result"
                if let step = currentStep {
                    let completedStep = AIThinkingStep(
                        id: step.id,
                        type: step.type,
                        content: step.content,
                        timestamp: step.timestamp,
                        isComplete: true
                    )
                    steps.append(completedStep)
                }
                currentStep = AIThinkingStep(type: .result, content: "")
                continue
            }
            
            // Parse plan steps
            if currentSection == "planning" {
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || 
                   trimmed.matches(of: /^\d+[\.\)]/).first != nil {
                    var stepText = trimmed
                    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                        stepText = String(trimmed.dropFirst(2))
                    } else if let match = trimmed.matches(of: /^\d+[\.\)]\s*/).first {
                        stepText = String(trimmed[match.range.upperBound...])
                    }
                    stepText = stepText.trimmingCharacters(in: .whitespaces)
                    if !stepText.isEmpty {
                        planSteps.append(stepText)
                    }
                }
            }
            
            // Accumulate content for current step
            if let step = currentStep, !trimmed.isEmpty {
                let updatedContent = step.content.isEmpty ? trimmed : step.content + "\n" + trimmed
                currentStep = AIThinkingStep(
                    id: step.id,
                    type: step.type,
                    content: updatedContent,
                    timestamp: step.timestamp,
                    isComplete: step.isComplete
                )
            }
        }
        
        // Add final step if exists
        if let step = currentStep {
            steps.append(step)
        }
        
        // Create plan if we found steps
        if !planSteps.isEmpty {
            plan = AIPlan(steps: planSteps, estimatedTime: nil, complexity: nil)
        }
        
        // Extract actions from steps and file operations
        for step in steps where step.type == .action {
            let action = AIAction(
                name: extractActionName(from: step.content),
                description: step.content,
                status: step.isComplete ? .completed : .executing
            )
            actions.append(action)
        }
        
        // Also extract file creation actions from code blocks
        let fileActions = extractFileActions(from: response)
        actions.append(contentsOf: fileActions)
        
        // If no structured steps found, create a single thinking step
        if steps.isEmpty {
            steps.append(AIThinkingStep(type: .thinking, content: response))
        }
        
        return (steps: steps, plan: plan, actions: actions)
    }
    
    private func extractActionName(from content: String) -> String {
        // Try to extract action name from content
        let lines = content.components(separatedBy: .newlines)
        if let firstLine = lines.first {
            // Remove common prefixes
            let cleaned = firstLine
                .replacingOccurrences(of: "Action:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Executing:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Creating file:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Create file:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Step", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            
            if !cleaned.isEmpty {
                return String(cleaned.prefix(50))
            }
        }
        
        return "Action"
    }
    
    private func extractFileActions(from response: String) -> [AIAction] {
        var actions: [AIAction] = []
        var foundPaths = Set<String>()
        
        // Pattern to find file paths followed by code blocks
        // Matches: `path/to/file.ext`:\n```lang\ncontent\n```
        let fileBlockPattern = #"`([^`\n]+\.[a-zA-Z0-9]+)`[:\s]*\n```[a-zA-Z]*\n([\s\S]*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: fileBlockPattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches where match.numberOfRanges > 2 {
                if let pathRange = Range(match.range(at: 1), in: response),
                   let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: CharacterSet(charactersIn: "`*\"'"))
                    let content = String(response[contentRange])
                    
                    if !foundPaths.contains(path) && !path.isEmpty {
                        foundPaths.insert(path)
                        actions.append(AIAction(
                            name: "Create \(path)",
                            description: "Creating file: \(path)",
                            status: .pending,
                            filePath: path,
                            fileContent: content
                        ))
                    }
                }
            }
        }
        
        // Also try alternate pattern: **path/file.ext**:\n```
        let altPattern = #"\*\*([^*\n]+\.[a-zA-Z0-9]+)\*\*[:\s]*\n```[a-zA-Z]*\n([\s\S]*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: altPattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches where match.numberOfRanges > 2 {
                if let pathRange = Range(match.range(at: 1), in: response),
                   let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: .whitespaces)
                    let content = String(response[contentRange])
                    
                    if !foundPaths.contains(path) && !path.isEmpty {
                        foundPaths.insert(path)
                        actions.append(AIAction(
                            name: "Create \(path)",
                            description: "Creating file: \(path)",
                            status: .pending,
                            filePath: path,
                            fileContent: content
                        ))
                    }
                }
            }
        }
        
        // Simple pattern: ### filename.ext\n```\ncontent\n```
        let headerPattern = #"###\s+([^\n]+\.[a-zA-Z0-9]+)\s*\n```[a-zA-Z]*\n([\s\S]*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: headerPattern, options: []) {
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches where match.numberOfRanges > 2 {
                if let pathRange = Range(match.range(at: 1), in: response),
                   let contentRange = Range(match.range(at: 2), in: response) {
                    let path = String(response[pathRange]).trimmingCharacters(in: .whitespaces)
                    let content = String(response[contentRange])
                    
                    if !foundPaths.contains(path) && !path.isEmpty {
                        foundPaths.insert(path)
                        actions.append(AIAction(
                            name: "Create \(path)",
                            description: "Creating file: \(path)",
                            status: .pending,
                            filePath: path,
                            fileContent: content
                        ))
                    }
                }
            }
        }
        
        return actions
    }
    
    // MARK: - Enhanced Prompts
    
    /// Enhance prompt for step-by-step execution
    func enhancePromptForSteps(_ originalPrompt: String) -> String {
        // Detect if this is a project generation request
        let isProjectRequest = originalPrompt.lowercased().contains("project") ||
                              originalPrompt.lowercased().contains("app") ||
                              originalPrompt.lowercased().contains("application") ||
                              originalPrompt.lowercased().contains("create") ||
                              originalPrompt.lowercased().contains("build") ||
                              originalPrompt.lowercased().contains("scaffold")
        
        if isProjectRequest {
            return enhancePromptForProject(originalPrompt)
        }
        
        return enhancePromptForCode(originalPrompt)
    }
    
    /// Enhanced prompt for multi-file project generation
    private func enhancePromptForProject(_ originalPrompt: String) -> String {
        return """
        \(originalPrompt)
        
        Generate ALL files needed for this project. Use this EXACT format:
        
        `path/to/file.ext`:
        ```language
        // complete code here
        ```
        
        Include: main code, config files (package.json etc), README.md
        Use relative paths. Provide COMPLETE working code - no placeholders!
        Just build it - no questions!
        """
    }
    
    /// Enhanced prompt for single file code generation
    private func enhancePromptForCode(_ originalPrompt: String) -> String {
        return """
        \(originalPrompt)
        
        Respond with code immediately. Use this format for files:
        
        `filename.ext`:
        ```language
        // complete code
        ```
        
        Just do it - no need to ask questions. Make reasonable assumptions.
        """
    }
    
    /// Get system prompt for project generation
    func getProjectGenerationSystemPrompt() -> String {
        return """
        You are an expert software developer that GENERATES CODE immediately.

        CRITICAL RULES:
        1. DO NOT ask clarifying questions - make reasonable assumptions and BUILD
        2. ALWAYS generate complete, working code
        3. NEVER say "I need more information" - just create something useful
        4. Be proactive and creative with implementations

        When creating NEW projects:
        1. ALWAYS provide complete, working code for ALL files
        2. Use proper project structure conventions for the language/framework
        3. Include all necessary configuration files
        4. Follow best practices for the technology stack
        5. Provide clear file paths in the format `path/to/file.ext`:

        When MODIFYING existing files:
        **CRITICAL: Always output the COMPLETE file, not snippets!**
        The system replaces entire files - partial code will delete the rest!
        Include ALL original code + your changes.

        OUTPUT FORMAT (REQUIRED):

        `filename.ext`:
        ```language
        // complete code here
        ```

        Example for NEW file:

        `src/main.py`:
        ```python
        def main():
            print("Hello, World!")

        if __name__ == "__main__":
            main()
        ```

        `requirements.txt`:
        ```
        flask==2.0.1
        ```

        Example for modifying existing file:

        `src/main.py`:
        ```python
        import logging  # ADDED

        def main():
            print("Hello, World!")
            logging.info("Application started")  # ADDED

        # Keep all other original functions below!
        def other_function():
            pass

        if __name__ == "__main__":
            main()
        ```

        NEVER use placeholders like "..." or "// rest of code here"
        ALWAYS provide complete file content (full files, not snippets)
        The highlighting system will show users what changed
        JUST BUILD IT - don't ask questions!
        """
    }
    
    /// Get default system prompt for all AI interactions
    func getDefaultSystemPrompt() -> String {
        return """
        You are an expert code assistant in LingCode IDE. Your job is to HELP by DOING.

        CRITICAL BEHAVIOR:
        - DO NOT ask clarifying questions unless absolutely necessary
        - Make reasonable assumptions and proceed with implementation
        - Be proactive - if user says "improve this", just improve it
        - Generate complete, working code
        - When editing existing code, preserve the important parts

        CODE OUTPUT FORMAT:
        Always specify the file path before code blocks:

        `path/to/file.ext`:
        ```language
        // code here
        ```

        TERMINAL COMMANDS:
        When the user asks to "run it", "start it", "execute it", or similar, generate the appropriate terminal commands.
        Detect the project type and provide the correct command:
        - Node.js/React: `npm start` or `npm run dev`
        - Python: `python main.py` or `python app.py`
        - Rust: `cargo run`
        - Swift: `swift run`
        - Go: `go run main.go`

        Format terminal commands like this:
        ```bash
        npm start
        ```

        Or for multiple commands:
        ```bash
        npm install
        npm start
        ```

        CRITICAL FILE OUTPUT RULE:
        **ALWAYS output the COMPLETE file content, never just snippets.**

        WHY: The system replaces entire files. Partial snippets will delete the rest of the file!

        When modifying existing files:
        1. Include ALL original code from the file
        2. Make your specific changes within the complete file
        3. Mark changes with comments like "// CHANGED:" or "// ADDED:" for clarity
        4. The highlighting system will automatically show users what changed

        You can be concise in your EXPLANATION, but code blocks must be complete:
        - ✅ In explanation: "I modified the calculateTotal function on line 15"
        - ✅ In code block: [complete file with all original code + your change]
        - ❌ NEVER: Just the changed function without the rest of the file

        Example for ANY change (small or large):
        `path/to/file.ext`:
        ```language
        // COMPLETE FILE (not a snippet!)
        function calculateTotal(items) {
            let total = 0;
            for (const item of items) {
                total += item.price;
            }
            console.log('Total calculated:', total); // ADDED: Logging
            return total;
        }

        function validateItems(items) {
            // Keep all other original functions!
            return items.every(item => item.price > 0);
        }

        // Include everything from the original file
        ```

        The change highlighting will show users exactly what you modified.

        Be concise, helpful, and action-oriented. Less talk, more code!
        """
    }
    
    /// Detect if user wants to run/execute something
    func detectRunRequest(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        return lowercased.contains("run it") ||
               lowercased.contains("run the") ||
               lowercased.contains("start it") ||
               lowercased.contains("start the") ||
               lowercased.contains("execute it") ||
               lowercased.contains("execute the") ||
               lowercased.contains("launch it") ||
               lowercased.contains("launch the") ||
               lowercased.contains("for me") && (lowercased.contains("run") || lowercased.contains("start") || lowercased.contains("execute"))
    }
    
    /// Enhance prompt for run/execute requests
    func enhancePromptForRun(_ originalPrompt: String, projectURL: URL?) -> String {
        let fileManager = FileManager.default
        
        // Detect project type
        var projectType: String?
        var runCommand: String?
        
        if let projectURL = projectURL {
            if fileManager.fileExists(atPath: projectURL.appendingPathComponent("package.json").path) {
                projectType = "Node.js"
                // Check for scripts in package.json
                if let packageData = try? Data(contentsOf: projectURL.appendingPathComponent("package.json")),
                   let packageJson = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
                   let scripts = packageJson["scripts"] as? [String: String] {
                    if scripts["start"] != nil {
                        runCommand = "npm start"
                    } else if scripts["dev"] != nil {
                        runCommand = "npm run dev"
                    } else if scripts["serve"] != nil {
                        runCommand = "npm run serve"
                    } else {
                        runCommand = "npm start"
                    }
                } else {
                    runCommand = "npm start"
                }
            } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("main.py").path) {
                projectType = "Python"
                runCommand = "python3 main.py"
            } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("app.py").path) {
                projectType = "Python"
                runCommand = "python3 app.py"
            } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) {
                projectType = "Rust"
                runCommand = "cargo run"
            } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) {
                projectType = "Swift"
                runCommand = "swift run"
            } else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("main.go").path) {
                projectType = "Go"
                runCommand = "go run main.go"
            }
        }
        
        var enhanced = originalPrompt
        
        if let type = projectType, let command = runCommand {
            enhanced += "\n\nGenerate the terminal command to run this \(type) project. Use this exact format:\n\n```bash\n\(command)\n```"
        } else {
            enhanced += "\n\nGenerate the appropriate terminal command(s) to run/start/execute the project. Detect the project type and provide the correct command. Format it as:\n\n```bash\n<command>\n```"
        }
        
        return enhanced
    }
}
