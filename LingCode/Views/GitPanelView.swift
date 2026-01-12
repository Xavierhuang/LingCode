//
//  GitPanelView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct GitPanelView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var commitMessage: String = ""
    @State private var selectedFiles: Set<String> = []
    @State private var isCommitting: Bool = false
    @State private var isPushing: Bool = false
    @State private var isPulling: Bool = false
    @State private var statusMessage: String?
    @State private var branches: [String] = []
    @State private var currentBranch: String = ""
    @State private var showBranchPicker: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                Text("Source Control")
                    .font(.headline)
                Spacer()
                
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Branch selector
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.secondary)
                
                Button(action: { showBranchPicker.toggle() }) {
                    HStack {
                        Text(currentBranch.isEmpty ? "No branch" : currentBranch)
                            .font(.system(.body, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showBranchPicker) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(branches, id: \.self) { branch in
                            Button(action: {
                                checkoutBranch(branch)
                                showBranchPicker = false
                            }) {
                                HStack {
                                    if branch == currentBranch {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(branch)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .frame(minWidth: 200)
                    .padding(.vertical, 8)
                }
                
                Spacer()
                
                // Pull/Push buttons
                HStack(spacing: 8) {
                    Button(action: pull) {
                        if isPulling {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Pull")
                    .disabled(isPulling)
                    
                    Button(action: push) {
                        if isPushing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.up.circle")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Push")
                    .disabled(isPushing)
                }
            }
            .padding()
            
            Divider()
            
            // Changed files
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let status = getGitStatus()
                    
                    if status.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                            Text("No changes")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(status, id: \.path) { file in
                            GitFileRowView(
                                file: file,
                                isSelected: selectedFiles.contains(file.path),
                                onToggle: {
                                    if selectedFiles.contains(file.path) {
                                        selectedFiles.remove(file.path)
                                    } else {
                                        selectedFiles.insert(file.path)
                                    }
                                },
                                onOpen: {
                                    openFile(file.path)
                                }
                            )
                        }
                    }
                }
            }
            
            Divider()
            
            // Commit section
            VStack(spacing: 8) {
                TextField("Commit message", text: $commitMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
                
                HStack {
                    Button(action: selectAll) {
                        Text("Select All")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: commit) {
                        if isCommitting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Commit \(selectedFiles.isEmpty ? "" : "(\(selectedFiles.count))")")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(commitMessage.isEmpty || selectedFiles.isEmpty || isCommitting)
                }
            }
            .padding()
            
            // Status message
            if let message = statusMessage {
                HStack {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 300)
        .onAppear {
            refresh()
        }
    }
    
    private func getGitStatus() -> [GitFileStatus] {
        guard let rootURL = viewModel.rootFolderURL else { return [] }
        return GitService.shared.getStatus(for: rootURL)
    }
    
    private func refresh() {
        loadBranches()
        loadCurrentBranch()
    }
    
    private func loadBranches() {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--list"]
        process.currentDirectoryURL = rootURL
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                branches = output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }
                    .filter { !$0.isEmpty }
            }
        } catch {}
    }
    
    private func loadCurrentBranch() {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--show-current"]
        process.currentDirectoryURL = rootURL
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                currentBranch = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
    }
    
    private func checkoutBranch(_ branch: String) {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["checkout", branch]
        process.currentDirectoryURL = rootURL
        
        do {
            try process.run()
            process.waitUntilExit()
            currentBranch = branch
            statusMessage = "Switched to branch '\(branch)'"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    private func commit() {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        isCommitting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Stage selected files
            for file in selectedFiles {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["add", file]
                process.currentDirectoryURL = rootURL
                try? process.run()
                process.waitUntilExit()
            }
            
            // Commit
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["commit", "-m", commitMessage]
            process.currentDirectoryURL = rootURL
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    isCommitting = false
                    if process.terminationStatus == 0 {
                        statusMessage = "Committed successfully"
                        commitMessage = ""
                        selectedFiles.removeAll()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                        statusMessage = "Error: \(output)"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isCommitting = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func push() {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        isPushing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["push"]
            process.currentDirectoryURL = rootURL
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    isPushing = false
                    statusMessage = process.terminationStatus == 0 ? "Pushed successfully" : "Push failed"
                }
            } catch {
                DispatchQueue.main.async {
                    isPushing = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func pull() {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        isPulling = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["pull"]
            process.currentDirectoryURL = rootURL
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    isPulling = false
                    statusMessage = process.terminationStatus == 0 ? "Pulled successfully" : "Pull failed"
                }
            } catch {
                DispatchQueue.main.async {
                    isPulling = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func selectAll() {
        let status = getGitStatus()
        selectedFiles = Set(status.map { $0.path })
    }
    
    private func openFile(_ path: String) {
        guard let rootURL = viewModel.rootFolderURL else { return }
        let fileURL = rootURL.appendingPathComponent(path)
        viewModel.openFile(at: fileURL)
    }
}

struct GitFileRowView: View {
    let file: GitFileStatus
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            statusIcon
                .frame(width: 16)
            
            Button(action: onOpen) {
                Text(file.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch file.status {
        case .modified:
            Text("M")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
        case .added:
            Text("A")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.green)
        case .deleted:
            Text("D")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.red)
        case .untracked:
            Text("U")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
        case .clean:
            Text("")
        }
    }
}

