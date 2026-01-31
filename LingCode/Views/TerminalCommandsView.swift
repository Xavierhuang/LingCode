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
            }
        }
    }
}

// MARK: - Terminal Command Card

struct TerminalCommandCard: View {
    let command: ParsedCommand
    let workingDirectory: URL?
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var isHovering = false
    @State private var isExecuting = false
    @State private var hasExecuted = false
    @State private var output = ""
    @State private var exitCode: Int32?
    @State private var showOutput = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Command header
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Text(command.command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                
                Spacer()
                
                if command.isDestructive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .help("Destructive command")
                }
                
                // Run button
                Button(action: runCommand) {
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if hasExecuted {
                        Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(exitCode == 0 ? .green : .red)
                    } else {
                        Image(systemName: "play.fill")
                            .foregroundColor(.green)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isExecuting)
                
                // Copy button
                Button(action: copyCommand) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Description if present
            if let description = command.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Output if executed
            if hasExecuted && !output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { showOutput.toggle() }) {
                        HStack {
                            Text("Output")
                                .font(.caption)
                            Image(systemName: showOutput ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if showOutput {
                        ScrollView {
                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onHover { isHovering = $0 }
    }
    
    private func runCommand() {
        isExecuting = true
        
        Task {
            let result = terminalService.executeSync(command.command, workingDirectory: workingDirectory)
            
            await MainActor.run {
                output = result.output
                exitCode = result.exitCode
                isExecuting = false
                hasExecuted = true
                showOutput = !output.isEmpty
            }
        }
    }
    
    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.command, forType: .string)
    }
}

