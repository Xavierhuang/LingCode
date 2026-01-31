//
//  ToolCallHandler.swift
//  LingCode
//
//  Handles tool calls from AI streaming responses.
//  ToolCall parsing is delegated to EditorCore.StreamParser; this class converts and executes.
//

import Foundation
import EditorCore

/// Handles tool calls in AI streaming responses
@MainActor
class ToolCallHandler {
    static let shared = ToolCallHandler()
    
    private let toolExecutor = ToolExecutionService.shared
    private var pendingToolCalls: [String: ToolCall] = [:]
    private var toolResults: [String: ToolResult] = [:]
    private var streamParser = StreamParser()
    
    private init() {}
    
    /// Process a chunk from AI stream - uses StreamParser for parsing, returns ToolCall for execution
    func processChunk(_ chunk: String, projectURL: URL?) -> (text: String, toolCalls: [ToolCall]) {
        var (text, parsed) = streamParser.processChunk(chunk)
        let toolCalls = parsed.compactMap { convertToToolCall($0) }
        for tc in toolCalls { pendingToolCalls[tc.id] = tc }
        return (text, toolCalls)
    }
    
    /// Flush any incomplete tool calls (call when stream ends)
    func flush() -> [ToolCall] {
        var parsed = streamParser.flush()
        return parsed.compactMap { convertToToolCall($0) }
    }
    
    private func convertToToolCall(_ p: ParsedToolCall) -> ToolCall? {
        guard let inputDict = try? JSONSerialization.jsonObject(with: p.inputData) as? [String: Any] else { return nil }
        let codableInput = inputDict.mapValues { AnyCodable($0) }
        return ToolCall(id: p.id, name: p.name, input: codableInput)
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
        streamParser = StreamParser()
    }
}
