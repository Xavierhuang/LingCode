//
//  DefinitionPopupView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct DefinitionPopupView: View {
    let symbol: String
    let definitions: [Definition]
    let onSelect: (Definition) -> Void
    let onClose: () -> Void
    
    @State private var selectedDefinition: Definition?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.right.square")
                Text("Go to Definition: \(symbol)")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if definitions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No definition found")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if definitions.count == 1 {
                // Single definition - show preview
                let def = definitions[0]
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: iconFor(def.kind))
                            .foregroundColor(colorFor(def.kind))
                        Text(def.file.lastPathComponent)
                            .font(.headline)
                        Text(":\(def.line)")
                            .foregroundColor(.secondary)
                    }
                    
                    Text(def.preview)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                    
                    HStack {
                        Spacer()
                        Button("Go to Definition") {
                            onSelect(def)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                // Multiple definitions - show list
                List {
                    ForEach(definitions) { def in
                        Button(action: { onSelect(def) }) {
                            HStack {
                                Image(systemName: iconFor(def.kind))
                                    .foregroundColor(colorFor(def.kind))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(def.file.lastPathComponent)
                                        .font(.headline)
                                    Text(def.preview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Text(":\(def.line)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 500, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 10)
    }
    
    private func iconFor(_ kind: Definition.DefinitionKind) -> String {
        switch kind {
        case .function: return "f.square"
        case .variable: return "v.square"
        case .classDefinition: return "c.square"
        case .structure: return "s.square"
        case .enumeration: return "e.square"
        case .interface: return "i.square"
        case .type: return "t.square"
        case .module: return "m.square"
        }
    }
    
    private func colorFor(_ kind: Definition.DefinitionKind) -> Color {
        switch kind {
        case .function: return .purple
        case .variable: return .blue
        case .classDefinition: return .orange
        case .structure: return .orange
        case .enumeration: return .green
        case .interface: return .yellow
        case .type: return .cyan
        case .module: return .gray
        }
    }
}

struct ReferencesPopupView: View {
    let symbol: String
    let references: [Reference]
    let projectURL: URL?
    let onSelect: (Reference) -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "link")
                Text("References: \(symbol)")
                    .font(.headline)
                Spacer()
                Text("\(references.count) found")
                    .foregroundColor(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if references.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No references found")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(references) { ref in
                        Button(action: { onSelect(ref) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(ref.file.lastPathComponent)
                                            .font(.headline)
                                        Text(":\(ref.line)")
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(ref.context)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 10)
    }
}

