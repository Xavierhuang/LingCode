//
//  StreamingResponseView.swift
//  LingCode
//
//  Streaming response view component (Cursor-style)
//

import SwiftUI

struct StreamingResponseView: View {
    let content: String
    let onContentChange: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.3, blue: 0.9))
                
                Text("AI Response")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                            .frame(width: 4, height: 4)
                            .opacity(0.9)
                            .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.6), radius: 2)
                        
                        Circle()
                            .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.5), lineWidth: 1)
                            .frame(width: 8, height: 8)
                            .scaleEffect(content.isEmpty ? 1.0 : 1.5)
                            .opacity(content.isEmpty ? 0.0 : 0.0)
                            .animation(
                                Animation.easeOut(duration: 0.8)
                                    .repeatForever(autoreverses: false),
                                value: content
                            )
                    }
                    Text("Streaming")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.4)
            )
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Streaming cursor
                    if !content.isEmpty {
                        HStack(spacing: 0) {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3))
                                    .frame(width: 2, height: 16)
                                
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                                    .frame(width: 2, height: 16)
                                    .opacity(0.9)
                                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.8), radius: 2)
                                    .animation(
                                        Animation.easeInOut(duration: 1.0)
                                            .repeatForever(autoreverses: true),
                                        value: content
                                    )
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 200)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onChange(of: content) { _, newValue in
            onContentChange(newValue)
        }
    }
}

