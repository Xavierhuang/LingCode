//
//  ActivityBarView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

enum ActivityItem: String, CaseIterable {
    case files = "Files"
    case search = "Search"
    case git = "Source Control"
    case ai = "AI Assistant"
    case outline = "Outline"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .files: return "doc.on.doc"
        case .search: return "magnifyingglass"
        case .git: return "arrow.triangle.branch"
        case .ai: return "sparkles"
        case .outline: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

struct ActivityBarView: View {
    @Binding var selectedItem: ActivityItem
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(ActivityItem.allCases.filter { $0 != .settings }, id: \.self) { item in
                ActivityBarButton(
                    item: item,
                    isSelected: selectedItem == item,
                    action: { selectedItem = item }
                )
            }
            
            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(width: 48)
        .background(DesignSystem.Colors.secondaryBackground)
    }
}

struct ActivityBarButton: View {
    let item: ActivityItem
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: item.icon)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .foregroundColor(
                    isSelected ? DesignSystem.Colors.accent :
                    (isHovered ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                )
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(
                            isSelected ? DesignSystem.Colors.sidebarSelected :
                            (isHovered ? DesignSystem.Colors.sidebarHover : Color.clear)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.quick) {
                isHovered = hovering
            }
        }
        .help(item.rawValue)
    }
}

