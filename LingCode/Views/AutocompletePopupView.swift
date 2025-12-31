//
//  AutocompletePopupView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct AutocompletePopupView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSelect: (AutocompleteSuggestion) -> Void
    @State private var selectedIndex: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.text) { index, suggestion in
                Button(action: {
                    onSelect(suggestion)
                }) {
                    HStack {
                        Image(systemName: "text.word.spacing")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        Text(suggestion.displayText)
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(4)
        .shadow(radius: 4)
        .frame(width: 300)
    }
}








