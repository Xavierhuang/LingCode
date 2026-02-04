//
//  SubagentPanelView.swift
//  LingCode
//
//  Multi-agent panel for delegating tasks to specialized subagents
//

import SwiftUI

struct SubagentPanelView: View {
    @ObservedObject private var subagentService = SubagentService.shared
    @ObservedObject var editorViewModel: EditorViewModel
    
    @State private var selectedAgentType: SubagentType = .coder
    @State private var taskDescription: String = ""
    @State private var showTaskBreakdown: Bool = false
    @State private var showHistory: Bool = false
    @State private var expandedTaskId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Quick Actions
            quickActionsSection
            
            Divider()
            
            // Active Tasks
            activeTasksSection
            
            if showHistory && !subagentService.completedTasks.isEmpty {
                Divider()
                completedTasksSection
            }
            
            Divider()
            
            // Create Task
            createTaskSection
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .foregroundColor(.purple)
            
            Text("Subagents")
                .fontWeight(.medium)
            
            Spacer()
            
            // Active count badge
            if !subagentService.activeTasks.isEmpty {
                Text("\(subagentService.activeTasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            // History toggle
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(showHistory ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Show completed tasks")
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                quickActionButton(
                    title: "Review Code",
                    icon: "eye",
                    color: .orange
                ) {
                    delegateReview()
                }
                
                quickActionButton(
                    title: "Write Tests",
                    icon: "checkmark.shield",
                    color: .green
                ) {
                    delegateTesting()
                }
                
                quickActionButton(
                    title: "Add Docs",
                    icon: "doc.text",
                    color: .blue
                ) {
                    delegateDocumentation()
                }
                
                quickActionButton(
                    title: "Refactor",
                    icon: "arrow.triangle.2.circlepath",
                    color: .purple
                ) {
                    delegateRefactoring()
                }
            }
            
            // Full task breakdown button
            Button(action: { showTaskBreakdown = true }) {
                HStack {
                    Image(systemName: "rectangle.stack")
                    Text("Create Task Breakdown")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showTaskBreakdown) {
                TaskBreakdownSheet(
                    projectURL: editorViewModel.rootFolderURL,
                    onDismiss: { showTaskBreakdown = false }
                )
            }
        }
        .padding(12)
    }
    
    private func quickActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(editorViewModel.editorState.activeDocument == nil)
    }
    
    // MARK: - Active Tasks
    
    private var activeTasksSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Active Tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if subagentService.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                
                Spacer()
                
                if !subagentService.activeTasks.isEmpty {
                    Button("Cancel All") {
                        for task in subagentService.activeTasks {
                            subagentService.cancelTask(task.id)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }
            
            if subagentService.activeTasks.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No active tasks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(subagentService.activeTasks) { task in
                    taskRow(task, isActive: true)
                }
            }
        }
        .padding(12)
    }
    
    // MARK: - Completed Tasks
    
    private var completedTasksSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(subagentService.completedTasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(subagentService.completedTasks.prefix(10)) { task in
                        taskRow(task, isActive: false)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .padding(12)
    }
    
    private func taskRow(_ task: SubagentTask, isActive: Bool) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation {
                    if expandedTaskId == task.id {
                        expandedTaskId = nil
                    } else {
                        expandedTaskId = task.id
                    }
                }
            }) {
                HStack(spacing: 8) {
                    // Agent type icon
                    Image(systemName: task.type.icon)
                        .foregroundColor(statusColor(task.status))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.type.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text(task.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    statusBadge(task.status)
                    
                    // Expand/collapse
                    Image(systemName: expandedTaskId == task.id ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content
            if expandedTaskId == task.id {
                expandedTaskContent(task, isActive: isActive)
            }
        }
    }
    
    private func expandedTaskContent(_ task: SubagentTask, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full description
            Text(task.description)
                .font(.caption)
                .padding(.horizontal, 8)
            
            // Result output if available
            if let result = task.result {
                if !result.output.isEmpty {
                    ScrollView {
                        Text(result.output)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 100)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                }
                
                // Changes
                if !result.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        ForEach(result.changes, id: \.file) { change in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .font(.caption2)
                                Text(change.file.lastPathComponent)
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                // Errors
                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.errors, id: \.self) { error in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                            }
                            .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            
            // Actions
            HStack {
                if isActive && task.status == .running {
                    Button("Cancel") {
                        subagentService.cancelTask(task.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if let completedAt = task.completedAt {
                    Text(completedAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
    
    private func statusColor(_ status: SubagentTaskStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
    
    @ViewBuilder
    private func statusBadge(_ status: SubagentTaskStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .running:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .foregroundColor(.orange)
        }
    }
    
    // MARK: - Create Task Section
    
    private var createTaskSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Create Task")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // Agent type picker
            HStack(spacing: 4) {
                ForEach(SubagentType.allCases, id: \.self) { type in
                    Button(action: { selectedAgentType = type }) {
                        Image(systemName: type.icon)
                            .font(.caption)
                            .frame(width: 28, height: 28)
                            .background(selectedAgentType == type ? Color.blue : Color.clear)
                            .foregroundColor(selectedAgentType == type ? .white : .secondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(type.displayName)
                }
            }
            
            // Task description
            HStack(spacing: 8) {
                TextField("Describe the task...", text: $taskDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                
                Button(action: createCustomTask) {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskDescription.isEmpty)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func delegateReview() {
        guard let doc = editorViewModel.editorState.activeDocument else { return }
        _ = subagentService.delegateReview(
            files: [doc.filePath].compactMap { $0 },
            projectURL: editorViewModel.rootFolderURL
        )
    }
    
    private func delegateTesting() {
        guard let doc = editorViewModel.editorState.activeDocument else { return }
        _ = subagentService.delegateTesting(
            files: [doc.filePath].compactMap { $0 },
            projectURL: editorViewModel.rootFolderURL
        )
    }
    
    private func delegateDocumentation() {
        guard let doc = editorViewModel.editorState.activeDocument else { return }
        _ = subagentService.delegateDocumentation(
            files: [doc.filePath].compactMap { $0 },
            projectURL: editorViewModel.rootFolderURL
        )
    }
    
    private func delegateRefactoring() {
        guard let doc = editorViewModel.editorState.activeDocument else { return }
        _ = subagentService.createTask(
            type: .refactorer,
            description: "Refactor and improve the code structure",
            context: SubagentContext(
                projectURL: editorViewModel.rootFolderURL,
                files: [doc.filePath].compactMap { $0 },
                selectedText: nil,
                additionalContext: nil
            )
        )
    }
    
    private func createCustomTask() {
        guard !taskDescription.isEmpty else { return }
        
        var files: [URL] = []
        if let filePath = editorViewModel.editorState.activeDocument?.filePath {
            files.append(filePath)
        }
        
        let selectedText = editorViewModel.editorState.selectedText.isEmpty ? nil : editorViewModel.editorState.selectedText
        
        _ = subagentService.createTask(
            type: selectedAgentType,
            description: taskDescription,
            context: SubagentContext(
                projectURL: editorViewModel.rootFolderURL,
                files: files,
                selectedText: selectedText,
                additionalContext: nil
            )
        )
        
        taskDescription = ""
    }
}

// MARK: - Task Breakdown Sheet

struct TaskBreakdownSheet: View {
    let projectURL: URL?
    let onDismiss: () -> Void
    
    @State private var mainTask: String = ""
    @State private var createdTasks: [SubagentTask] = []
    @State private var isCreating: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Task Breakdown")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onDismiss() }
            }
            .padding()
            
            Divider()
            
            // Main content
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe the main task:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $mainTask)
                        .font(.body)
                        .frame(height: 80)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                }
                
                // Breakdown preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("This will create 5 subagent tasks:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 4) {
                        breakdownRow(number: 1, type: .researcher, description: "Research the codebase")
                        breakdownRow(number: 2, type: .architect, description: "Design the approach")
                        breakdownRow(number: 3, type: .coder, description: "Implement the solution")
                        breakdownRow(number: 4, type: .tester, description: "Write tests")
                        breakdownRow(number: 5, type: .reviewer, description: "Review the implementation")
                    }
                }
                
                // Created tasks
                if !createdTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Tasks created!")
                                .fontWeight(.medium)
                        }
                        
                        Text("The tasks are now running in parallel (up to 3 at a time).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            Spacer()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                if createdTasks.isEmpty {
                    Button("Create Tasks") {
                        createBreakdown()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mainTask.isEmpty || isCreating)
                } else {
                    Button("Done") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 450, height: 450)
    }
    
    private func breakdownRow(number: Int, type: SubagentType, description: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            
            Image(systemName: type.icon)
                .foregroundColor(.secondary)
            
            Text(type.displayName)
                .font(.caption)
                .fontWeight(.medium)
            
            Text("- \(description)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func createBreakdown() {
        guard !mainTask.isEmpty else { return }
        isCreating = true
        
        createdTasks = SubagentService.shared.createTaskBreakdown(
            mainTask: mainTask,
            projectURL: projectURL
        )
        
        isCreating = false
    }
}

#Preview {
    SubagentPanelView(editorViewModel: EditorViewModel())
        .frame(width: 350, height: 600)
}
