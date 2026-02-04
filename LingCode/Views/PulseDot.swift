//
//  PulseDot.swift
//  LingCode
//
//  Animated status indicators that match AI state
//

import SwiftUI
import Foundation

// MARK: - Basic Pulse Dot

struct PulseDot: View {
    let color: Color
    let size: CGFloat
    let minScale: CGFloat
    let maxScale: CGFloat
    let minOpacity: Double
    let maxOpacity: Double
    let duration: Double

    init(
        color: Color = .accentColor,
        size: CGFloat = 8,
        minScale: CGFloat = 0.7,
        maxScale: CGFloat = 1.0,
        minOpacity: Double = 0.4,
        maxOpacity: Double = 1.0,
        duration: Double = 1.2
    ) {
        self.color = color
        self.size = size
        self.minScale = minScale
        self.maxScale = maxScale
        self.minOpacity = minOpacity
        self.maxOpacity = maxOpacity
        self.duration = duration
    }

    var body: some View {
        TimelineView(.animation) { context in
            let progress = (context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration)) / duration
            let wave = 0.5 + 0.5 * sin(progress * 2.0 * Double.pi)
            let scale = minScale + (maxScale - minScale) * CGFloat(wave)
            let opacity = minOpacity + (maxOpacity - minOpacity) * wave

            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(scale)
                .opacity(opacity)
        }
    }
}

// MARK: - Status Indicator with Ring

struct StatusPulseDot: View {
    let color: Color
    let size: CGFloat
    let isActive: Bool
    
    init(color: Color = .blue, size: CGFloat = 10, isActive: Bool = true) {
        self.color = color
        self.size = size
        self.isActive = isActive
    }
    
    var body: some View {
        TimelineView(.animation) { context in
            let progress = isActive ? (context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.5)) / 1.5 : 0
            let ringScale = 1.0 + (isActive ? progress * 0.5 : 0)
            let ringOpacity = isActive ? 1.0 - progress : 0
            
            ZStack {
                // Expanding ring
                if isActive {
                    Circle()
                        .stroke(color.opacity(ringOpacity * 0.5), lineWidth: 1.5)
                        .frame(width: size * ringScale, height: size * ringScale)
                }
                
                // Core dot
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - AI Thinking Indicator

struct AIThinkingIndicator: View {
    let color: Color
    
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 20, height: 20)
                .blur(radius: 4)
            
            // Rotating arcs
            ForEach(0..<3) { i in
                Circle()
                    .trim(from: CGFloat(i) * 0.2, to: CGFloat(i) * 0.2 + 0.15)
                    .stroke(color.opacity(Double(3 - i) * 0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(rotation + Double(i) * 30))
            }
            
            // Center dot
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Writing Indicator (for code streaming)

struct WritingIndicator: View {
    let color: Color
    
    @State private var currentDot = 0
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .scaleEffect(currentDot == i ? 1.2 : 0.8)
                    .opacity(currentDot == i ? 1.0 : 0.4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    currentDot = (currentDot + 1) % 3
                }
            }
        }
    }
}

// MARK: - Success Checkmark Animation

struct AnimatedCheckmark: View {
    let color: Color
    let size: CGFloat
    
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
                .scaleEffect(scale)
            
            // Checkmark path
            Path { path in
                let rect = CGRect(x: 0, y: 0, width: size * 0.5, height: size * 0.5)
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.7))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.3))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.5, height: size * 0.5)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                trimEnd = 1.0
            }
        }
    }
}

// MARK: - Error Indicator Animation

struct AnimatedError: View {
    let color: Color
    let size: CGFloat
    
    @State private var appear = false
    @State private var shake: CGFloat = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            
            Image(systemName: "xmark")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(color)
        }
        .scaleEffect(appear ? 1.0 : 0.5)
        .opacity(appear ? 1.0 : 0)
        .offset(x: shake)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                appear = true
            }
            
            // Shake animation
            withAnimation(.easeInOut(duration: 0.1).repeatCount(3, autoreverses: true).delay(0.2)) {
                shake = 3
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                shake = 0
            }
        }
    }
}
