//
//  AgentPromptBuilder.swift
//  LingCode
//
//  Builds the agent prompt from task, history, and context (extracted from AgentService).
//

import Foundation

enum AgentPromptBuilder {
    
    /// Validates if project URL looks like the system root (a common misconfiguration)
    static func isSystemRoot(_ url: URL?) -> Bool {
        guard let url = url else { return true }
        let path = url.path
        // Detect system root or common system directories
        return path == "/" || path == "/Users" || path == "/System" || path == "/Library" || path.isEmpty
    }
    
    static func buildPrompt(
        task: AgentTask,
        history: String,
        filesRead: [String],
        agentMemory: String,
        loopDetectionHint: String,
        requiresModifications: Bool,
        noFilesWrittenYet: Bool = false,
        iterationCount: Int = 0,
        filesWrittenCount: Int = 0,
        projectStructure: String? = nil
    ) -> String {
        
        // 1. Validate project directory - warn if it looks wrong
        let projectPath = task.projectURL?.path ?? "Unknown"
        let isInvalidProject = isSystemRoot(task.projectURL)
        
        let projectWarning = isInvalidProject ? """
        
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        ! WARNING: Project directory appears to be system root!     !
        ! Path: \(projectPath)                                       
        ! You may be looking at the wrong folder.                   !
        ! Look for project-specific folders like src/, app/, etc.   !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        
        """ : ""
        
        // 2. Project structure - boundaries so the AI knows exactly where it is
        let projectStructureSection: String
        if let structure = projectStructure, !structure.isEmpty {
            projectStructureSection = """
            
            # PROJECT STRUCTURE (your boundaries - work only within these paths)
            \(structure)
            
            """
        } else if !isInvalidProject {
            projectStructureSection = "\n# PROJECT STRUCTURE\n(Call read_directory with \".\" to discover files.)\n\n"
        } else {
            projectStructureSection = ""
        }
        
        // 3. Critical alert for stalled agents
        let criticalAlert: String
        if requiresModifications && noFilesWrittenYet {
            criticalAlert = """
            
            ************************************************************
            *  ATTENTION: You have read files but HAVEN'T modified any!*
            ************************************************************
            
            You MUST call 'write_file' before you can call 'done'.
            If you are unsure, pick the most relevant file from History and improve it now.
            
            """
        } else if iterationCount > 3 && filesWrittenCount == 0 && requiresModifications {
            criticalAlert = """
            
            WARNING: \(iterationCount) iterations without writing any files.
            STOP exploring. You MUST call write_file NOW with improvements.
            
            """
        } else {
            criticalAlert = ""
        }

        // 3. Clearer file history
        let historySection = filesRead.isEmpty ? "" : """
        
        FILES ALREADY ACCESSED (DO NOT read again - content is in History):
        \(filesRead.map { "- \($0)" }.joined(separator: "\n"))
        
        """

        // 4. Determine suggested action
        let hasReadFiles = !filesRead.isEmpty
        let nextStep: String
        if isInvalidProject {
            nextStep = "First, identify the correct project folder. Look for directories like 'src', 'app', 'LingCode', etc."
        } else if !hasReadFiles && history.isEmpty {
            nextStep = "Start by calling read_directory with \".\" to see the project structure."
        } else if hasReadFiles && requiresModifications && filesWrittenCount == 0 {
            nextStep = "You have read files. NOW call write_file to modify one of them."
        } else if filesWrittenCount > 0 {
            nextStep = "Files written. Verify if needed, then call done with a summary."
        } else {
            nextStep = "Perform the next logical action for the task."
        }

        return """
        # ROLE
        You are LingCode's autonomous developer agent.
        Current Project Directory: \(projectPath)
        \(projectWarning)
        \(projectStructureSection)
        # TASK
        \(task.description)
        \(criticalAlert)
        # PROJECT MEMORY
        \(agentMemory.isEmpty ? "No specific memory for this project." : agentMemory)

        # EXECUTION HISTORY
        \(history.isEmpty ? "Task started." : history)
        \(historySection)
        # STRICT RULES
        1. ACTIONS ONLY: Never explain what you are about to do - just call the tool.
        2. NO DUPLICATE READS: Do not call read_file or read_directory for paths already accessed.
        3. MODIFICATION REQUIREMENT: \(requiresModifications ? "This task requires code changes. You MUST call write_file." : "Read-only task.")
        4. VERIFICATION: After writing, you may read once to verify, then call done.

        \(loopDetectionHint.isEmpty ? "" : "LOOP WARNING: \(loopDetectionHint)\n")
        # NEXT STEP
        \(nextStep)
        """
    }
}
