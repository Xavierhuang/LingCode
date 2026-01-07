//
//  TerminalCommandsView.swift
//  LingCode
//
//  Terminal commands view component
//

import SwiftUI

struct TerminalCommandsView: View {
    let commands: [ParsedCommand]
    let workingDirectory: URL?
    let onRunAll: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with "Run All" button if multiple commands
            if commands.count > 1 {
                HStack {
                    Text("Terminal Commands")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: onRunAll) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Run All")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.2, green: 0.6, blue: 1.0))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Run All Terminal Commands")
                }
                .padding(.horizontal, 4)
            }
            
            ForEach(commands) { command in
                TerminalCommandCard(
                    command: command,
                    workingDirectory: workingDirectory
                )
                .id(command.id.uuidString)
                .transition(.asymmetric(
                    insertion: .move(edge: .top)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.95))
                        .animation(.spring(response: 0.4, dampingFraction: 0.75)),
                    removal: .opacity
                        .combined(with: .scale(scale: 0.95))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8))
                ))
            }
        }
    }
}

