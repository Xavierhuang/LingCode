//
//  LoadingIndicatorView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct LoadingIndicatorView: View {
    @State private var animationPhase: Int = 0
    var onCancel: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.3)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
                
                Text("AI is thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let onCancel = onCancel {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                        Text("Stop")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .onAppear {
            animationPhase = 2
        }
    }
}



