//
//  MinimapView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct MinimapView: View {
    let content: String
    let language: String?
    let visibleRange: NSRange?
    let onScrollTo: (CGFloat) -> Void
    
    @State private var hoveredLine: Int?
    
    private let lineHeight: CGFloat = 2
    private let width: CGFloat = 80
    
    var body: some View {
        GeometryReader { geometry in
            let lines = content.components(separatedBy: .newlines)
            let totalHeight = CGFloat(lines.count) * lineHeight
            let scaleFactor = min(1.0, geometry.size.height / totalHeight)
            
            ZStack(alignment: .topLeading) {
                // Minimap content
                Canvas { context, size in
                    for (index, line) in lines.enumerated() {
                        let y = CGFloat(index) * lineHeight * scaleFactor
                        let lineWidth = min(CGFloat(line.count) * 0.8, width - 10)
                        
                        let color = colorForLine(line, language: language)
                        let rect = CGRect(x: 5, y: y, width: lineWidth, height: lineHeight * scaleFactor)
                        
                        context.fill(Path(rect), with: .color(color))
                    }
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                // Visible area indicator
                if let range = visibleRange {
                    let startY = CGFloat(range.location) * lineHeight * scaleFactor
                    let height = CGFloat(range.length) * lineHeight * scaleFactor
                    
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: width, height: max(20, height))
                        .offset(y: startY)
                }
            }
            .frame(width: width)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let percentage = value.location.y / geometry.size.height
                        onScrollTo(percentage)
                    }
            )
        }
    }
    
    private func colorForLine(_ line: String, language: String?) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Comment
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
            return Color.gray.opacity(0.4)
        }
        
        // Keyword detection
        let keywords = ["func", "class", "struct", "enum", "def", "function", "const", "let", "var", "import", "from"]
        for keyword in keywords {
            if trimmed.hasPrefix(keyword + " ") {
                return Color.blue.opacity(0.6)
            }
        }
        
        // String
        if trimmed.contains("\"") || trimmed.contains("'") {
            return Color.green.opacity(0.5)
        }
        
        // Empty line
        if trimmed.isEmpty {
            return Color.clear
        }
        
        return Color.primary.opacity(0.3)
    }
}

