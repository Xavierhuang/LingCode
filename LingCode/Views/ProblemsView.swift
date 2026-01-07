//
//  ProblemsView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import Combine

enum ProblemSeverity: String {
    case error = "Error"
    case warning = "Warning"
    case info = "Info"
    case hint = "Hint"
    
    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .hint: return .purple
        }
    }
}

struct Problem: Identifiable {
    let id = UUID()
    let severity: ProblemSeverity
    let message: String
    let file: String
    let line: Int
    let column: Int
    let source: String?
}

class ProblemsService: ObservableObject {
    static let shared = ProblemsService()
    
    @Published var problems: [Problem] = []
    
    private init() {}
    
    func analyzeFile(_ content: String, filename: String, language: String?) -> [Problem] {
        var detectedProblems: [Problem] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Common code issues
            
            // TODO/FIXME comments
            if trimmed.contains("// TODO:") || trimmed.contains("# TODO:") {
                detectedProblems.append(Problem(
                    severity: .info,
                    message: "TODO comment found",
                    file: filename,
                    line: index + 1,
                    column: 0,
                    source: "LingCode"
                ))
            }
            
            if trimmed.contains("// FIXME:") || trimmed.contains("# FIXME:") {
                detectedProblems.append(Problem(
                    severity: .warning,
                    message: "FIXME comment found",
                    file: filename,
                    line: index + 1,
                    column: 0,
                    source: "LingCode"
                ))
            }
            
            // Console/print statements (potential debug code)
            if language == "javascript" || language == "typescript" {
                if trimmed.hasPrefix("console.log(") {
                    detectedProblems.append(Problem(
                        severity: .hint,
                        message: "Debug console.log found - consider removing before production",
                        file: filename,
                        line: index + 1,
                        column: 0,
                        source: "LingCode"
                    ))
                }
            }
            
            if language == "python" {
                if trimmed.hasPrefix("print(") && !trimmed.contains("file=") {
                    detectedProblems.append(Problem(
                        severity: .hint,
                        message: "Debug print statement found",
                        file: filename,
                        line: index + 1,
                        column: 0,
                        source: "LingCode"
                    ))
                }
            }
            
            // Very long lines
            if line.count > 120 {
                detectedProblems.append(Problem(
                    severity: .hint,
                    message: "Line exceeds 120 characters (\(line.count))",
                    file: filename,
                    line: index + 1,
                    column: 120,
                    source: "LingCode"
                ))
            }
            
            // Trailing whitespace
            if line != trimmed && !line.isEmpty && line.hasSuffix(" ") || line.hasSuffix("\t") {
                detectedProblems.append(Problem(
                    severity: .hint,
                    message: "Trailing whitespace",
                    file: filename,
                    line: index + 1,
                    column: line.count,
                    source: "LingCode"
                ))
            }
        }
        
        return detectedProblems
    }
    
    func updateProblems(for file: String, content: String, language: String?) {
        // Remove old problems for this file
        problems.removeAll { $0.file == file }
        
        // Add new problems
        let newProblems = analyzeFile(content, filename: file, language: language)
        problems.append(contentsOf: newProblems)
    }
    
    func clearProblems(for file: String) {
        problems.removeAll { $0.file == file }
    }
}

struct ProblemsView: View {
    @ObservedObject private var service = ProblemsService.shared
    @ObservedObject var viewModel: EditorViewModel
    @State private var selectedSeverity: ProblemSeverity?
    
    var filteredProblems: [Problem] {
        if let severity = selectedSeverity {
            return service.problems.filter { $0.severity == severity }
        }
        return service.problems
    }
    
    var problemCounts: [ProblemSeverity: Int] {
        var counts: [ProblemSeverity: Int] = [:]
        for problem in service.problems {
            counts[problem.severity, default: 0] += 1
        }
        return counts
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Problems")
                    .font(.headline)
                
                Spacer()
                
                // Filter buttons
                ForEach([ProblemSeverity.error, .warning, .info], id: \.self) { severity in
                    Button(action: {
                        selectedSeverity = selectedSeverity == severity ? nil : severity
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: severity.icon)
                                .foregroundColor(severity.color)
                            Text("\(problemCounts[severity] ?? 0)")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(selectedSeverity == severity ? severity.color.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if filteredProblems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("No problems detected")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredProblems) { problem in
                        ProblemRowView(problem: problem) {
                            goToProblem(problem)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func goToProblem(_ problem: Problem) {
        guard let rootURL = viewModel.rootFolderURL else { return }
        let fileURL = rootURL.appendingPathComponent(problem.file)
        viewModel.openFile(at: fileURL)
        
        // Navigate to line
        NotificationCenter.default.post(
            name: NSNotification.Name("GoToLine"),
            object: nil,
            userInfo: ["line": problem.line]
        )
    }
}

struct ProblemRowView: View {
    let problem: Problem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: problem.severity.icon)
                    .foregroundColor(problem.severity.color)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.message)
                        .font(.body)
                        .lineLimit(2)
                    
                    HStack {
                        Text(problem.file)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("[\(problem.line):\(problem.column)]")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let source = problem.source {
                            Text(source)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

