//
//  CommandExecutionView.swift
//  LingCode
//
//  Cursor-style terminal command execution with confirmation
//

import SwiftUI

/// Cursor-style command block that appears in AI responses
struct CommandBlockView: View {
    let command: ParsedCommand
    let workingDirectory: URL?
    let onExecute: () -> Void
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var isHovering = false
    @State private var showConfirmation = false
    @State private var executionOutput = ""
    @State private var isExecuting = false
    @State private var hasExecuted = false
    @State private var exitCode: Int32?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Command header
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Running...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if hasExecuted {
                    if exitCode == 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Success")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                if isHovering && !isExecuting && !hasExecuted {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command.command, forType: .string)
                    }) {
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
            
            // Command content
            HStack(spacing: 0) {
                Text("$ ")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                
                Text(command.command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))
            
            // Description if available
            if let description = command.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            
            // Output section
            if !executionOutput.isEmpty || isExecuting {
                Divider()
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if isExecuting {
                            Button(action: {
                                terminalService.cancel()
                                isExecuting = false
                            }) {
                                Text("Cancel")
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
                        Text(executionOutput.isEmpty ? "Waiting for output..." : executionOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(executionOutput.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(12)
                    .background(Color.black.opacity(0.8))
                }
            }
            
            // Action buttons
            if !hasExecuted && !isExecuting {
                Divider()
                
                HStack(spacing: 12) {
                    if command.isDestructive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Destructive command")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if command.isDestructive {
                            showConfirmation = true
                        } else {
                            executeCommand()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Run")
                        }
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
            }
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
            Text("This command may modify or delete files:\n\n\(command.command)\n\nAre you sure you want to run it?")
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
        executionOutput = ""
        
        terminalService.execute(
            command.command,
            workingDirectory: workingDirectory,
            environment: nil,
            onOutput: { output in
                executionOutput += output
            },
            onError: { error in
                executionOutput += error
            },
            onComplete: { code in
                isExecuting = false
                hasExecuted = true
                exitCode = code
                onExecute()
            }
        )
    }
}

/// Multiple commands detected in AI response
struct CommandsListView: View {
    let commands: [ParsedCommand]
    let workingDirectory: URL?
    let onAllExecuted: () -> Void
    
    @State private var executedCount = 0
    @State private var isRunningAll = false
    @State private var showRunAllConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.accentColor)
                
                Text("\(commands.count) command\(commands.count == 1 ? "" : "s") detected")
                    .font(.headline)
                
                Spacer()
                
                if commands.count > 1 && !isRunningAll {
                    Button(action: {
                        if commands.contains(where: { $0.isDestructive }) {
                            showRunAllConfirmation = true
                        } else {
                            runAllCommands()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Run All")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
            
            // Command list
            ForEach(commands) { command in
                CommandBlockView(
                    command: command,
                    workingDirectory: workingDirectory,
                    onExecute: {
                        executedCount += 1
                        if executedCount == commands.count {
                            onAllExecuted()
                        }
                    }
                )
            }
        }
        .alert("Run All Commands?", isPresented: $showRunAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run All", role: .destructive) {
                runAllCommands()
            }
        } message: {
            Text("Some commands may be destructive. Are you sure you want to run all \(commands.count) commands?")
        }
    }
    
    private func runAllCommands() {
        isRunningAll = true
        // This triggers individual command execution
    }
}

/// Inline command suggestion (appears after AI message)
struct InlineCommandSuggestionView: View {
    let command: String
    let description: String?
    let workingDirectory: URL?
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var isExpanded = false
    @State private var showOutput = false
    @State private var output = ""
    @State private var isExecuting = false
    @State private var hasRun = false
    @State private var exitCode: Int32?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed view
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundColor(.green)
                    
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if hasRun {
                        Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(exitCode == 0 ? .green : .red)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded view
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Full command
                    HStack {
                        Text("$ ")
                            .foregroundColor(.green)
                        Text(command)
                            .textSelection(.enabled)
                    }
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(6)
                    
                    if let desc = description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Output
                    if showOutput || isExecuting {
                        ScrollView {
                            Text(output.isEmpty ? "Running..." : output)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color.black.opacity(0.9))
                        .cornerRadius(6)
                    }
                    
                    // Actions
                    HStack(spacing: 8) {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        if isExecuting {
                            Button(action: {
                                terminalService.cancel()
                                isExecuting = false
                            }) {
                                Label("Cancel", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        } else if !hasRun {
                            Button(action: runCommand) {
                                Label("Run", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(action: runCommand) {
                                Label("Run Again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
    
    private func runCommand() {
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
                hasRun = true
                exitCode = code
            }
        )
    }
}

/// Full-screen terminal execution modal (like Cursor's terminal panel)
struct TerminalExecutionModal: View {
    @Binding var isPresented: Bool
    let commands: [ParsedCommand]
    let workingDirectory: URL?
    
    @ObservedObject private var terminalService = TerminalExecutionService.shared
    @State private var output = ""
    @State private var currentCommandIndex = 0
    @State private var isRunning = false
    @State private var completedCommands: Set<UUID> = []
    @State private var failedCommands: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("Terminal")
                        .font(.headline)
                    Text(workingDirectory?.path ?? "~")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isRunning {
                    Button(action: {
                        terminalService.cancel()
                        isRunning = false
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Commands list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        CommandChip(
                            command: command,
                            index: index,
                            isActive: index == currentCommandIndex && isRunning,
                            isCompleted: completedCommands.contains(command.id),
                            isFailed: failedCommands.contains(command.id)
                        )
                    }
                }
                .padding()
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            // Output
            ScrollView {
                Text(output.isEmpty ? "Ready to run commands..." : output)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.black)
            
            Divider()
            
            // Actions
            HStack {
                Text("\(completedCommands.count)/\(commands.count) completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !isRunning {
                    if completedCommands.count < commands.count {
                        Button(action: runAllCommands) {
                            Label("Run All", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: { isPresented = false }) {
                            Label("Done", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 500)
    }
    
    private func runAllCommands() {
        guard currentCommandIndex < commands.count else { return }
        
        isRunning = true
        runCommand(at: currentCommandIndex)
    }
    
    private func runCommand(at index: Int) {
        guard index < commands.count else {
            isRunning = false
            return
        }
        
        currentCommandIndex = index
        let command = commands[index]
        
        output += "\n$ \(command.command)\n"
        
        terminalService.execute(
            command.command,
            workingDirectory: workingDirectory,
            environment: nil,
            onOutput: { out in
                output += out
            },
            onError: { err in
                output += err
            },
            onComplete: { code in
                if code == 0 {
                    completedCommands.insert(command.id)
                    output += "\n[Exit code: \(code)]\n"
                    // Run next command
                    runCommand(at: index + 1)
                } else {
                    failedCommands.insert(command.id)
                    output += "\n[Failed with exit code: \(code)]\n"
                    isRunning = false
                }
            }
        )
    }
}

struct CommandChip: View {
    let command: ParsedCommand
    let index: Int
    let isActive: Bool
    let isCompleted: Bool
    let isFailed: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            if isActive {
                ProgressView()
                    .scaleEffect(0.6)
            } else if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isFailed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            } else {
                Text("\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            
            Text(command.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var backgroundColor: Color {
        if isActive { return Color.orange.opacity(0.2) }
        if isCompleted { return Color.green.opacity(0.1) }
        if isFailed { return Color.red.opacity(0.1) }
        return Color(NSColor.textBackgroundColor)
    }
    
    private var borderColor: Color {
        if isActive { return .orange }
        if isCompleted { return .green }
        if isFailed { return .red }
        return Color.secondary.opacity(0.3)
    }
}

/// Command run confirmation dialog (Cursor-style)
struct CommandConfirmationView: View {
    let command: ParsedCommand
    let workingDirectory: URL?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if command.isDestructive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                } else {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
                
                VStack(alignment: .leading) {
                    Text(command.isDestructive ? "Run Destructive Command?" : "Run Command?")
                        .font(.headline)
                    
                    if let dir = workingDirectory {
                        Text("in \(dir.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Command preview
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("$ ")
                        .foregroundColor(.green)
                    Text(command.command)
                        .textSelection(.enabled)
                }
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                
                if let description = command.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if command.isDestructive {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text("This command may modify or delete files")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding()
            
            Divider()
            
            // Actions
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Button(action: onConfirm) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(command.isDestructive ? .orange : .accentColor)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 450)
    }
}

