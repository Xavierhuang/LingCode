//
//  TerminalCommandBlock.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct TerminalCommandBlock: View {
    let command: String
    let language: String?
    let workingDirectory: URL?
    let onCopy: () -> Void
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var isHovering = false
    @State private var isExecuting = false
    @State private var hasExecuted = false
    @State private var output = ""
    @State private var exitCode: Int32?
    @State private var showOutput = false
    @State private var showConfirmation = false
    
    private var isDestructive: Bool {
        let destructive = ["rm ", "rm\t", "rmdir", "delete", "remove", "drop ", "truncate", "format", "> /", ">> /", "sudo rm", "git reset --hard", "git clean"]
        return destructive.contains { command.lowercased().contains($0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Text(language ?? "Terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Status indicator
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Running...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if hasExecuted {
                    Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(exitCode == 0 ? .green : .red)
                    Text(exitCode == 0 ? "Success" : "Failed")
                        .font(.caption)
                        .foregroundColor(exitCode == 0 ? .green : .red)
                }
                
                // Copy button
                if isHovering {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Copy command")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Command
            HStack(spacing: 0) {
                Text("$ ")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                
                Spacer()
            }
            .padding(12)
            .background(Color.black.opacity(0.85))
            
            // Output section
            if showOutput && (!output.isEmpty || isExecuting) {
                Divider()
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if isExecuting {
                            Button(action: cancelExecution) {
                                Label("Cancel", systemImage: "stop.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    ScrollView {
                        Text(output.isEmpty ? "Waiting for output..." : output)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(output.isEmpty ? .gray : .white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(12)
                    .background(Color.black.opacity(0.9))
                }
            }
            
            // Action bar
            HStack(spacing: 12) {
                if isDestructive {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Destructive")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
                
                Spacer()
                
                if hasExecuted && !isExecuting {
                    Button(action: {
                        hasExecuted = false
                        output = ""
                        exitCode = nil
                        showOutput = false
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if isExecuting {
                    Button(action: cancelExecution) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                } else if !hasExecuted {
                    Button(action: {
                        if isDestructive {
                            showConfirmation = true
                        } else {
                            executeCommand()
                        }
                    }) {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .alert("Run Destructive Command?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run Anyway", role: .destructive) {
                executeCommand()
            }
        } message: {
            Text("This command may modify or delete files:\n\n$ \(command)\n\nAre you sure you want to run it?")
        }
    }
    
    private var borderColor: Color {
        if isExecuting { return .orange }
        if hasExecuted {
            return exitCode == 0 ? .green : .red
        }
        return Color.secondary.opacity(0.3)
    }
    
    private func executeCommand() {
        isExecuting = true
        showOutput = true
        output = ""
        
        terminalService.execute(
            command,
            workingDirectory: workingDirectory,
            environment: nil,
            onOutput: { out in
                output += out
            },
            onError: { err in
                output += err
            },
            onComplete: { code in
                isExecuting = false
                hasExecuted = true
                exitCode = code
            }
        )
    }
    
    private func cancelExecution() {
        terminalService.cancel()
        isExecuting = false
        output += "\n[Cancelled by user]"
    }
}



