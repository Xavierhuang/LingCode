//
//  AutocompletePopupView.swift
//  LingCode
//
//  IntelliSense-style autocomplete dropdown
//

import SwiftUI

struct AutocompletePopupView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSelect: (AutocompleteSuggestion) -> Void
    let position: CGPoint
    
    @State private var selectedIndex: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                AutocompleteItemView(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex
                )
                .onTapGesture {
                    onSelect(suggestion)
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 8)
        .position(position)
        .onAppear {
            selectedIndex = 0
        }
    }
}

struct AutocompleteItemView: View {
    let suggestion: AutocompleteSuggestion
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.displayText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isSelected ? .white : .primary)
                
                if let detail = suggestion.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            
            Spacer()
            
            if suggestion.documentation != nil {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(4)
    }
}
