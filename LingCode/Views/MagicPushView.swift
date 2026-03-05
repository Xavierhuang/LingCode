//
//  MagicPushView.swift
//  LingCode
//
//  One-tap "stage → AI commit message → commit → push" popover.
//
//  UX states:
//    .input    — remote/branch picker (with "Add remote" flow if none), commit message, Push button
//    .progress — step tracker + live terminal output
//    .success  — branch + hash confirmation, auto-dismiss after 4 s
//    .failure  — terminal showing exactly what went wrong
//
//  Fixed frame: 380 × 370 pt.
//

import SwiftUI

// MARK: - Popover state

private enum PushPopoverState: Equatable {
    case input
    case progress
    case needsRemote               // triggered by git after push fails with no remote
    case success(branch: String, hash: String)
    case failure(message: String)
}

// MARK: - Main view

struct MagicPushView: View {
    @ObservedObject private var pushService = MagicPushService.shared

    let projectURL: URL
    var onDismiss: (() -> Void)?

    @State private var customMessage: String = ""
    @State private var stepMessage: String = ""
    @State private var popoverState: PushPopoverState = .input
    @FocusState private var fieldFocused: Bool
    @FocusState private var remoteURLFocused: Bool

    // Remote / branch
    @State private var remotes: [String] = []
    @State private var localBranches: [String] = []
    @State private var selectedRemote: String = "origin"
    @State private var selectedBranch: String = ""

    // Shown only when git says "no remote configured" after attempting push
    @State private var remoteURLInput: String = ""
    @State private var remoteNameInput: String = "origin"
    // For "Add remote..." in the picker menu
    @State private var showAddRemoteInline: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(width: 380, height: 370)

            VStack(spacing: 0) {
                header
                Divider()
                ZStack {
                    if popoverState == .input {
                        inputPane
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .leading)),
                                removal:   .opacity.combined(with: .move(edge: .leading))
                            ))
                    }
                    if case .progress = popoverState {
                        progressPane
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal:   .opacity.combined(with: .move(edge: .trailing))
                            ))
                    }
                    if popoverState == .needsRemote {
                        needsRemotePane
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal:   .opacity.combined(with: .move(edge: .bottom))
                            ))
                    }
                    if case .success(let branch, let hash) = popoverState {
                        successPane(branch: branch, hash: hash)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                removal:   .opacity
                            ))
                    }
                    if case .failure = popoverState {
                        failurePane
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal:   .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(width: 380, height: 370)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadRepoInfoInBackground() }
        .onChange(of: pushService.state) { handleStateChange($0) }
    }

    // MARK: - Background git load (no main-thread blocking)

    private func loadRepoInfoInBackground() {
        fieldFocused = true
        // Only fetch the minimum needed to populate the pickers.
        // getStatus and getAheadBehind are intentionally omitted — they are
        // slow (especially getAheadBehind which contacts the remote) and not
        // needed to initiate a push.
        Task.detached(priority: .utility) {
            // Step 1: set repo URL (just checks .git exists — fast)
            await MainActor.run { GitService.shared.setRepositoryURL(projectURL) }

            // Step 2: current branch (one git process, typically <100ms)
            let result = GitService.shared.runGitPublic(
                ["rev-parse", "--abbrev-ref", "HEAD"],
                in: projectURL
            )
            let current = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Step 3: local branches (one git process)
            let branchResult = GitService.shared.runGitPublic(["branch"], in: projectURL)
            let localBranchList: [String] = branchResult.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }
                .filter { !$0.isEmpty }

            // Step 4: remotes (one git process)
            let remotesResult = GitService.shared.runGitPublic(["remote"], in: projectURL)
            let fetchedRemotes = remotesResult.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let branchList = localBranchList.isEmpty ? ["main"] : localBranchList.sorted()

            await MainActor.run {
                remotes = fetchedRemotes
                localBranches = branchList
                selectedRemote = fetchedRemotes.first ?? "origin"
                selectedBranch = branchList.contains(current) ? current : (branchList.first ?? "main")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(headerIconColor)
                .animation(.easeInOut(duration: 0.2), value: popoverState)

            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if case .progress = popoverState {
                Button("Cancel") {
                    pushService.reset()
                    withAnimation(.easeInOut(duration: 0.22)) { popoverState = .input }
                }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }

            if case .failure = popoverState {
                Button("Try again") {
                    pushService.reset()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        popoverState = .input
                        stepMessage = ""
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Input pane

    private var inputPane: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {

                // Remote + Branch pickers (only shown if remotes are known)
                if !remotes.isEmpty {
                    pickerRow
                }

                // Commit message
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    TextField("Commit message (leave empty to use 'Update files')", text: $customMessage)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))
                        .focused($fieldFocused)
                        .onSubmit { startPush() }
                    if !customMessage.isEmpty {
                        Button { customMessage = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            fieldFocused ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor),
                            lineWidth: 1
                        )
                )

                // Push button
                Button(action: startPush) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Magic Push")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Needs remote pane (shown after git push fails with no remote)

    private var needsRemotePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mirror the git terminal error message
            PushTerminalView(logs: pushService.gitLog)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("No remote configured — where do you want to push?")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)

                // Remote URL field
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    TextField("https://github.com/user/repo.git  or  git@github.com:user/repo.git", text: $remoteURLInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                        .focused($remoteURLFocused)
                        .onSubmit { retryWithRemote() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            remoteURLFocused ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 14)
                .onAppear { remoteURLFocused = true }

                // Auth format hints
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use SSH (recommended — no password):")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("git@github.com:Xavierhuang/repo.git")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                    Text("Or HTTPS with a Personal Access Token:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .padding(.top, 2)
                    Text("https://<token>@github.com/Xavierhuang/repo.git")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                    Button("Get a GitHub token →") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=LingCode")!)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)

                Button(action: retryWithRemote) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add Remote & Push")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(NSColor.controlColor) : Color.accentColor)
                    .foregroundColor(remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .secondary : .white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Remote/branch pickers

    private var pickerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Remote").font(.system(size: 10)).foregroundColor(.secondary)
                Menu {
                    ForEach(remotes, id: \.self) { name in
                        Button(name) { selectedRemote = name }
                    }
                    Divider()
                    Button("Add remote...") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            popoverState = .needsRemote
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud").font(.system(size: 11))
                        Text(selectedRemote).font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Branch").font(.system(size: 10)).foregroundColor(.secondary)
                Menu {
                    ForEach(localBranches, id: \.self) { name in
                        Button(name) { selectedBranch = name }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                        Text(selectedBranch.isEmpty ? (localBranches.first ?? "main") : selectedBranch)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }

    // MARK: - Progress pane

    private var progressPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            pushStepper
                .padding(.horizontal, 14)
                .padding(.top, 14)

            Divider().padding(.top, 10)

            HStack(spacing: 7) {
                if pushService.state.isInProgress {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                }
                Text(stepMessage.isEmpty ? pushService.state.displayText : stepMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.15), value: stepMessage)

                if !pushService.generatedMessage.isEmpty {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 9)).foregroundColor(.accentColor)
                        Text("\"\(pushService.generatedMessage)\"")
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Live terminal
            PushTerminalView(logs: pushService.gitLog)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Push step dots

    private var pushStepper: some View {
        HStack(spacing: 0) {
            ForEach(PushPipelineStep.allCases) { step in
                HStack(spacing: 0) {
                    PushStepDot(step: step, currentState: pushService.state)
                    if step != PushPipelineStep.allCases.last {
                        Rectangle()
                            .frame(maxWidth: .infinity, maxHeight: 1)
                            .foregroundColor(
                                step.isCompleted(for: pushService.state)
                                    ? Color.accentColor.opacity(0.5)
                                    : Color(NSColor.separatorColor)
                            )
                            .animation(.easeInOut(duration: 0.25), value: pushService.state)
                    }
                }
            }
        }
    }

    // MARK: - Success pane

    private func successPane(branch: String, hash: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 56, height: 56)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            VStack(spacing: 4) {
                Text("Pushed successfully").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundColor(.secondary)
                    Text(branch).font(.system(size: 11, weight: .medium))
                    if !hash.isEmpty {
                        Text("·").foregroundColor(.secondary)
                        Text(hash).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
                if !pushService.generatedMessage.isEmpty {
                    Text("\"\(pushService.generatedMessage)\"")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.tail).padding(.top, 2)
                }
            }
            HStack(spacing: 12) {
                Button("Done") { onDismiss?() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                PushCountdownLabel(seconds: 4) { onDismiss?() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Failure pane

    private var failurePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(.red)
                Text("Push failed — see output below")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            PushTerminalView(logs: pushService.gitLog)
                .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Start push

    private func startPush() {
        withAnimation(.easeInOut(duration: 0.22)) {
            popoverState = .progress
            stepMessage = "Starting..."
        }

        let msg    = customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = selectedRemote.isEmpty ? "origin" : selectedRemote
        let branch = selectedBranch.isEmpty ? (localBranches.first ?? "main") : selectedBranch

        Task { @MainActor in
            await pushService.push(
                in: projectURL,
                customMessage: msg.isEmpty ? nil : msg,
                remote: remote,
                branch: branch
            ) { step in
                withAnimation(.easeInOut(duration: 0.15)) { self.stepMessage = step }
            }
        }
    }

    private func retryWithRemote() {
        let url = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        let branch = selectedBranch.isEmpty ? (localBranches.first ?? "main") : selectedBranch

        withAnimation(.easeInOut(duration: 0.22)) {
            popoverState = .progress
            stepMessage = "Configuring remote..."
        }

        Task { @MainActor in
            await pushService.addRemoteAndPush(
                remoteURL: url,
                remoteName: remoteNameInput.isEmpty ? "origin" : remoteNameInput,
                projectURL: projectURL,
                branch: branch
            ) { step in
                withAnimation(.easeInOut(duration: 0.15)) { self.stepMessage = step }
            }
        }
    }

    // MARK: - State observer

    private func handleStateChange(_ newState: MagicPushState) {
        switch newState {
        case .needsRemote:
            withAnimation(.easeInOut(duration: 0.22)) {
                popoverState = .needsRemote
            }
        case .success(let branch, let hash):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                popoverState = .success(branch: branch, hash: hash)
            }
        case .failed(let msg):
            if case .progress = popoverState {
                withAnimation(.easeInOut(duration: 0.22)) {
                    popoverState = .failure(message: msg)
                }
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    private var headerIcon: String {
        switch popoverState {
        case .input:       return "arrow.up.circle"
        case .progress:    return "arrow.up.circle"
        case .needsRemote: return "link.badge.plus"
        case .success:     return "checkmark.circle.fill"
        case .failure:     return "xmark.circle.fill"
        }
    }
    private var headerIconColor: Color {
        switch popoverState {
        case .input, .progress: return .accentColor
        case .needsRemote:      return .orange
        case .success:          return .accentColor
        case .failure:          return .red
        }
    }
    private var headerTitle: String {
        switch popoverState {
        case .input:       return "Magic Push"
        case .progress:    return "Pushing..."
        case .needsRemote: return "Where to push?"
        case .success:     return "Pushed"
        case .failure:     return "Push Failed"
        }
    }
}

// MARK: - Terminal view (push-specific, same styling as DeployTerminalView)

private struct PushTerminalView: View {
    let logs: String
    @State private var copied = false

    private struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        var color: Color {
            let l = text.lowercased()
            if l.contains("[error]") || l.contains("error:") || l.contains("fatal") {
                return Color(red: 1.0, green: 0.4, blue: 0.4)
            }
            if l.contains("✓") || l.contains("success") || l.contains("pushed") {
                return Color(red: 0.4, green: 0.9, blue: 0.5)
            }
            if l.contains("warn") { return Color(red: 1.0, green: 0.8, blue: 0.3) }
            if l.contains("[push]") { return Color(red: 0.4, green: 0.75, blue: 1.0) }
            return Color(red: 0.78, green: 0.78, blue: 0.78)
        }
    }

    private var lines: [LogLine] {
        logs.components(separatedBy: .newlines).filter { !$0.isEmpty }.map { LogLine(text: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1.0, green: 0.73, blue: 0.22)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.25, green: 0.78, blue: 0.36)).frame(width: 8, height: 8)
                Text("git output").font(.system(size: 10, weight: .medium)).foregroundColor(Color(white: 0.5))
                Spacer()
                Text("\(lines.count) lines").font(.system(size: 9)).foregroundColor(Color(white: 0.4))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 9))
                        Text(copied ? "Copied" : "Copy").font(.system(size: 9))
                    }
                    .foregroundColor(copied ? .green : Color(white: 0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(red: 0.18, green: 0.18, blue: 0.18))

            Divider().background(Color(white: 0.25))

            if logs.isEmpty {
                HStack {
                    Text("Waiting for output...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.12, blue: 0.12))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(line.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .onChange(of: logs) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25), lineWidth: 0.5))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120)
    }
}

// MARK: - Pipeline step dot

private struct PushStepDot: View {
    let step: PushPipelineStep
    let currentState: MagicPushState
    private enum DotState { case pending, active, done }
    private var dotState: DotState {
        if step.isCompleted(for: currentState) { return .done }
        if step.isActive(for: currentState)    { return .active }
        return .pending
    }
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .strokeBorder(ringColor, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(fillColor))
                    .animation(.easeInOut(duration: 0.2), value: dotState)
                switch dotState {
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                case .active:
                    ProgressView().scaleEffect(0.45).frame(width: 11, height: 11).transition(.opacity)
                case .pending:
                    EmptyView()
                }
            }
            Text(step.label)
                .font(.system(size: 9))
                .foregroundColor(dotState == .pending
                    ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.labelColor))
                .lineLimit(1)
        }
        .frame(minWidth: 48)
    }
    private var fillColor: Color {
        switch dotState {
        case .done:    return Color.accentColor
        case .active:  return Color.accentColor.opacity(0.12)
        case .pending: return Color.clear
        }
    }
    private var ringColor: Color {
        switch dotState {
        case .done, .active: return Color.accentColor
        case .pending:       return Color(NSColor.separatorColor)
        }
    }
}

// MARK: - Pipeline steps model

private enum PushPipelineStep: String, CaseIterable, Identifiable {
    case run  = "Run"
    case done = "Done"

    var id: String { rawValue }
    var label: String { rawValue }

    func isActive(for state: MagicPushState) -> Bool {
        switch (self, state) {
        case (.run, .running): return true
        default: return false
        }
    }

    func isCompleted(for state: MagicPushState) -> Bool {
        switch state {
        case .idle, .running:  return false
        case .needsRemote:     return self == .run
        case .success, .failed: return true
        }
    }
}

// MARK: - Countdown label

private struct PushCountdownLabel: View {
    let seconds: Int
    let onComplete: () -> Void
    @State private var remaining: Int
    init(seconds: Int, onComplete: @escaping () -> Void) {
        self.seconds = seconds; self.onComplete = onComplete
        self._remaining = State(initialValue: seconds)
    }
    var body: some View {
        Text("Closes in \(remaining)s")
            .font(.system(size: 10))
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
            .onAppear { tick() }
    }
    private func tick() {
        guard remaining > 0 else { onComplete(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if remaining > 1 { remaining -= 1; tick() } else { remaining = 0; onComplete() }
        }
    }
}

// MARK: - Trigger button

struct MagicPushButton: View {
    let projectURL: URL
    @State private var isPresented = false
    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 10, weight: .semibold))
                Text("Push").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Color(NSColor.labelColor).opacity(0.75))
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            MagicPushView(projectURL: projectURL) { isPresented = false }
        }
        .help("Magic Push — stage, AI commit message, and push in one tap")
    }
}
