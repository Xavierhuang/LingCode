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
                HStack(spacing: 4) {
                    ForEach(breadcrumbComponents(for: path), id: \.self) { component in
                        HStack(spacing: 4) {
                            Text(component)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            if component != breadcrumbComponents(for: path).last {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 20)
            .background(Color(NSColor.controlBackgroundColor))
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

