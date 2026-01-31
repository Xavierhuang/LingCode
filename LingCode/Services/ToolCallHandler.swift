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
    
    // Buffer for incomplete tool calls that span multiple chunks
    private var incompleteToolCallBuffer: String = ""
    
    private init() {}
    
    /// Process a chunk from AI stream - detect and handle tool calls
    func processChunk(_ chunk: String, projectURL: URL?) -> (text: String, toolCalls: [ToolCall]) {
        // Combine buffer with new chunk
        let combinedChunk = incompleteToolCallBuffer + chunk
        incompleteToolCallBuffer = ""
        
        var text = combinedChunk
        var detectedToolCalls: [ToolCall] = []
        
        // FIX: Detect tool call markers anywhere in the chunk (not just at start)
        // Format: TOOL_CALL:id:name:base64Input\n
        let marker = "TOOL_CALL:"
        
        // Search for marker in the chunk (may be on a separate line or mixed with text)
        var searchRange = combinedChunk.startIndex..<combinedChunk.endIndex
        while let markerRange = combinedChunk.range(of: marker, range: searchRange) {
            print("🔍 [ToolCallHandler] Detected tool call marker at position \(combinedChunk.distance(from: combinedChunk.startIndex, to: markerRange.lowerBound))")
            
            // Extract the part after the marker
            let afterMarker = combinedChunk[markerRange.upperBound...]
            
            // Find the end of the tool call (newline or end of string)
            let newlineRange = afterMarker.range(of: "\n", range: afterMarker.startIndex..<afterMarker.endIndex)
            let toolCallEnd = newlineRange?.lowerBound ?? afterMarker.endIndex
            
            // Extract the tool call data (everything from marker to newline or end)
            let toolCallData = String(afterMarker[..<toolCallEnd])
            
            // Check if we have a complete tool call (ends with newline)
            if newlineRange == nil {
                // Incomplete tool call - buffer it for next chunk
                print("🔍 [ToolCallHandler] Incomplete tool call detected, buffering \(toolCallData.count) chars")
                incompleteToolCallBuffer = String(combinedChunk[markerRange.lowerBound...])
                // Remove the incomplete marker from text
                text = String(combinedChunk[..<markerRange.lowerBound])
                break
            }
            
            // Complete tool call - parse it
            let parts = toolCallData.components(separatedBy: ":")
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
                        let markerEnd = newlineRange!.upperBound
                        let beforeMarker = combinedChunk[..<markerRange.lowerBound]
                        let afterMarkerEnd = combinedChunk[markerEnd...]
                        text = String(beforeMarker + afterMarkerEnd)
                    } else {
                        print("🔴 [ToolCallHandler] Failed to parse JSON from decoded data")
                        if let jsonString = String(data: inputData, encoding: .utf8) {
                            print("🔴 [ToolCallHandler] Decoded string: \(jsonString.prefix(200))")
                        }
                        // Remove the invalid marker from text
                        let markerEnd = newlineRange!.upperBound
                        let beforeMarker = combinedChunk[..<markerRange.lowerBound]
                        let afterMarkerEnd = combinedChunk[markerEnd...]
                        text = String(beforeMarker + afterMarkerEnd)
                    }
                } else {
                    print("🔴 [ToolCallHandler] Failed to decode base64 input")
                    print("🔴 [ToolCallHandler] Base64 string (first 100 chars): \(base64Input.prefix(100))")
                    // Remove the invalid marker from text
                    let markerEnd = newlineRange!.upperBound
                    let beforeMarker = combinedChunk[..<markerRange.lowerBound]
                    let afterMarkerEnd = combinedChunk[markerEnd...]
                    text = String(beforeMarker + afterMarkerEnd)
                }
            } else {
                print("🔴 [ToolCallHandler] Invalid tool call format - expected at least 3 parts, got \(parts.count)")
                print("🔴 [ToolCallHandler] Tool call data: \(toolCallData.prefix(200))")
                // Remove the invalid marker from text
                let markerEnd = newlineRange!.upperBound
                let beforeMarker = combinedChunk[..<markerRange.lowerBound]
                let afterMarkerEnd = combinedChunk[markerEnd...]
                text = String(beforeMarker + afterMarkerEnd)
            }
            
            // Continue searching after this marker
            if let nextStart = combinedChunk.index(markerRange.upperBound, offsetBy: 1, limitedBy: combinedChunk.endIndex) {
                searchRange = nextStart..<combinedChunk.endIndex
            } else {
                break
            }
        }
        
        return (text, detectedToolCalls)
    }
    
    /// Flush any incomplete tool calls (call when stream ends)
    func flush() -> [ToolCall] {
        var toolCalls: [ToolCall] = []
        
        if !incompleteToolCallBuffer.isEmpty {
            print("🔍 [ToolCallHandler] Flushing incomplete tool call buffer: \(incompleteToolCallBuffer.prefix(100))...")
            // Temporarily save and clear the buffer, then process with newline
            let savedBuffer = incompleteToolCallBuffer
            incompleteToolCallBuffer = ""
            // Add a newline to make it parseable (stream ended without newline)
            let bufferWithNewline = savedBuffer + "\n"
            let (_, calls) = processChunk(bufferWithNewline, projectURL: nil)
            toolCalls.append(contentsOf: calls)
        }
        
        return toolCalls
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
        incompleteToolCallBuffer = ""
    }
}
