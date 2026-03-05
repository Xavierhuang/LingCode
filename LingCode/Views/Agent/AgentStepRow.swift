//
//  AgentStepRow.swift
//  LingCode
//
//  Displays a single step in the agent task execution
//

import SwiftUI

struct AgentStepRow: View {
    let step: AgentStep
    var projectURL: URL? = nil
    var onOpenFile: ((String) -> Void)? = nil
    @State private var isExpanded: Bool

    init(step: AgentStep, projectURL: URL? = nil, onOpenFile: ((String) -> Void)? = nil) {
        self.step = step
        self.projectURL = projectURL
        self.onOpenFile = onOpenFile
        _isExpanded = State(initialValue: step.status != .failed)
    }

    private var fullPathForFile: String? {
        guard let path = step.targetFilePath else { return nil }
        if path.hasPrefix("/") { return path }
        guard let root = projectURL else { return path }
        return root.appendingPathComponent(path).path
    }

    private var isFileWriteStep: Bool {
        step.type == .codeGeneration || 
        step.description.lowercased().contains("write:") ||
        step.streamingCode != nil
    }
    
    private var isFileReadStep: Bool {
        step.type == .fileOperation || step.description.lowercased().contains("read:")
    }

    private var isReplaceStep: Bool {
        step.description.hasPrefix("Replace in ")
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

    private var isTaskHeader: Bool {
        step.type == .taskHeader
    }

    private var isCompleteStep: Bool {
        step.type == .complete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            if !isTaskHeader { contentView }
        }
        .padding(12)
        .background(isTaskHeader ? Color(NSColor.controlBackgroundColor).opacity(0.3) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .onChange(of: step.status) { _, newStatus in
            if newStatus == .failed {
                DispatchQueue.main.async { isExpanded = false }
            }
        }
    }

    // MARK: - Header
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isTaskHeader { StatusIndicator(status: step.status) }
            VStack(alignment: .leading, spacing: 4) {
                descriptionView
                    .font(.system(size: isTaskHeader ? 13 : 14, weight: isTaskHeader ? .medium : .medium))
                    .foregroundColor(isTaskHeader ? .secondary : .primary)
                if !isTaskHeader { statusText }
                if let error = step.error {
                    let summary = error.count > 80 ? String(error.prefix(80)) + "..." : error
                    Text(isExpanded ? error : summary)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(isExpanded ? nil : 2)
                }
                
                if let result = step.result, !isFileWriteStep && !isFileReadStep {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            if !isTaskHeader {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Image(systemName: stepIcon)
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isTaskHeader else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var descriptionView: some View {
        if let path = step.targetFilePath, onOpenFile != nil {
            let displayName = fileName ?? path
            let prefix: String = {
                if step.description.hasPrefix("Replace in ") { return "Replace in " }
                if step.description.lowercased().hasPrefix("write:") { return "Write: " }
                if step.description.lowercased().hasPrefix("read:") { return "Read: " }
                return step.description.replacingOccurrences(of: displayName, with: "").trimmingCharacters(in: .whitespacesAndNewlines) + " "
            }()
            HStack(spacing: 0) {
                Text(prefix)
                Button(displayName) {
                    onOpenFile?(path)
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .contentShape(Rectangle())
            }
            .help(fullPathForFile ?? path)
        } else {
            Text(step.description)
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        if step.status == .running {
            // Don't show status text if StreamingCodeBox will be shown (it has its own "Writing" badge)
            if isFileWriteStep {
                EmptyView()
            } else if isFileReadStep {
                // Read steps don't open a content view - show "Processing..." while running
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    PulseDot(color: .accentColor, size: 6, minScale: 0.8, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 0.8)
                    Text("Processing...")
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
                fileName: fileName,
                previousContent: step.originalContent
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeOut(duration: 0.2), value: codeContent)
        } else if isExpanded && isReplaceStep {
            let isNoOp = (step.output?.contains("No change;") ?? false) || (step.replaceOldString == step.replaceNewString && step.replaceOldString != nil)
            if isNoOp, let output = step.output, !output.isEmpty {
                regularOutputView(output: output)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let oldStr = step.replaceOldString, let newStr = step.replaceNewString {
                replaceDiffView(oldString: oldStr, newString: newStr)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let output = step.output, !output.isEmpty {
                regularOutputView(output: output)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } else if isExpanded && isCompleteStep, let output = step.output, !output.isEmpty {
            TypingTextView(fullText: output)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if isExpanded, !isFileWriteStep, !isFileReadStep, let output = step.output, !output.isEmpty {
            regularOutputView(output: output)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private func replaceDiffView(oldString: String, newString: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(oldString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.red.opacity(0.2))
                .cornerRadius(4)
                .textSelection(.enabled)
            Text(newString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func regularOutputView(output: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(output)
                    .font(.system(size: 11, design: .monospaced))
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
                DispatchQueue.main.async {
                    if step.status == .running {
                        withAnimation(.none) {
                            proxy.scrollTo("streaming-output", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Typing Text View (Cursor-style character-by-character reveal)

/// Reveals `fullText` character by character with a blinking cursor.
/// Plain prose styling — not a code box.
struct TypingTextView: View {
    let fullText: String

    @State private var displayedCount: Int = 0
    @State private var cursorVisible: Bool = true
    @State private var timer: Timer? = nil
    @State private var blinkTimer: Timer? = nil

    private let charsPerTick: Int = 4
    private let tickInterval: TimeInterval = 0.018

    private var isFinished: Bool { displayedCount >= fullText.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(String(fullText.prefix(displayedCount)))
                .foregroundColor(.primary)
             + (isFinished ? Text("") : Text(cursorVisible ? "▍" : " ")
                .foregroundColor(.accentColor))
            )
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
        .onAppear {
            startTyping()
        }
        .onChange(of: fullText) { _, _ in
            stopTimers()
            displayedCount = 0
            startTyping()
        }
        .onDisappear {
            stopTimers()
        }
    }

    private func startTyping() {
        displayedCount = 0
        cursorVisible = true

        // Single typing timer — invalidates itself when done
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { t in
            let next = min(displayedCount + charsPerTick, fullText.count)
            displayedCount = next
            if displayedCount >= fullText.count {
                t.invalidate()
                timer = nil
                cursorVisible = false
                blinkTimer?.invalidate()
                blinkTimer = nil
            }
        }

        // Slow blink timer — 2 Hz, only while typing
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard !isFinished else { return }
            cursorVisible.toggle()
        }
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
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
