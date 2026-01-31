//
//  PulseDot.swift
//  LingCode
//
//  Subtle animated status indicator
//

import SwiftUI
import Foundation

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
