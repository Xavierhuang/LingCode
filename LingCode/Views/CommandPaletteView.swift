//
//  CommandPaletteView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let commands: [Command]
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    var filteredCommands: [Command] {
        if searchText.isEmpty {
            return commands
        }
        return commands.filter { command in
            command.title.localizedCaseInsensitiveContains(searchText) ||
            command.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "command")
                    .foregroundColor(.secondary)
                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        if selectedIndex < filteredCommands.count {
                            filteredCommands[selectedIndex].action()
                            isPresented = false
                        }
                    }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(
                            command: command,
                            isSelected: index == selectedIndex
                        )
                        .onTapGesture {
                            command.action()
                            isPresented = false
                        }
                    }
                }
            }
            .frame(height: 300)
        }
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            isFocused = true
        }
        .onChange(of: searchText) { oldValue, newValue in
            selectedIndex = 0
        }
    }
}

struct Command: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let keywords: [String]
    let action: () -> Void
}

struct CommandRow: View {
    let command: Command
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13))
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

