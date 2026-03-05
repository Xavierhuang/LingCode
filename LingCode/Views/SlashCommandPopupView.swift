//
//  SlashCommandPopupView.swift
//  LingCode
//
//  Floating popup that appears when the user types "/" in the chat input.
//  Supports keyboard navigation (Up/Down/Return) and mouse click selection.
//

import SwiftUI

// MARK: - Popup view

struct SlashCommandPopupView: View {
    /// The portion of input after the "/" prefix, used to filter the list.
    let query: String
    /// Called when the user picks a command. Passes the full "/name " string.
    let onSelect: (Skill) -> Void
    /// Called when the user presses Escape or clicks outside.
    let onDismiss: () -> Void

    @StateObject private var skillsService = SkillsService.shared
    @State private var selectedIndex: Int = 0

    private var suggestions: [Skill] {
        skillsService.getSlashSuggestions("/" + query)
    }

    var body: some View {
        VStack(spacing: 0) {
            if suggestions.isEmpty {
                Text("No matching commands")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(DesignSystem.Spacing.md)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, skill in
                                SlashCommandRow(
                                    skill: skill,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(skill)
                                }
                                .onHover { hovering in
                                    if hovering { selectedIndex = index }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                    .onChange(of: query) { _, _ in
                        selectedIndex = 0
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.secondaryBackground)
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 1)
        )
        .frame(width: 340)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(suggestions.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !suggestions.isEmpty else { return .ignored }
            onSelect(suggestions[selectedIndex])
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }
}

// MARK: - Row

private struct SlashCommandRow: View {
    let skill: Skill
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(categoryColor(for: skill.category).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: skill.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(categoryColor(for: skill.category))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("/\(skill.name)")
                        .font(DesignSystem.Typography.caption1.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text("·")
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Text(skill.category.rawValue)
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Text(skill.description)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? DesignSystem.Colors.sidebarSelected
                : Color.clear
        )
    }

    private func categoryColor(for category: SkillCategory) -> Color {
        switch category {
        case .git:          return .orange
        case .code:         return .blue
        case .testing:      return .green
        case .documentation: return .purple
        case .refactoring:  return .yellow
        case .debugging:    return .red
        case .custom:       return .gray
        }
    }
}
