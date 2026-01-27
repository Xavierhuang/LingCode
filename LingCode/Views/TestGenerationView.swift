//
//  TestGenerationView.swift
//  LingCode
//
//  UI for generating tests for files
//

import SwiftUI

struct TestGenerationView: View {
    let files: [StreamingFileInfo]
    let projectURL: URL?
    @StateObject private var testService = TestGenerationService.shared
    @State private var selectedFiles: Set<String> = []
    @State private var testType: GeneratedTest.TestType = .unit
    @State private var generatedTests: [GeneratedTest] = []
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("Generate Tests")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Button("Close") {
                    onDismiss()
                }
            }
            .padding(DesignSystem.Spacing.md)
            
            Divider()
            
            if testService.isGenerating {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Generating tests...")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !generatedTests.isEmpty {
                // Show generated tests
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        ForEach(generatedTests) { test in
                            GeneratedTestCard(test: test, projectURL: projectURL)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            } else {
                // File selection
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    // Test type picker
                    Picker("Test Type", selection: $testType) {
                        Text("Unit Tests").tag(GeneratedTest.TestType.unit)
                        Text("Integration Tests").tag(GeneratedTest.TestType.integration)
                        Text("E2E Tests").tag(GeneratedTest.TestType.e2e)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.md)
                    
                    Divider()
                    
                    // File list
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            ForEach(files) { file in
                                FileSelectionRow(
                                    file: file,
                                    isSelected: selectedFiles.contains(file.id),
                                    onToggle: {
                                        if selectedFiles.contains(file.id) {
                                            selectedFiles.remove(file.id)
                                        } else {
                                            selectedFiles.insert(file.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                    }
                    
                    Divider()
                    
                    // Generate button
                    HStack {
                        Spacer()
                        Button("Generate Tests") {
                            generateTests()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFiles.isEmpty || testService.isGenerating)
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private func generateTests() {
        let filesToTest = files.filter { selectedFiles.contains($0.id) }
        
        for file in filesToTest {
            let language = detectLanguage(from: file.path)
            testService.generateTests(
                for: file.content,
                filePath: file.path,
                language: language,
                testType: testType
            ) { result in
                switch result {
                case .success(let test):
                    generatedTests.append(test)
                case .failure:
                    break
                }
            }
        }
    }
    
    private func detectLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "java": return "java"
        case "go": return "go"
        case "rs": return "rust"
        default: return "code"
        }
    }
}

struct FileSelectionRow: View {
    let file: StreamingFileInfo
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                Text(file.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
                Text(file.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isSelected ? Color.green.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GeneratedTestCard: View {
    let test: GeneratedTest
    let projectURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(test.filePath)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(test.testType == .unit ? "Unit" : (test.testType == .integration ? "Integration" : "E2E"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color.blue.opacity(0.1))
                    )
            }
            
            // Coverage info
            HStack(spacing: DesignSystem.Spacing.md) {
                if !test.coverage.functions.isEmpty {
                    Label("\(test.coverage.functions.count) functions", systemImage: "function")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if !test.coverage.classes.isEmpty {
                    Label("\(test.coverage.classes.count) classes", systemImage: "square.stack")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Label("\(test.coverage.lines) lines", systemImage: "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Test code preview
            ScrollView {
                Text(test.testContent)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .frame(maxHeight: 200)
            
            // Save button
            Button("Save Test File") {
                saveTestFile(test)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
    
    private func saveTestFile(_ test: GeneratedTest) {
        guard let projectURL = projectURL else { return }
        
        // Determine test file path based on language
        let testFileName = "\(test.filePath.components(separatedBy: "/").last ?? "test")_test"
        let testFilePath = projectURL.appendingPathComponent(testFileName)
        
        do {
            try test.testContent.write(to: testFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save test file: \(error)")
        }
    }
}
