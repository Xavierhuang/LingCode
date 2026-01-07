//
//  BreadcrumbView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct BreadcrumbView: View {
    let filePath: URL?
    
    var body: some View {
        if let path = filePath {
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
            .background(DesignSystem.Colors.secondaryBackground)
            .overlay(
                Rectangle()
                    .fill(DesignSystem.Colors.borderSubtle)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
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

