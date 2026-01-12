//
//  DesignSystem.swift
//  LingCode
//
//  Modern design system for LingCode UI
//

import SwiftUI
import AppKit

struct DesignSystem {
    // MARK: - Colors
    
    struct Colors {
        // Background colors
        static let primaryBackground = Color(NSColor.windowBackgroundColor)
        static let secondaryBackground = Color(NSColor.controlBackgroundColor)
        static let tertiaryBackground = Color(NSColor.textBackgroundColor)
        
        // Surface colors (for cards, panels)
        static let surface = Color(NSColor.controlBackgroundColor)
        static let surfaceElevated = Color(NSColor.windowBackgroundColor)
        static let surfaceHover = Color(NSColor.controlAccentColor).opacity(0.1)
        
        // Border colors
        static let border = Color(NSColor.separatorColor)
        static let borderSubtle = Color(NSColor.separatorColor).opacity(0.5)
        
        // Text colors
        static let textPrimary = Color(NSColor.labelColor)
        static let textSecondary = Color(NSColor.secondaryLabelColor)
        static let textTertiary = Color(NSColor.tertiaryLabelColor)
        
        // Accent colors
        static let accent = Color.accentColor
        static let accentMuted = Color.accentColor.opacity(0.6)
        
        // Status colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // Sidebar specific
        static let sidebarBackground = Color(NSColor.controlBackgroundColor).opacity(0.8)
        static let sidebarHover = Color(NSColor.controlAccentColor).opacity(0.15)
        static let sidebarSelected = Color(NSColor.selectedContentBackgroundColor)
        
        // Editor specific
        static let editorBackground = Color(NSColor.textBackgroundColor)
        static let editorBorder = Color(NSColor.separatorColor).opacity(0.3)
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Typography
    
    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title1 = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 15, weight: .semibold, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
        static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xlarge: CGFloat = 16
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        static let small = Shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        static let medium = Shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        static let large = Shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
    
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    
    // MARK: - Animation
    
    struct Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let smooth = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let bouncy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.6)
    }
}

// MARK: - View Modifiers

extension View {
    func cardStyle(elevated: Bool = false) -> some View {
        self
            .background(elevated ? DesignSystem.Colors.surfaceElevated : DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .shadow(
                color: DesignSystem.Shadows.small.color,
                radius: DesignSystem.Shadows.small.radius,
                x: DesignSystem.Shadows.small.x,
                y: DesignSystem.Shadows.small.y
            )
    }
    
    func panelStyle() -> some View {
        self
            .background(DesignSystem.Colors.sidebarBackground)
            .overlay(
                Rectangle()
                    .fill(DesignSystem.Colors.borderSubtle)
                    .frame(width: 1)
                    .offset(x: -0.5),
                alignment: .trailing
            )
    }
    
    func sectionHeader() -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
    }
}

