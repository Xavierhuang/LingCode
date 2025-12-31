//
//  LineNumbersView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct LineNumbersView: View {
    let lineCount: Int
    let fontSize: CGFloat
    let fontName: String
    var editorScrollView: NSScrollView? = nil
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...max(1, lineCount), id: \.self) { lineNumber in
                        HStack {
                            Spacer()
                            Text("\(lineNumber)")
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundColor(lineNumberColor)
                                .padding(.trailing, 8)
                        }
                        .frame(height: lineHeight)
                    }
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(gutterBackground)
    }
    
    private var lineNumberColor: Color {
        colorScheme == .dark 
            ? Color(white: 0.5)
            : Color(white: 0.4)
    }
    
    private var gutterBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.15)
            : Color(white: 0.93)
    }
    
    private var lineHeight: CGFloat {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return font.ascender - font.descender + font.leading
    }
}
