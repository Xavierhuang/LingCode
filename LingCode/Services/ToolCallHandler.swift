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
        
        // FIX: Detect tool call markers anywhere in the chunk (not just at start)
        // Format: 🔧 TOOL_CALL:id:name:base64Input
        let marker = "🔧 TOOL_CALL:"
        
        // Search for marker in the chunk (may be on a separate line or mixed with text)
        var searchRange = chunk.startIndex..<chunk.endIndex
        while let markerRange = chunk.range(of: marker, range: searchRange) {
            print("🔍 [ToolCallHandler] Detected tool call marker at position \(chunk.distance(from: chunk.startIndex, to: markerRange.lowerBound))")
            
            // Extract the part after the marker
            let afterMarker = chunk[markerRange.upperBound...]
            let parts = String(afterMarker).components(separatedBy: ":")
            print("🔍 [ToolCallHandler] Split into \(parts.count) parts")
            
            if parts.count >= 3 {
                let toolUseId = parts[0]
                let toolName = parts[1]
                // FIX: Join remaining parts (in case base64 contains colons)
                let base64Input = parts.dropFirst(2).joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("🔍 [ToolCallHandler] Tool ID: \(toolUseId), Name: \(toolName), Base64 length: \(base64Input.count)")
                
                // Decode tool input
                if let inputData = Data(base64Encoded: base64Input) {
                    print("🔍 [ToolCallHandler] Base64 decoded successfully, data size: \(inputData.count) bytes")
                    if let inputDict = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] {
                        print("🔍 [ToolCallHandler] JSON parsed successfully, keys: \(inputDict.keys.joined(separator: ", "))")
                        
                        // Convert to AnyCodable
                        let codableInput = inputDict.mapValues { AnyCodable($0) }
                        
                        let toolCall = ToolCall(
                            id: toolUseId,
                            name: toolName,
                            input: codableInput
                        )
                        
                        print("🟢 [ToolCallHandler] Created ToolCall: \(toolName) with \(codableInput.count) input parameters")
                        detectedToolCalls.append(toolCall)
                        pendingToolCalls[toolUseId] = toolCall
                        
                        // Remove tool call marker and its content from text
                        // Find the end of the base64 input (end of line or end of string)
                        if let newlineRange = afterMarker.range(of: "\n", range: afterMarker.startIndex..<afterMarker.endIndex) {
                            let markerEnd = newlineRange.upperBound
                            let beforeMarker = chunk[..<markerRange.lowerBound]
                            let afterMarkerEnd = chunk[markerEnd...]
                            text = String(beforeMarker + afterMarkerEnd)
                        } else {
                            // No newline, remove everything from marker to end
                            text = String(chunk[..<markerRange.lowerBound])
                        }
                    } else {
                        print("🔴 [ToolCallHandler] Failed to parse JSON from decoded data")
                        if let jsonString = String(data: inputData, encoding: .utf8) {
                            print("🔴 [ToolCallHandler] Decoded string: \(jsonString.prefix(200))")
                        }
                    }
                } else {
                    print("🔴 [ToolCallHandler] Failed to decode base64 input")
                    print("🔴 [ToolCallHandler] Base64 string (first 100 chars): \(base64Input.prefix(100))")
                }
            } else {
                print("🔴 [ToolCallHandler] Invalid tool call format - expected at least 3 parts, got \(parts.count)")
                print("🔴 [ToolCallHandler] After marker: \(String(afterMarker.prefix(200)))")
            }
            
            // Continue searching after this marker
            if let nextStart = chunk.index(markerRange.upperBound, offsetBy: 1, limitedBy: chunk.endIndex) {
                searchRange = nextStart..<chunk.endIndex
            } else {
                break
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
