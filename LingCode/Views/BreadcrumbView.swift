//
//  BreadcrumbView.swift
//  LingCode
//
//  Path breadcrumbs + optional symbol breadcrumbs (Tree-sitter; high-frequency UI).
//

import SwiftUI
import EditorParsers

struct BreadcrumbView: View {
    let filePath: URL?
    var content: String?
    var language: String?
    var cursorLine: Int?
    
    var body: some View {
        if let path = filePath {
            VStack(alignment: .leading, spacing: 0) {
                pathRow(path: path)
                if let syms = symbolBreadcrumbComponents, !syms.isEmpty {
                    symbolRow(components: syms)
                }
            }
            .background(DesignSystem.Colors.secondaryBackground)
            .overlay(
                Rectangle()
                    .fill(DesignSystem.Colors.borderSubtle)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }
    
    private func pathRow(path: URL) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(breadcrumbComponents(for: path), id: \.self) { component in
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(component)
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        if component != breadcrumbComponents(for: path).last {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
        }
        .frame(height: 24)
    }
    
    private func symbolRow(components: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(component)
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        if component != components.last {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
        }
        .frame(height: 20)
    }
    
    private var symbolBreadcrumbComponents: [String]? {
        guard let content = content, let language = language, let path = filePath, let line = cursorLine,
              TreeSitterUI.isLanguageSupported(language.lowercased()) else {
            return nil
        }
        return TreeSitterUI.symbolBreadcrumbs(content: content, language: language, fileURL: path, cursorLine: line)
    }
    
    private func breadcrumbComponents(for filePath: URL) -> [String] {
        var components: [String] = []
        var currentPath = filePath
        
        while !currentPath.pathComponents.isEmpty {
            let component = currentPath.lastPathComponent
            if !component.isEmpty && component != "/" {
                components.insert(component, at: 0)
            }
            currentPath = currentPath.deletingLastPathComponent()
            if currentPath.path == "/" || currentPath.path.isEmpty {
                break
            }
        }
        
        return components
    }
}

