//
//  StreamingStateViews.swift
//  LingCode
//
//  State views extracted from CursorStreamingView to reduce file size
//  Enhanced with smooth animations that match AI state
//

import SwiftUI

// MARK: - Animated Ring Indicator

struct AnimatedRingIndicator: View {
    let color: Color
    let isActive: Bool
    
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 3)
                .frame(width: 44, height: 44)
                .scaleEffect(scale)
            
            // Rotating dashed ring
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
            
            // Inner solid circle
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 32, height: 32)
            
            // Center icon
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
                .scaleEffect(scale)
        }
        .onAppear {
            if isActive {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.1
                }
            }
        }
    }
}

// MARK: - Generating View

struct StreamingGeneratingView: View {
    let streamingText: String
    let toolCallProgresses: [ToolCallProgress]
    let onApprove: (String) -> Void
    let onReject: (String) -> Void
    
    @State private var appear = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Animated progress indicator
            AnimatedRingIndicator(color: .blue, isActive: true)
                .scaleEffect(appear ? 1.0 : 0.5)
                .opacity(appear ? 1.0 : 0)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: 6) {
                    Text("Generating")
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    // Animated dots
                    AnimatedDots()
                }
                
                Text("AI is writing code")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .opacity(appear ? 1.0 : 0)
            .offset(y: appear ? 0 : 10)
            
            // Pending tool calls
            if !toolCallProgresses.isEmpty {
                ToolCallProgressListView(
                    progresses: toolCallProgresses,
                    onApprove: onApprove,
                    onReject: onReject
                )
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Show live streaming text
            if !streamingText.isEmpty {
                StreamingLivePreview(text: streamingText)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appear = true
            }
        }
    }
}

// MARK: - Animated Dots

struct AnimatedDots: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DesignSystem.Colors.textSecondary)
                    .frame(width: 4, height: 4)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    animationPhase = (animationPhase + 1) % 3
                }
            }
        }
    }
}

// MARK: - Live Preview

struct StreamingLivePreview: View {
    let text: String
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("Live Preview")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    // Content
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.sm)
                        .id("streaming-live")
                }
            }
            .frame(maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
            .onChange(of: text.count) { _, _ in
                withAnimation(.none) {
                    proxy.scrollTo("streaming-live", anchor: .bottom)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Validating View

struct StreamingValidatingView: View {
    @State private var progress: CGFloat = 0
    @State private var appear = false
    @State private var checkmarks: [Bool] = [false, false, false]
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Animated validation indicator
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.orange.opacity(0.15), lineWidth: 3)
                    .frame(width: 44, height: 44)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                
                // Center icon
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
                    .scaleEffect(appear ? 1.0 : 0.5)
            }
            .opacity(appear ? 1.0 : 0)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Validating output...")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Checking code safety and correctness")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .opacity(appear ? 1.0 : 0)
            .offset(y: appear ? 0 : 10)
            
            // Validation checklist
            VStack(alignment: .leading, spacing: 8) {
                ValidationCheckItem(text: "Syntax check", isComplete: checkmarks[0])
                ValidationCheckItem(text: "Type validation", isComplete: checkmarks[1])
                ValidationCheckItem(text: "Safety analysis", isComplete: checkmarks[2])
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .opacity(appear ? 1.0 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appear = true
            }
            
            // Animate progress
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                progress = 0.9
            }
            
            // Animate checkmarks sequentially
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        checkmarks[i] = true
                    }
                }
            }
        }
    }
}

struct ValidationCheckItem: View {
    let text: String
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(isComplete ? Color.green : Color.gray.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(isComplete ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
        }
    }
}

// MARK: - Empty Output View

struct StreamingEmptyOutputView: View {
    let onRetry: () -> Void
    
    @State private var appear = false
    @State private var iconOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.orange)
                .offset(y: iconOffset)
                .opacity(appear ? 1.0 : 0)
                .scaleEffect(appear ? 1.0 : 0.5)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No code changes detected")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("The AI response didn't include any file edits")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .opacity(appear ? 1.0 : 0)
            .offset(y: appear ? 0 : 10)
            
            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text("Try Again")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color.blue)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(appear ? 1.0 : 0)
            .scaleEffect(appear ? 1.0 : 0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                appear = true
            }
            
            // Subtle searching animation
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                iconOffset = -5
            }
        }
    }
}

// MARK: - Empty State View

struct StreamingEmptyStateView: View {
    @State private var sparkleRotation: Double = 0
    @State private var sparkleScale: CGFloat = 1.0
    @State private var appear = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                // Subtle glow
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .blur(radius: 10)
                    .scaleEffect(sparkleScale)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundColor(.blue.opacity(0.7))
                    .rotationEffect(.degrees(sparkleRotation))
                    .scaleEffect(sparkleScale)
            }
            .opacity(appear ? 1.0 : 0)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Ready to assist")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Type a message to start")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .opacity(appear ? 1.0 : 0)
            .offset(y: appear ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appear = true
            }
            
            // Subtle idle animation
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                sparkleScale = 1.05
            }
            
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                sparkleRotation = 10
            }
        }
    }
}

// MARK: - Blocked View

struct StreamingBlockedView: View {
    let reason: String
    let onDismiss: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var appear = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                // Pulsing background
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulseScale)
                
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
            }
            .opacity(appear ? 1.0 : 0)
            .scaleEffect(appear ? 1.0 : 0.5)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Action Required")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(reason)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appear ? 1.0 : 0)
            .offset(y: appear ? 0 : 10)
            
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color.blue)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(appear ? 1.0 : 0)
            .scaleEffect(appear ? 1.0 : 0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                appear = true
            }
            
            // Attention-grabbing pulse
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

// MARK: - Ready View

struct StreamingReadyView: View {
    let editCount: Int
    let onApplyAll: () -> Void
    
    @State private var appear = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var ringProgress: CGFloat = 0
    @State private var buttonGlow: CGFloat = 0
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                // Success ring animation
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                
                // Checkmark with scale animation
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green)
                    .scaleEffect(checkmarkScale)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Ready to apply")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("\(editCount) edit\(editCount == 1 ? "" : "s") ready")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .opacity(appear ? 1.0 : 0)
            .offset(y: appear ? 0 : 10)
            
            Button(action: onApplyAll) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text("Apply All")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color.green)
                        
                        // Glow effect
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color.green.opacity(0.5))
                            .blur(radius: 8)
                            .scaleEffect(1.1)
                            .opacity(buttonGlow)
                    }
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(appear ? 1.0 : 0.8)
            .opacity(appear ? 1.0 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .onAppear {
            // Sequence the animations
            withAnimation(.easeOut(duration: 0.4)) {
                ringProgress = 1.0
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.3)) {
                checkmarkScale = 1.0
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4)) {
                appear = true
            }
            
            // Subtle button glow
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.6)) {
                buttonGlow = 0.4
            }
        }
    }
}

// MARK: - Parse Failure View

struct StreamingParseFailureView: View {
    let rawOutput: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Parse Failed")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            
            Text("The AI output could not be parsed into executable edits. This may happen when the AI responds with explanations instead of code blocks.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !rawOutput.isEmpty {
                DisclosureGroup("Raw Output") {
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .padding()
    }
}
