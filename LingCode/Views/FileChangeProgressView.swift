//
//  FileChangeProgressView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

/// Cursor-style file change progress view with step-by-step updates
struct FileChangeProgressView: View {
    @ObservedObject var viewModel: AIViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var expandedFiles: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            progressHeader
            
            Divider()
            
            // Step-by-step content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Planning step
                        if let plan = viewModel.currentPlan {
                            StepCard(
                                stepNumber: 1,
                                title: "Planning",
                                icon: "list.bullet.rectangle",
                                iconColor: .blue,
                                isComplete: true
                            ) {
                                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text(step)
                                            .font(.callout)
                                    }
                                }
                            }
                        }
                        
                        // File changes step
                        if !viewModel.currentActions.isEmpty || !viewModel.createdFiles.isEmpty {
                            StepCard(
                                stepNumber: 2,
                                title: "Creating Files",
                                icon: "doc.badge.plus",
                                iconColor: .orange,
                                isComplete: !viewModel.isLoading
                            ) {
                                VStack(spacing: 8) {
                                    ForEach(viewModel.currentActions) { action in
                                        ProgressFileChangeCard(
                                            action: action,
                                            isExpanded: expandedFiles.contains(action.id.uuidString),
                                            fileContent: getFileContent(for: action),
                                            onToggle: {
                                                if expandedFiles.contains(action.id.uuidString) {
                                                    expandedFiles.remove(action.id.uuidString)
                                                } else {
                                                    expandedFiles.insert(action.id.uuidString)
                                                }
                                            },
                                            onOpen: {
                                                openFile(for: action)
                                            }
                                        )
                                        .id(action.id)
                                    }
                                }
                            }
                        }
                        
                        // Completion step
                        if !viewModel.createdFiles.isEmpty && !viewModel.isLoading {
                            StepCard(
                                stepNumber: 3,
                                title: "Complete",
                                icon: "checkmark.seal.fill",
                                iconColor: .green,
                                isComplete: true
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(viewModel.createdFiles.count) file\(viewModel.createdFiles.count == 1 ? "" : "s") created successfully")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 8) {
                                        Button(action: openAllFiles) {
                                            Label("Open All", systemImage: "arrow.up.right.square")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        
                                        Button(action: revealInFinder) {
                                            Label("Reveal in Finder", systemImage: "folder")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.currentActions.count) { _, _ in
                    if let lastAction = viewModel.currentActions.last {
                        withAnimation {
                            proxy.scrollTo(lastAction.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(progressTitle)
                        .font(.headline)
                } else if !viewModel.createdFiles.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Changes Applied")
                        .font(.headline)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text("AI Assistant")
                        .font(.headline)
                }
                
                Spacer()
                
                if viewModel.isLoading {
                    Button(action: { viewModel.cancelGeneration() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Progress bar
            if viewModel.isLoading && !viewModel.currentActions.isEmpty {
                VStack(spacing: 4) {
                    ProgressView(value: progressValue)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text(progressDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var progressTitle: String {
        if viewModel.currentPlan != nil && viewModel.currentActions.isEmpty {
            return "Planning..."
        } else if !viewModel.currentActions.isEmpty {
            let completed = viewModel.currentActions.filter { $0.status == .completed }.count
            return "Creating files (\(completed)/\(viewModel.currentActions.count))"
        }
        return "Processing..."
    }
    
    private var progressValue: Double {
        guard !viewModel.currentActions.isEmpty else { return 0 }
        let completed = Double(viewModel.currentActions.filter { $0.status == .completed }.count)
        return completed / Double(viewModel.currentActions.count)
    }
    
    private var progressDetail: String {
        if let executing = viewModel.currentActions.first(where: { $0.status == .executing }) {
            return "Writing \(executing.name.replacingOccurrences(of: "Create ", with: ""))..."
        }
        return ""
    }
    
    private func getFileContent(for action: AIAction) -> String? {
        // Get file content from the created files
        let fileName = action.name.replacingOccurrences(of: "Create ", with: "")
        if let file = viewModel.createdFiles.first(where: { $0.lastPathComponent == fileName }) {
            return try? String(contentsOf: file, encoding: .utf8)
        }
        return action.result
    }
    
    private func openFile(for action: AIAction) {
        let fileName = action.name.replacingOccurrences(of: "Create ", with: "")
        if let file = viewModel.createdFiles.first(where: { $0.lastPathComponent == fileName }) {
            editorViewModel.openFile(at: file)
        }
    }
    
    private func openAllFiles() {
        for file in viewModel.createdFiles {
            editorViewModel.openFile(at: file)
        }
    }
    
    private func revealInFinder() {
        if let firstFile = viewModel.createdFiles.first {
            NSWorkspace.shared.activateFileViewerSelecting([firstFile])
        }
    }
}

// MARK: - Step Card

struct StepCard<Content: View>: View {
    let stepNumber: Int
    let title: String
    let icon: String
    let iconColor: Color
    let isComplete: Bool
    @ViewBuilder let content: () -> Content
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 12) {
                    // Step number badge
                    ZStack {
                        Circle()
                            .fill(isComplete ? iconColor : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        } else {
                            Text("\(stepNumber)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                    }
                    
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                    
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(iconColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - File Change Card

struct ProgressFileChangeCard: View {
    let action: AIAction
    let isExpanded: Bool
    let fileContent: String?
    let onToggle: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    // Status icon
                    statusIcon
                        .frame(width: 20)
                    
                    // File icon
                    Image(systemName: fileIcon)
                        .foregroundColor(.accentColor)
                    
                    // File name
                    Text(fileName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status badge
                    statusBadge
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(backgroundColor)
            
            // File content preview
            if isExpanded, let content = fileContent {
                VStack(alignment: .leading, spacing: 0) {
                    // Language header
                    HStack {
                        Text(fileLanguage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if action.status == .completed {
                            Button(action: onOpen) {
                                Label("Open", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    // Code preview with line numbers
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            let lines = content.components(separatedBy: .newlines)
                            ForEach(Array(lines.prefix(50).enumerated()), id: \.offset) { index, line in
                                HStack(alignment: .top, spacing: 0) {
                                    // Line number
                                    Text("\(index + 1)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 36, alignment: .trailing)
                                        .padding(.trailing, 12)
                                    
                                    // Line content with + indicator for new file
                                    HStack(spacing: 4) {
                                        Text("+")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.green)
                                        
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.1))
                            }
                            
                            if lines.count > 50 {
                                Text("... \(lines.count - 50) more lines")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 300)
                    .background(Color(NSColor.textBackgroundColor))
                }
                .cornerRadius(6)
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var fileName: String {
        action.name.replacingOccurrences(of: "Create ", with: "")
    }
    
    private var fileIcon: String {
        let name = fileName.lowercased()
        if name.hasSuffix(".swift") { return "swift" }
        if name.hasSuffix(".js") || name.hasSuffix(".jsx") { return "curlybraces" }
        if name.hasSuffix(".ts") || name.hasSuffix(".tsx") { return "curlybraces.square" }
        if name.hasSuffix(".py") { return "terminal" }
        if name.hasSuffix(".html") { return "chevron.left.slash.chevron.right" }
        if name.hasSuffix(".css") { return "paintbrush" }
        if name.hasSuffix(".json") { return "doc.text" }
        if name.hasSuffix(".md") { return "text.justify" }
        return "doc.fill"
    }
    
    private var fileLanguage: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift"
        case "js", "jsx": return "JavaScript"
        case "ts", "tsx": return "TypeScript"
        case "py": return "Python"
        case "html": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "md": return "Markdown"
        default: return ext.uppercased()
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch action.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundColor(.gray)
        case .executing:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch action.status {
        case .pending:
            Text("PENDING")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.secondary)
                .cornerRadius(4)
        case .executing:
            Text("WRITING")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)
        case .completed:
            Text("CREATED")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(4)
        case .failed:
            Text("FAILED")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(4)
        }
    }
    
    private var backgroundColor: Color {
        switch action.status {
        case .executing: return Color.blue.opacity(0.05)
        case .completed: return Color.green.opacity(0.05)
        case .failed: return Color.red.opacity(0.05)
        default: return Color.clear
        }
    }
    
    private var borderColor: Color {
        switch action.status {
        case .executing: return Color.blue.opacity(0.3)
        case .completed: return Color.green.opacity(0.3)
        case .failed: return Color.red.opacity(0.3)
        default: return Color.secondary.opacity(0.2)
        }
    }
}

// MARK: - Preview

#Preview {
    FileChangeProgressView(
        viewModel: AIViewModel(),
        editorViewModel: EditorViewModel()
    )
    .frame(width: 400, height: 600)
}

