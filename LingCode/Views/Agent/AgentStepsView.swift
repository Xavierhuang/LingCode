//
//  AgentStepsView.swift
//  LingCode
//
//  Displays the steps of an agent task with streaming support
//

import SwiftUI

struct AgentStepsView: View {
    @ObservedObject var agent: AgentService
    @Binding var lastStepCount: Int
    var bottomID: Namespace.ID
    var projectURL: URL? = nil
    var onOpenFile: ((String) -> Void)? = nil

    @State private var thinkingStartTime: Date?
    @State private var showLongWaitNote: Bool = false
    @State private var longWaitWorkItem: DispatchWorkItem?
    
    private var shouldShowStreamingPreview: Bool {
        guard agent.isRunning else { return false }
        if agent.steps.isEmpty { return true }
        
        if let lastStep = agent.steps.last {
            if lastStep.streamingCode != nil { return false }
            if let output = lastStep.output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if lastStep.status == .running { return true }
        }
        return false
    }
    
    /// Filter steps to avoid redundant "Task Complete" cards
    /// Only show the final .complete step, filter out intermediate ones
    private var filteredSteps: [AgentStep] {
        var result: [AgentStep] = []
        var lastCompleteStep: AgentStep?
        
        for step in agent.steps {
            if step.type == .complete {
                // Keep track of the last complete step
                lastCompleteStep = step
            } else {
                // Add non-complete steps
                result.append(step)
            }
        }
        
        // Only add the final complete step if agent is not running
        // (If running, more steps might come, so don't show "complete" yet)
        if !agent.isRunning, let completeStep = lastCompleteStep {
            result.append(completeStep)
        }
        
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if shouldShowStreamingPreview, !agent.streamingText.isEmpty {
                        streamingPreviewView(text: agent.streamingText)
                            .id("streaming-preview")
                            .transition(.opacity)
                    }
                    if showLongWaitNote {
                        Text("Taking longer than usual. The model may be thinking or generating a large response.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }

                    // Filter out intermediate "Task Complete" steps - only show the final one
                    // This prevents multiple "Task Complete" cards from stacking up
                    ForEach(filteredSteps) { step in
                        AgentStepRow(step: step, projectURL: projectURL, onOpenFile: onOpenFile)
                            .id(step.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: agent.steps.count)
            }
            .onChange(of: agent.steps.count) { _, newCount in
                DispatchQueue.main.async {
                    if newCount > lastStepCount {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                        lastStepCount = newCount
                    }
                    if let last = agent.steps.last, last.type != .thinking {
                        longWaitWorkItem?.cancel()
                        longWaitWorkItem = nil
                        thinkingStartTime = nil
                        showLongWaitNote = false
                    }
                }
            }
            .onChange(of: agent.isRunning) { _, running in
                DispatchQueue.main.async {
                    if !running {
                        longWaitWorkItem?.cancel()
                        longWaitWorkItem = nil
                        thinkingStartTime = nil
                        showLongWaitNote = false
                        return
                    }
                    showLongWaitNote = false
                    guard thinkingStartTime == nil else { return }
                    thinkingStartTime = Date()
                    let item = DispatchWorkItem { [weak agent] in
                        DispatchQueue.main.async {
                            if agent?.isRunning == true {
                                showLongWaitNote = true
                            }
                        }
                    }
                    longWaitWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: item)
                }
            }
            .onChange(of: agent.steps.last?.output) { _, _ in
                DispatchQueue.main.async { scrollToBottomIfRunning(proxy: proxy) }
            }
            .onChange(of: agent.steps.last?.streamingCode) { _, _ in
                DispatchQueue.main.async { scrollToBottomIfRunning(proxy: proxy) }
            }
            .onChange(of: agent.streamingText) { _, _ in
                DispatchQueue.main.async {
                    if shouldShowStreamingPreview {
                        withAnimation(.none) {
                            proxy.scrollTo("streaming-preview", anchor: .bottom)
                        }
                    } else {
                        scrollToBottomIfRunning(proxy: proxy)
                    }
                }
            }
            .onChange(of: agent.steps.last?.status) { _, newStatus in
                DispatchQueue.main.async {
                    if newStatus != .failed {
                        scrollToBottomIfRunning(proxy: proxy)
                    }
                }
            }
        }
    }
    
    private func scrollToBottomIfRunning(proxy: ScrollViewProxy) {
        if agent.isRunning {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    private func streamingPreviewView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PulseDot(color: .accentColor, size: 8, minScale: 0.8, maxScale: 1.0, minOpacity: 0.6, maxOpacity: 1.0, duration: 1.0)
                Text("Analyzing task...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ScrollViewReader { innerProxy in
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("streaming-text-end")
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .onChange(of: text) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.none) {
                            innerProxy.scrollTo("streaming-text-end", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

}
