//
//  AgentStepRow.swift
//  LingCode
//
//  Displays a single step in the agent task execution
//

import SwiftUI

struct AgentStepRow: View {
    let step: AgentStep
    @State private var isExpanded: Bool = true
    
    private var isFileWriteStep: Bool {
        step.type == .codeGeneration || 
        step.description.lowercased().contains("write:") ||
        step.streamingCode != nil
    }
    
    private var isFileReadStep: Bool {
        step.type == .fileOperation || step.description.lowercased().contains("read:")
    }
    
    private var fileName: String? {
        if let path = step.targetFilePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if step.description.lowercased().contains("write:") {
            let parts = step.description.components(separatedBy: ":")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        if step.description.contains(" in ") {
            let parts = step.description.components(separatedBy: " in ")
            if parts.count > 1 {
                return URL(fileURLWithPath: parts[1]).lastPathComponent
            }
        }
        return nil
    }
    
    private var codeContent: String? {
        // Trust the AgentService's extraction first (streamingCode is populated by service)
        if let streamingCode = step.streamingCode, !streamingCode.isEmpty {
            return streamingCode
        }
        
        // Fallback only if the step is finished and we need to parse the final output
        guard step.status != .running else { return nil }
        guard let output = step.output, !output.isEmpty else { return nil }
        
        // Try marker-based extraction for completed steps
        if let startRange = output.range(of: "---\n") {
            let contentStart = startRange.upperBound
            if let endRange = output.range(of: "\n--- End of", options: .backwards, range: contentStart..<output.endIndex) {
                return String(output[contentStart..<endRange.lowerBound])
            } else {
                let partialContent = String(output[contentStart...])
                if !partialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return partialContent
                }
            }
        }
        
        // Fallback: detect code patterns
        let codePatterns = ["import ", "function ", "<!DOCTYPE", "<html", "class ", "struct ", "const ", "let ", "def ", "func "]
        if codePatterns.contains(where: { output.contains($0) }) {
            return output
        }
        
        return nil
    }
    
    private var hasWriteContent: Bool {
        isFileWriteStep && (step.streamingCode != nil || codeContent != nil)
    }
    
    private var extractReadFileName: String? {
        if step.description.lowercased().contains("read:") {
            let parts = step.description.components(separatedBy: ":")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private var stepIcon: String {
        if isFileWriteStep { return "doc.badge.plus" }
        if isFileReadStep { return "doc.text" }
        return step.type.icon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            contentView
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIndicator(status: step.status)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(step.description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                statusText
                
                if let error = step.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if let result = step.result, !isFileWriteStep && !isFileReadStep {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            Image(systemName: stepIcon)
                .foregroundColor(.secondary)
                .font(.system(size: 14))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        if step.status == .running {
            // Don't show "Writing..." or "Reading..." if we have content boxes that already show status
            if isFileWriteStep && hasWriteContent {
                // StreamingCodeBox already shows "Writing" badge - don't duplicate
                EmptyView()
            } else if isFileReadStep && step.output != nil && !(step.output ?? "").isEmpty {
                // FileReadBox already shows "Reading" badge - don't duplicate
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    PulseDot(color: .accentColor, size: 6, minScale: 0.8, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 0.8)
                    Text(isFileWriteStep ? "Writing..." : (isFileReadStep ? "Reading..." : "Processing..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if step.status == .completed && (isFileWriteStep || isFileReadStep) {
            Text("Success")
                .font(.caption)
                .foregroundColor(.green)
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        if isExpanded && isFileWriteStep && (step.status == .running || hasWriteContent) {
            StreamingCodeBox(
                content: codeContent ?? step.streamingCode ?? "",
                isStreaming: step.status == .running,
                fileName: fileName
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeOut(duration: 0.2), value: codeContent)
        } else if isExpanded && isFileReadStep && (step.status == .running || (step.output != nil && !(step.output ?? "").isEmpty)) {
            FileReadBox(
                content: step.output ?? "",
                isStreaming: step.status == .running,
                fileName: extractReadFileName
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if isExpanded, !isFileWriteStep, !isFileReadStep, let output = step.output, !output.isEmpty {
            regularOutputView(output: output)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private func regularOutputView(output: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id("streaming-output")
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .onChange(of: output) { _, _ in
                if step.status == .running {
                    withAnimation(.none) {
                        proxy.scrollTo("streaming-output", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: AgentStepStatus
    
    var body: some View {
        Group {
            switch status {
            case .pending:
                Circle()
                    .strokeBorder(Color.gray, lineWidth: 2)
                    .frame(width: 16, height: 16)
            case .running:
                PulseDot(color: Color.accentColor.opacity(0.8), size: 10)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
            case .cancelled:
                Image(systemName: "slash.circle")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
            }
        }
    }
}
