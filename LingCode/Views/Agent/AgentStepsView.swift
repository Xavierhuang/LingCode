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
                    if shouldShowStreamingPreview {
                        if !agent.streamingText.isEmpty {
                            streamingPreviewView(text: agent.streamingText)
                                .id("streaming-preview")
                                .transition(.opacity)
                        } else {
                            connectingPreviewView
                                .id("streaming-preview")
                                .transition(.opacity)
                        }
                    }
                    
                    // Filter out intermediate "Task Complete" steps - only show the final one
                    // This prevents multiple "Task Complete" cards from stacking up
                    ForEach(filteredSteps) { step in
                        AgentStepRow(step: step)
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
                if newCount > lastStepCount {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                    lastStepCount = newCount
                }
            }
            .onChange(of: agent.steps.last?.output) { _, _ in
                scrollToBottomIfRunning(proxy: proxy)
            }
            .onChange(of: agent.steps.last?.streamingCode) { _, _ in
                scrollToBottomIfRunning(proxy: proxy)
            }
            .onChange(of: agent.streamingText) { _, _ in
                if shouldShowStreamingPreview {
                    withAnimation(.none) {
                        proxy.scrollTo("streaming-preview", anchor: .bottom)
                    }
                } else {
                    scrollToBottomIfRunning(proxy: proxy)
                }
            }
            .onChange(of: agent.steps.last?.status) { _, _ in
                scrollToBottomIfRunning(proxy: proxy)
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
                        .font(.system(.caption, design: .monospaced))
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
                    withAnimation(.none) {
                        innerProxy.scrollTo("streaming-text-end", anchor: .bottom)
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

    private var connectingPreviewView: some View {
        HStack(spacing: 8) {
            PulseDot(color: .accentColor, size: 8, minScale: 0.8, maxScale: 1.0, minOpacity: 0.5, maxOpacity: 1.0, duration: 1.1)
            Text("Connecting to model...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}
