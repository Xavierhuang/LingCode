//
//  ToolCallHandler.swift
//  LingCode
//
//  Handles tool calls from AI streaming responses
//  Extracts tool calls, executes them, and manages tool result responses
//

import Foundation

/// Handles tool calls in AI streaming responses
@MainActor
class ToolCallHandler {
    static let shared = ToolCallHandler()
    
    private let toolExecutor = ToolExecutionService.shared
    private var pendingToolCalls: [String: ToolCall] = [:]
    private var toolResults: [String: ToolResult] = [:]
    
    private init() {}
    
    /// Process a chunk from AI stream - detect and handle tool calls
    func processChunk(_ chunk: String, projectURL: URL?) -> (text: String, toolCalls: [ToolCall]) {
        var text = chunk
        var detectedToolCalls: [ToolCall] = []
        
        // FIX: Detect tool call markers in stream
        // Format: 🔧 TOOL_CALL:id:name:base64Input
        if chunk.hasPrefix("🔧 TOOL_CALL:") {
            let parts = chunk.dropFirst("🔧 TOOL_CALL:".count).components(separatedBy: ":")
            if parts.count >= 3 {
                let toolUseId = parts[0]
                let toolName = parts[1]
                let base64Input = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Decode tool input
                if let inputData = Data(base64Encoded: base64Input),
                   let inputDict = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] {
                    
                    // Convert to AnyCodable
                    let codableInput = inputDict.mapValues { AnyCodable($0) }
                    
                    let toolCall = ToolCall(
                        id: toolUseId,
                        name: toolName,
                        input: codableInput
                    )
                    
                    detectedToolCalls.append(toolCall)
                    pendingToolCalls[toolUseId] = toolCall
                    
                    // Remove tool call marker from text
                    text = ""
                }
            }
        }
        
        return (text, detectedToolCalls)
    }
    
    /// Execute a tool call and return the result
    func executeToolCall(_ toolCall: ToolCall, projectURL: URL?) async throws -> ToolResult {
        // Set project URL for relative path resolution
        toolExecutor.setProjectURL(projectURL)
        
        // Execute tool
        let result = try await toolExecutor.executeToolCall(toolCall)
        toolResults[toolCall.id] = result
        
        return result
    }
    
    /// Get tool result for a tool use ID
    func getToolResult(for toolUseId: String) -> ToolResult? {
        return toolResults[toolUseId]
    }
    
    /// Clear all pending tool calls and results
    func clear() {
        pendingToolCalls.removeAll()
        toolResults.removeAll()
    }
}
