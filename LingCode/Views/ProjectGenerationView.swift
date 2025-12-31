//
//  ProjectGenerationView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

/// View for project generation with templates and progress tracking
struct ProjectGenerationView: View {
    @ObservedObject var viewModel: AIViewModel
    @Binding var isPresented: Bool
    
    @State private var projectName: String = "MyProject"
    @State private var projectDescription: String = ""
    @State private var selectedTemplate: ProjectTemplate?
    @State private var projectLocation: URL?
    @State private var useTemplate: Bool = true
    @State private var showLocationPicker: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Project Name
                    projectNameSection
                    
                    // Location
                    locationSection
                    
                    Divider()
                    
                    // Template or AI Generation Toggle
                    modeToggle
                    
                    if useTemplate {
                        templateSelectionSection
                    } else {
                        aiGenerationSection
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Progress or Actions
            if viewModel.isGeneratingProject {
                progressView
            } else {
                actionButtons
            }
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "plus.app")
                .font(.title)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading) {
                Text("Create New Project")
                    .font(.headline)
                Text("Choose a template or describe your project")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
    
    // MARK: - Project Name
    
    private var projectNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Project Name", systemImage: "folder")
                .font(.headline)
            
            TextField("Enter project name", text: $projectName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    // MARK: - Location
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location", systemImage: "folder.badge.plus")
                .font(.headline)
            
            HStack {
                Text(projectLocation?.path ?? "Select a location...")
                    .foregroundColor(projectLocation == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button("Browse...") {
                    selectLocation()
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
    }
    
    // MARK: - Mode Toggle
    
    private var modeToggle: some View {
        Picker("", selection: $useTemplate) {
            Text("Use Template").tag(true)
            Text("AI Generation").tag(false)
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    
    // MARK: - Template Selection
    
    private var templateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select Template", systemImage: "doc.on.doc")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(viewModel.getProjectTemplates()) { template in
                    templateCard(template)
                }
            }
        }
    }
    
    private func templateCard(_ template: ProjectTemplate) -> some View {
        Button(action: {
            selectedTemplate = template
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundColor(selectedTemplate?.id == template.id ? .white : .accentColor)
                    
                    Spacer()
                    
                    if selectedTemplate?.id == template.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                    }
                }
                
                Text(template.name)
                    .font(.headline)
                    .foregroundColor(selectedTemplate?.id == template.id ? .white : .primary)
                
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(selectedTemplate?.id == template.id ? .white.opacity(0.8) : .secondary)
                    .lineLimit(2)
                
                Text("\(template.files.count) files")
                    .font(.caption2)
                    .foregroundColor(selectedTemplate?.id == template.id ? .white.opacity(0.6) : .secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedTemplate?.id == template.id ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - AI Generation
    
    private var aiGenerationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Project Description", systemImage: "text.bubble")
                .font(.headline)
            
            Text("Describe the project you want to create. Be specific about features, technologies, and requirements.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextEditor(text: $projectDescription)
                .font(.body)
                .frame(height: 200)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            
            // Example prompts
            VStack(alignment: .leading, spacing: 8) {
                Text("Examples:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(examplePrompts, id: \.self) { prompt in
                    Button(action: {
                        projectDescription = prompt
                    }) {
                        Text(prompt)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var examplePrompts: [String] {
        [
            "A React todo app with local storage",
            "A Python CLI tool for file organization",
            "A Swift command-line calculator",
            "A Node.js REST API with Express",
            "A Rust command-line utility"
        ]
    }
    
    // MARK: - Progress
    
    private var progressView: some View {
        VStack(spacing: 12) {
            if let progress = viewModel.generationProgress {
                ProgressView(value: progress.percentage / 100)
                    .progressViewStyle(LinearProgressViewStyle())
                
                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let currentFile = progress.currentFile {
                    Text("Creating: \(currentFile)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating project...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button(action: createProject) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Project")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreate)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var canCreate: Bool {
        guard !projectName.isEmpty, projectLocation != nil else { return false }
        
        if useTemplate {
            return selectedTemplate != nil
        } else {
            return !projectDescription.isEmpty
        }
    }
    
    private func selectLocation() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Location"
        
        if panel.runModal() == .OK {
            projectLocation = panel.url
        }
    }
    
    private func createProject() {
        guard let location = projectLocation else { return }
        
        if useTemplate, let template = selectedTemplate {
            viewModel.createProjectFromTemplate(template, name: projectName, at: location)
        } else {
            // AI generation
            viewModel.generateProject(description: projectDescription, projectURL: location.appendingPathComponent(projectName))
        }
    }
}

// MARK: - Project Progress Overlay (Cursor-style)

struct ProjectProgressOverlay: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var expandedFiles: Set<String> = []
    
    var body: some View {
        if viewModel.isGeneratingProject {
            VStack(spacing: 0) {
                // Header
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generating Project")
                            .font(.headline)
                        
                        if let progress = viewModel.generationProgress {
                            Text(progress.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.cancelGeneration() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                // Progress bar
                if let progress = viewModel.generationProgress {
                    VStack(spacing: 4) {
                        ProgressView(value: progress.percentage / 100)
                            .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        
                        HStack {
                            Text("\(Int(progress.percentage))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if progress.totalFiles > 0 {
                                Text("\(progress.completedFiles)/\(progress.totalFiles) files")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                Divider()
                
                // Step-by-step file changes
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Planning step
                        if let plan = viewModel.currentPlan {
                            StepSection(
                                number: 1,
                                title: "Planning",
                                icon: "list.bullet.rectangle",
                                color: .blue,
                                isComplete: true
                            ) {
                                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                            .frame(width: 14)
                                        Text(step)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        
                        // Files step
                        if !viewModel.currentActions.isEmpty {
                            StepSection(
                                number: 2,
                                title: "Creating Files",
                                icon: "doc.badge.plus",
                                color: .orange,
                                isComplete: !viewModel.isLoading
                            ) {
                                ForEach(viewModel.currentActions) { action in
                                    ProgressFileRow(
                                        action: action,
                                        isExpanded: expandedFiles.contains(action.id.uuidString),
                                        onToggle: {
                                            if expandedFiles.contains(action.id.uuidString) {
                                                expandedFiles.remove(action.id.uuidString)
                                            } else {
                                                expandedFiles.insert(action.id.uuidString)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 400)
            }
            .frame(width: 500)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 20)
            )
        }
    }
}

// MARK: - Step Section

struct StepSection<Content: View>: View {
    let number: Int
    let title: String
    let icon: String
    let color: Color
    let isComplete: Bool
    @ViewBuilder let content: () -> Content
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 10) {
                    // Step badge
                    ZStack {
                        Circle()
                            .fill(isComplete ? color : color.opacity(0.3))
                            .frame(width: 24, height: 24)
                        
                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        } else {
                            Text("\(number)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                    }
                    
                    Image(systemName: icon)
                        .foregroundColor(color)
                    
                    Text(title)
                        .font(.subheadline.bold())
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 8)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(.leading, 34)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Progress File Row

struct ProgressFileRow: View {
    let action: AIAction
    let isExpanded: Bool
    let onToggle: () -> Void
    
    private var fileName: String {
        action.name.replacingOccurrences(of: "Create ", with: "")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    // Status
                    statusIcon
                        .frame(width: 16)
                    
                    // File icon
                    Image(systemName: fileIcon)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    // Name
                    Text(fileName)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Badge
                    statusBadge
                    
                    // Chevron
                    if action.result != nil {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(backgroundColor)
            .cornerRadius(6)
            
            // Expanded content preview
            if isExpanded, let content = action.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(content.components(separatedBy: .newlines).prefix(20).enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                Text("+ ")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.green)
                                
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.08))
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 150)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch action.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundColor(.gray)
                .font(.caption)
        case .executing:
            ProgressView()
                .scaleEffect(0.5)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch action.status {
        case .pending:
            Text("PENDING")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.secondary)
                .cornerRadius(3)
        case .executing:
            Text("WRITING")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(3)
        case .completed:
            Text("DONE")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(3)
        case .failed:
            Text("FAILED")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(3)
        }
    }
    
    private var backgroundColor: Color {
        switch action.status {
        case .executing: return Color.blue.opacity(0.05)
        case .completed: return Color.green.opacity(0.03)
        case .failed: return Color.red.opacity(0.05)
        default: return Color.clear
        }
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
}

// MARK: - Quick Project Button

struct QuickProjectButton: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var showProjectSheet = false
    
    var body: some View {
        Button(action: {
            showProjectSheet = true
        }) {
            HStack {
                Image(systemName: "plus.app")
                Text("New Project")
            }
        }
        .sheet(isPresented: $showProjectSheet) {
            ProjectGenerationView(viewModel: viewModel, isPresented: $showProjectSheet)
        }
    }
}

// MARK: - Created Files List

struct CreatedFilesListView: View {
    let files: [URL]
    let onSelect: (URL) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Files Created")
                    .font(.headline)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(files, id: \.self) { file in
                        Button(action: {
                            onSelect(file)
                        }) {
                            HStack {
                                Image(systemName: iconForFile(file))
                                    .foregroundColor(.accentColor)
                                
                                VStack(alignment: .leading) {
                                    Text(file.lastPathComponent)
                                        .font(.body)
                                    Text(file.deletingLastPathComponent().lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding()
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces.square"
        case "py": return "terminal"
        case "rs": return "gear"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "html": return "chevron.left.slash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        case "md": return "text.justify"
        case "yaml", "yml": return "list.bullet"
        default: return "doc.fill"
        }
    }
}

