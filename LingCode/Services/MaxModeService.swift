//
//  MaxModeService.swift
//  LingCode
//
//  Max Mode - Extended thinking and enhanced reasoning (like Cursor's Max Mode)
//  Enables longer, more thorough AI responses with explicit reasoning
//

import Foundation
import Combine

// MARK: - Max Mode Settings

struct MaxModeSettings: Codable, Equatable {
    var isEnabled: Bool
    var thinkingBudget: ThinkingBudget
    var showThinkingProcess: Bool
    var useChainOfThought: Bool
    var maxTokenMultiplier: Double  // How much to multiply default max tokens
    var enableSelfReflection: Bool
    var iterationLimit: Int
    
    static let `default` = MaxModeSettings(
        isEnabled: false,
        thinkingBudget: .medium,
        showThinkingProcess: true,
        useChainOfThought: true,
        maxTokenMultiplier: 2.0,
        enableSelfReflection: true,
        iterationLimit: 3
    )
}

enum ThinkingBudget: String, Codable, CaseIterable {
    case quick = "Quick"
    case medium = "Medium"
    case thorough = "Thorough"
    case maximum = "Maximum"
    
    var description: String {
        switch self {
        case .quick: return "Fast responses with basic reasoning"
        case .medium: return "Balanced thinking and response time"
        case .thorough: return "Deep analysis with detailed reasoning"
        case .maximum: return "Exhaustive exploration of all angles"
        }
    }
    
    var tokenMultiplier: Double {
        switch self {
        case .quick: return 1.0
        case .medium: return 1.5
        case .thorough: return 2.0
        case .maximum: return 3.0
        }
    }
    
    var thinkingTokens: Int {
        switch self {
        case .quick: return 500
        case .medium: return 1500
        case .thorough: return 3000
        case .maximum: return 6000
        }
    }
}

// MARK: - Thinking Process

struct ThinkingProcess: Identifiable {
    let id = UUID()
    var steps: [MaxModeThinkingStep]
    var startTime: Date
    var endTime: Date?
    var totalTokens: Int
    var conclusion: String?
}

struct MaxModeThinkingStep: Identifiable {
    let id = UUID()
    let type: MaxModeStepType
    let content: String
    let timestamp: Date
    var isComplete: Bool
}

enum MaxModeStepType: String {
    case analyzing = "Analyzing"
    case planning = "Planning"
    case researching = "Researching"
    case reasoning = "Reasoning"
    case evaluating = "Evaluating"
    case synthesizing = "Synthesizing"
    case reflecting = "Reflecting"
    case concluding = "Concluding"
    
    var icon: String {
        switch self {
        case .analyzing: return "magnifyingglass"
        case .planning: return "list.bullet.clipboard"
        case .researching: return "doc.text.magnifyingglass"
        case .reasoning: return "brain"
        case .evaluating: return "checkmark.circle"
        case .synthesizing: return "arrow.triangle.merge"
        case .reflecting: return "arrow.2.squarepath"
        case .concluding: return "flag.checkered"
        }
    }
}

// MARK: - Max Mode Service

class MaxModeService: ObservableObject {
    static let shared = MaxModeService()
    
    @Published var settings: MaxModeSettings
    @Published var currentThinkingProcess: ThinkingProcess?
    @Published var isThinking: Bool = false
    
    private let settingsURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        settingsURL = lingcodeDir.appendingPathComponent("max_mode_settings.json")
        
        settings = MaxModeService.loadSettings(from: settingsURL)
    }
    
    // MARK: - Settings Management
    
    func updateSettings(_ newSettings: MaxModeSettings) {
        settings = newSettings
        saveSettings()
    }
    
    func toggleMaxMode() {
        settings.isEnabled.toggle()
        saveSettings()
    }
    
    func setThinkingBudget(_ budget: ThinkingBudget) {
        settings.thinkingBudget = budget
        saveSettings()
    }
    
    // MARK: - Enhanced Prompts
    
    /// Build system prompt for Max Mode
    func buildMaxModeSystemPrompt(basePrompt: String) -> String {
        guard settings.isEnabled else { return basePrompt }
        
        var enhanced = basePrompt
        
        enhanced += """
        
        ## Extended Thinking Mode
        
        You are in Max Mode with extended thinking capabilities. Take your time to provide thorough, well-reasoned responses.
        
        """
        
        if settings.useChainOfThought {
            enhanced += """
            
            ### Chain of Thought
            
            Before providing your final answer, think through the problem step by step:
            
            1. **Understand**: Restate the problem in your own words
            2. **Analyze**: Break down the components and requirements
            3. **Plan**: Outline your approach before implementing
            4. **Execute**: Implement the solution carefully
            5. **Verify**: Check your work for errors or improvements
            
            """
        }
        
        if settings.enableSelfReflection {
            enhanced += """
            
            ### Self-Reflection
            
            After generating a response, reflect on:
            - Are there any edge cases I missed?
            - Is this the most efficient/clean solution?
            - Have I fully addressed the user's intent?
            - What could go wrong with this approach?
            
            If you identify issues, revise your answer.
            
            """
        }
        
        enhanced += """
        
        ### Thinking Budget: \(settings.thinkingBudget.rawValue)
        
        \(settings.thinkingBudget.description)
        
        Show your reasoning process using <thinking> tags when appropriate.
        
        """
        
        return enhanced
    }
    
    /// Get adjusted max tokens for Max Mode
    func getMaxTokens(base: Int) -> Int {
        guard settings.isEnabled else { return base }
        
        let multiplier = settings.maxTokenMultiplier * settings.thinkingBudget.tokenMultiplier
        return Int(Double(base) * multiplier)
    }
    
    // MARK: - Thinking Process Tracking
    
    func startThinkingProcess() {
        currentThinkingProcess = ThinkingProcess(
            steps: [],
            startTime: Date(),
            totalTokens: 0
        )
        isThinking = true
    }
    
    func addThinkingStep(type: MaxModeStepType, content: String) {
        let step = MaxModeThinkingStep(
            type: type,
            content: content,
            timestamp: Date(),
            isComplete: false
        )
        currentThinkingProcess?.steps.append(step)
    }
    
    func completeCurrentStep() {
        guard var process = currentThinkingProcess,
              !process.steps.isEmpty else { return }
        
        let lastIndex = process.steps.count - 1
        process.steps[lastIndex].isComplete = true
        currentThinkingProcess = process
    }
    
    func finishThinkingProcess(conclusion: String, tokens: Int) {
        currentThinkingProcess?.endTime = Date()
        currentThinkingProcess?.conclusion = conclusion
        currentThinkingProcess?.totalTokens = tokens
        isThinking = false
    }
    
    // MARK: - Parse Thinking from Response
    
    /// Extract thinking steps from AI response
    func parseThinkingFromResponse(_ response: String) -> (thinking: [MaxModeThinkingStep], answer: String) {
        var steps: [MaxModeThinkingStep] = []
        var cleanAnswer = response
        
        // Extract <thinking> blocks
        let thinkingPattern = #"<thinking>([\s\S]*?)</thinking>"#
        if let regex = try? NSRegularExpression(pattern: thinkingPattern, options: []) {
            let range = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches.reversed() {
                if let thinkingRange = Range(match.range(at: 1), in: response) {
                    let thinkingContent = String(response[thinkingRange])
                    
                    // Parse thinking content into steps
                    let parsedSteps = parseThinkingContent(thinkingContent)
                    steps.append(contentsOf: parsedSteps)
                }
                
                // Remove thinking block from answer
                if let fullRange = Range(match.range, in: cleanAnswer) {
                    cleanAnswer.removeSubrange(fullRange)
                }
            }
        }
        
        return (steps, cleanAnswer.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func parseThinkingContent(_ content: String) -> [MaxModeThinkingStep] {
        var steps: [MaxModeThinkingStep] = []
        
        let lines = content.components(separatedBy: "\n")
        var currentType: MaxModeStepType = .reasoning
        var currentContent = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for step markers
            if let type = detectStepType(trimmed) {
                // Save previous step
                if !currentContent.isEmpty {
                    steps.append(MaxModeThinkingStep(
                        type: currentType,
                        content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines),
                        timestamp: Date(),
                        isComplete: true
                    ))
                }
                currentType = type
                currentContent = trimmed
            } else {
                currentContent += "\n" + line
            }
        }
        
        // Add last step
        if !currentContent.isEmpty {
            steps.append(MaxModeThinkingStep(
                type: currentType,
                content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines),
                timestamp: Date(),
                isComplete: true
            ))
        }
        
        return steps
    }
    
    private func detectStepType(_ line: String) -> MaxModeStepType? {
        let lowercased = line.lowercased()
        
        if lowercased.contains("analyz") { return .analyzing }
        if lowercased.contains("plan") { return .planning }
        if lowercased.contains("research") { return .researching }
        if lowercased.contains("reason") { return .reasoning }
        if lowercased.contains("evaluat") || lowercased.contains("check") { return .evaluating }
        if lowercased.contains("synthesi") || lowercased.contains("combin") { return .synthesizing }
        if lowercased.contains("reflect") || lowercased.contains("reconsider") { return .reflecting }
        if lowercased.contains("conclud") || lowercased.contains("final") { return .concluding }
        
        return nil
    }
    
    // MARK: - Iterative Refinement
    
    /// Run iterative refinement if enabled
    func shouldRefine(response: String, iteration: Int) -> Bool {
        guard settings.isEnabled && settings.enableSelfReflection else { return false }
        guard iteration < settings.iterationLimit else { return false }
        
        // Check if response indicates need for refinement
        let lowercased = response.lowercased()
        let needsRefinement = lowercased.contains("could be improved") ||
                              lowercased.contains("alternative approach") ||
                              lowercased.contains("however, ") ||
                              lowercased.contains("on second thought")
        
        return needsRefinement
    }
    
    func buildRefinementPrompt(originalResponse: String, iteration: Int) -> String {
        return """
        You provided this response:
        
        \(originalResponse)
        
        This is refinement iteration \(iteration + 1) of \(settings.iterationLimit).
        
        Please reflect on your response:
        1. Are there any errors or inaccuracies?
        2. Is there a more efficient or elegant solution?
        3. Are there edge cases that weren't handled?
        4. Is the code readable and maintainable?
        
        If improvements are needed, provide a refined response. If not, confirm the response is optimal.
        """
    }
    
    // MARK: - Persistence
    
    private static func loadSettings(from url: URL) -> MaxModeSettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(MaxModeSettings.self, from: data)
        } catch {
            print("MaxModeService: Failed to load settings: \(error)")
            return .default
        }
    }
    
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL)
        } catch {
            print("MaxModeService: Failed to save settings: \(error)")
        }
    }
}
