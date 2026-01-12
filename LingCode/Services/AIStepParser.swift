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
        let lowercased = originalPrompt.lowercased()
        let isProjectRequest = lowercased.contains("project") ||
                              lowercased.contains("app") ||
                              lowercased.contains("application") ||
                              lowercased.contains("create") ||
                              lowercased.contains("build") ||
                              lowercased.contains("scaffold") ||
                              lowercased.contains("landing page") ||
                              lowercased.contains("website") ||
                              lowercased.contains("web app") ||
                              lowercased.contains("web application") ||
                              lowercased.contains("dashboard") ||
                              lowercased.contains("portfolio") ||
                              lowercased.contains("blog") ||
                              lowercased.contains("write me") ||
                              lowercased.contains("make me") ||
                              lowercased.contains("build me")
        
        if isProjectRequest {
            return enhancePromptForProject(originalPrompt)
        }
        
        // Even for single-file requests, encourage complete implementations
        return enhancePromptForCode(originalPrompt)
    }
    
    /// Enhanced prompt for multi-file project generation
    private func enhancePromptForProject(_ originalPrompt: String) -> String {
        let lowercased = originalPrompt.lowercased()
        let isWebsite = lowercased.contains("website") || 
                       lowercased.contains("web page") || 
                       lowercased.contains("webpage") ||
                       lowercased.contains("landing page") ||
                       lowercased.contains("site")
        
        var websiteSpecificInstructions = ""
        if isWebsite {
            websiteSpecificInstructions = """
            
            ⚠️⚠️⚠️ **MANDATORY WEBSITE GENERATION PROTOCOL** ⚠️⚠️⚠️
            
            **YOU ARE REQUIRED TO GENERATE EXACTLY 3 FILES. NO EXCEPTIONS.**
            
            **STEP-BY-STEP CHECKLIST (YOU MUST COMPLETE ALL STEPS):**
            
            STEP 1: Generate `index.html`
            - HTML structure ONLY
            - MUST include: <link rel="stylesheet" href="styles.css">
            - MUST include: <script src="script.js"></script>
            - NO <style> tags with CSS code
            - NO <script> tags with JavaScript code (only the src attribute)
            
            STEP 2: Generate `styles.css`  
            - ALL CSS styling goes here
            - Complete, working stylesheet
            - NO inline styles in HTML
            - NO <style> tags in HTML
            
            STEP 3: Generate `script.js`
            - ALL JavaScript functionality goes here
            - Complete, working JavaScript code
            - NO <script> tags with code in HTML
            - Only <script src="script.js"></script> in HTML
            
            **OUTPUT FORMAT - COPY THIS EXACT STRUCTURE:**
            
            `index.html`:
            ```html
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>My Website</title>
                <link rel="stylesheet" href="styles.css">
            </head>
            <body>
                <!-- Your HTML content here -->
                <script src="script.js"></script>
            </body>
            </html>
            ```
            
            `styles.css`:
            ```css
            /* ALL your CSS styling goes here */
            body {
                margin: 0;
                padding: 0;
            }
            /* Continue with all styles... */
            ```
            
            `script.js`:
            ```javascript
            // ALL your JavaScript code goes here
            document.addEventListener('DOMContentLoaded', function() {
                // Your code...
            });
            ```
            
            **CRITICAL REMINDERS:**
            - You MUST output all 3 files in your response
            - Do NOT stop after generating index.html
            - Do NOT embed CSS or JS in HTML
            - If you reference a file (styles.css, script.js), you MUST generate that file
            - Your response is incomplete if it only contains index.html
            
            **VERIFICATION: Before you finish, check:**
            ✓ Did I generate index.html? 
            ✓ Did I generate styles.css?
            ✓ Did I generate script.js?
            ✓ Are all 3 files in my response?
            
            If any answer is NO, you MUST continue generating until all 3 files are complete.
            
            """
        }
        
        return """
        \(originalPrompt)
        
        **CRITICAL: Generate a COMPLETE, WORKING application with ALL necessary files.**
        
        This means:
        - HTML/CSS/JS files (if web-based) - SEPARATE FILES, not embedded!
        - Configuration files (package.json, requirements.txt, etc.)
        - README.md with setup instructions
        - All assets and dependencies
        - A fully functional, runnable application
        \(websiteSpecificInstructions)
        Use this EXACT format for each file:
        
        `path/to/file.ext`:
        ```language
        // complete code here - NO placeholders!
        ```
        
        **DO NOT** generate just one file. Generate the ENTIRE application structure.
        **DO NOT** embed CSS in <style> tags or JS in <script> tags - use separate files!
        **DO NOT** ask questions - make reasonable assumptions and build it.
        **DO NOT** use placeholders like "..." or "// rest of code here"
        
        Include ALL files needed to run the application immediately.
        Use relative paths from the project root.
        Provide COMPLETE working code - no placeholders!
        Just build it - no questions!
        """
    }
    
    /// Enhanced prompt for single file code generation
    private func enhancePromptForCode(_ originalPrompt: String) -> String {
        // Check if this might actually need multiple files
        let lowercased = originalPrompt.lowercased()
        let mightNeedMultipleFiles = lowercased.contains("page") ||
                                    lowercased.contains("site") ||
                                    lowercased.contains("component") ||
                                    lowercased.contains("feature") ||
                                    lowercased.contains("module")
        
        if mightNeedMultipleFiles {
            return """
            \(originalPrompt)
            
            **IMPORTANT: If this request requires multiple files (HTML + CSS + JS, or multiple components), generate ALL of them.**
            
            **WORKFLOW:**
            1. Think out loud - explain what you're going to do
            2. Generate each file that needs to be created or changed
            
            Use this format for each file:
            
            `path/to/file.ext`:
            ```language
            // complete code - NO placeholders!
            ```
            
            Generate a COMPLETE, working implementation. If it needs:
            - HTML file → generate it
            - CSS file → generate it
            - JavaScript file → generate it
            - Config files → generate them
            - README → generate it
            
            Don't just generate one file if the request needs multiple files to work.
            Make reasonable assumptions and build the complete solution.
            """
        }
        
        return """
        \(originalPrompt)
        
        **WORKFLOW:**
        1. Think out loud - explain what you're going to do and which files need changes
        2. Generate code for each file that needs to be changed
        
        Use this format for files:
        
        `filename.ext`:
        ```language
        // complete code
        ```
        
        For existing files, include ALL original code and make your changes within it.
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

        When creating NEW projects or applications:
        1. ALWAYS provide complete, working code for ALL files needed
        2. Use proper project structure conventions for the language/framework
        3. Include all necessary configuration files (package.json, requirements.txt, etc.)
        4. Include README.md with setup and run instructions
        5. Follow best practices for the technology stack
        6. Provide clear file paths in the format `path/to/file.ext`:
        7. **CRITICAL for websites/web pages**: You MUST generate EXACTLY 3 SEPARATE FILES:
           STEP 1: Generate index.html (HTML structure only, MUST use <link rel="stylesheet" href="styles.css"> and <script src="script.js"></script>)
           STEP 2: Generate styles.css (ALL CSS styling, NO <style> tags in HTML, NO inline styles)
           STEP 3: Generate script.js (ALL JavaScript, NO <script> tags with code in HTML, only <script src="script.js"></script>)
           **YOU MUST COMPLETE ALL 3 STEPS. DO NOT STOP AFTER STEP 1. YOUR RESPONSE IS INCOMPLETE IF IT ONLY HAS HTML.**
        8. If it's a React/Vue/Angular app, include all component files and config
        9. Make it runnable immediately - no missing dependencies or files
        10. **NEVER generate just one HTML file with embedded CSS/JS for websites!**
        11. **If you reference a file in HTML (like styles.css or script.js), YOU MUST GENERATE THAT FILE IN THE SAME RESPONSE!**
        12. **For website requests, count your files before finishing: You need 3 files (HTML, CSS, JS). If you only have 1, you're not done!**

        When MODIFYING existing files:
        **CRITICAL: Always output the COMPLETE file, not snippets!**
        The system replaces entire files - partial code will delete the rest!
        
        **BEFORE MODIFYING ANY FILE:**
        1. Look for the existing file content in the context above (it will be marked with "--- filename.ext ---" or "--- filename.ext (EXISTING - PRESERVE ALL CODE) ---")
        2. Read and preserve ALL existing code from that file - EVERY LINE, EVERY FUNCTION, EVERY VARIABLE
        3. Make your changes while keeping ALL original code intact
        4. Output the COMPLETE file with ALL original code + your changes
        
        **CRITICAL RULES FOR MODIFICATIONS:**
        - NEVER delete existing code unless explicitly asked to remove it
        - NEVER replace entire functions - only modify what needs to change
        - ALWAYS include ALL original code in your output
        - If you see "EXISTING - PRESERVE ALL CODE" in context, that file MUST keep all its current content
        - When upgrading/improving, ADD new features while keeping ALL existing features
        - If you don't see the file content in context, you MUST ask or preserve what you know should be there
        
        **Example of CORRECT modification:**
        Original file has 500 lines of JavaScript code.
        User asks to "upgrade" or "improve" it.
        Your output MUST include all 500 original lines PLUS your improvements.
        Your output should be 500+ lines, not 10 lines!

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
        
        PREFERRED OUTPUT FORMAT (for edits):
        For code modifications, you can use structured JSON edit format:
        ```json
        {
          "edits": [
            {
              "file": "path/to/file.ext",
              "operation": "replace",
              "range": {
                "startLine": 10,
                "endLine": 15
              },
              "content": [
                "line 1 of new code",
                "line 2 of new code"
              ]
            }
          ]
        }
        ```
        
        Operations: "insert", "replace", "delete"
        If using JSON format, ensure all edits are valid and within file bounds.

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
