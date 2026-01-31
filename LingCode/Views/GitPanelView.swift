//
//  GitPanelView.swift
//  LingCode
//
//  Git panel with commit, push, pull, and branch management
//

import SwiftUI

struct GitPanelView: View {
    @ObservedObject private var gitService = GitService.shared
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var commitMessage: String = ""
    @State private var showBranchPicker: Bool = false
    @State private var showCreateBranch: Bool = false
    @State private var newBranchName: String = ""
    @State private var selectedFiles: Set<String> = []
    @State private var isCommitting: Bool = false
    @State private var isPushing: Bool = false
    @State private var isPulling: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with branch info
            headerView
            
            Divider()
            
            // Changes list
            changesListView
            
            Divider()
            
            // Commit section
            commitSection
            
            Divider()
            
            // Actions bar
            actionsBar
        }
        .onAppear {
            if let url = editorViewModel.rootFolderURL {
                gitService.setRepository(url)
            }
        }
        .alert("Git Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showBranchPicker) {
            branchPickerSheet
        }
        .sheet(isPresented: $showCreateBranch) {
            createBranchSheet
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundColor(.orange)
            
            // Branch button
            Button(action: { showBranchPicker = true }) {
                HStack(spacing: 4) {
                    Text(gitService.currentBranch.isEmpty ? "No branch" : gitService.currentBranch)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Ahead/Behind indicator
            if gitService.aheadBehind.ahead > 0 || gitService.aheadBehind.behind > 0 {
                HStack(spacing: 8) {
                    if gitService.aheadBehind.ahead > 0 {
                        Label("\(gitService.aheadBehind.ahead)", systemImage: "arrow.up")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if gitService.aheadBehind.behind > 0 {
                        Label("\(gitService.aheadBehind.behind)", systemImage: "arrow.down")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Refresh button
            Button(action: { gitService.refreshStatus() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(gitService.isLoading)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Changes List
    
    private var changesListView: some View {
        List {
            if gitService.fileStatuses.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No changes")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                // Staged changes
                let stagedFiles = gitService.fileStatuses.filter { $0.isStaged }
                if !stagedFiles.isEmpty {
                    Section("Staged Changes") {
                        ForEach(stagedFiles) { file in
                            GitFileRow(file: file, onStage: { unstage(file) }, staged: true)
                        }
                    }
                }
                
                // Unstaged changes
                let unstagedFiles = gitService.fileStatuses.filter { !$0.isStaged }
                if !unstagedFiles.isEmpty {
                    Section("Changes") {
                        ForEach(unstagedFiles) { file in
                            GitFileRow(file: file, onStage: { stage(file) }, staged: false)
                        }
                    }
                }
            }
        }
        .listStyle(SidebarListStyle())
    }
    
    // MARK: - Commit Section
    
    private var commitSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Commit Message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                // Stage all button
                if !gitService.fileStatuses.filter({ !$0.isStaged }).isEmpty {
                    Button("Stage All") {
                        stageAll()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            
            TextEditor(text: $commitMessage)
                .font(.system(.body, design: .monospaced))
                .frame(height: 60)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            
            Button(action: commit) {
                HStack {
                    if isCommitting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark.circle")
                    }
                    Text("Commit")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(commitMessage.isEmpty || gitService.fileStatuses.filter({ $0.isStaged }).isEmpty || isCommitting)
        }
        .padding(12)
    }
    
    // MARK: - Actions Bar
    
    private var actionsBar: some View {
        HStack(spacing: 12) {
            // Fetch
            Button(action: fetch) {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            
            // Pull
            Button(action: pull) {
                HStack(spacing: 4) {
                    if isPulling {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.down")
                    }
                    Text("Pull")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isPulling)
            
            // Push
            Button(action: push) {
                HStack(spacing: 4) {
                    if isPushing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.up")
                    }
                    Text("Push")
                    if gitService.aheadBehind.ahead > 0 {
                        Text("(\(gitService.aheadBehind.ahead))")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPushing || gitService.aheadBehind.ahead == 0)
            
            Spacer()
            
            // More actions menu
            Menu {
                Button("New Branch...") { showCreateBranch = true }
                Button("Stash Changes") { stash() }
                Button("Pop Stash") { stashPop() }
                Divider()
                Button("Discard All Changes", role: .destructive) { discardAll() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(BorderlessButtonMenuStyle())
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Branch Picker Sheet
    
    private var branchPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Switch Branch")
                    .font(.headline)
                Spacer()
                Button("Done") { showBranchPicker = false }
            }
            .padding()
            
            Divider()
            
            List {
                Section("Local Branches") {
                    ForEach(gitService.branches.filter { !$0.isRemote }) { branch in
                        Button(action: { checkout(branch.name) }) {
                            HStack {
                                if branch.isCurrent {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                                Text(branch.name)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Section("Remote Branches") {
                    ForEach(gitService.branches.filter { $0.isRemote }) { branch in
                        Button(action: { checkout(branch.name) }) {
                            HStack {
                                Text(branch.name)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
    
    // MARK: - Create Branch Sheet
    
    private var createBranchSheet: some View {
        VStack(spacing: 16) {
            Text("Create New Branch")
                .font(.headline)
            
            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") {
                    newBranchName = ""
                    showCreateBranch = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    createBranch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
    
    // MARK: - Actions
    
    private func stage(_ file: GitFileStatus) {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.stage(files: [file.path], in: url)
        handleResult(result)
    }
    
    private func unstage(_ file: GitFileStatus) {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.unstage(files: [file.path], in: url)
        handleResult(result)
    }
    
    private func stageAll() {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.stageAll(in: url)
        handleResult(result)
    }
    
    private func commit() {
        guard let url = editorViewModel.rootFolderURL else { return }
        isCommitting = true
        
        Task {
            let result = gitService.commit(message: commitMessage, in: url)
            await MainActor.run {
                isCommitting = false
                if result.success {
                    commitMessage = ""
                } else {
                    handleResult(result)
                }
            }
        }
    }
    
    private func push() {
        guard let url = editorViewModel.rootFolderURL else { return }
        isPushing = true
        
        Task {
            let result = gitService.push(in: url)
            await MainActor.run {
                isPushing = false
                handleResult(result)
            }
        }
    }
    
    private func pull() {
        guard let url = editorViewModel.rootFolderURL else { return }
        isPulling = true
        
        Task {
            let result = gitService.pull(in: url)
            await MainActor.run {
                isPulling = false
                handleResult(result)
            }
        }
    }
    
    private func fetch() {
        guard let url = editorViewModel.rootFolderURL else { return }
        _ = gitService.fetch(in: url)
    }
    
    private func checkout(_ branch: String) {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.checkoutBranch(name: branch, in: url)
        handleResult(result)
        showBranchPicker = false
    }
    
    private func createBranch() {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.createBranch(name: newBranchName, in: url)
        handleResult(result)
        if result.success {
            newBranchName = ""
            showCreateBranch = false
        }
    }
    
    private func stash() {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.stash(in: url)
        handleResult(result)
    }
    
    private func stashPop() {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.stashPop(in: url)
        handleResult(result)
    }
    
    private func discardAll() {
        guard let url = editorViewModel.rootFolderURL else { return }
        let result = gitService.discardAllChanges(in: url)
        handleResult(result)
    }
    
    private func handleResult(_ result: GitResult) {
        gitService.refreshStatus()
        if !result.success, let error = result.error {
            errorMessage = error
            showError = true
        }
    }
}

// MARK: - Git File Row

struct GitFileRow: View {
    let file: GitFileStatus
    let onStage: () -> Void
    let staged: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIcon
                .frame(width: 16)
            
            // File path
            Text(file.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Stage/Unstage button
            Button(action: onStage) {
                Image(systemName: staged ? "minus.circle" : "plus.circle")
                    .foregroundColor(staged ? .orange : .green)
            }
            .buttonStyle(PlainButtonStyle())
            .help(staged ? "Unstage" : "Stage")
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch file.status {
        case .modified:
            Image(systemName: "pencil.circle.fill")
                .foregroundColor(.orange)
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.green)
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.red)
        case .untracked:
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.gray)
        case .renamed:
            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(.blue)
        default:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    GitPanelView(editorViewModel: EditorViewModel())
        .frame(width: 350, height: 500)
}
