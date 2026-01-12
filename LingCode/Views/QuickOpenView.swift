//
//  QuickOpenView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import Combine

struct RecentFile: Identifiable {
    let id = UUID()
    let url: URL
    let accessDate: Date
    
    var displayName: String {
        url.lastPathComponent
    }
    
    var relativePath: String {
        url.path
    }
}

class RecentFilesService: ObservableObject {
    static let shared = RecentFilesService()
    
    @Published var recentFiles: [RecentFile] = []
    private let maxRecentFiles = 50
    
    private init() {
        loadRecentFiles()
    }
    
    func addRecentFile(_ url: URL) {
        // Remove if already exists
        recentFiles.removeAll { $0.url == url }
        
        // Add to front
        recentFiles.insert(RecentFile(url: url, accessDate: Date()), at: 0)
        
        // Trim to max
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        
        saveRecentFiles()
    }
    
    private func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: "RecentFiles"),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            recentFiles = paths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    return RecentFile(url: url, accessDate: Date())
                }
                return nil
            }
        }
    }
    
    private func saveRecentFiles() {
        let paths = recentFiles.map { $0.url.path }
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: "RecentFiles")
        }
    }
}

struct QuickOpenView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: EditorViewModel
    @StateObject private var recentService = RecentFilesService.shared
    
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @State private var allFiles: [URL] = []
    @State private var isLoading: Bool = false
    
    var filteredResults: [QuickOpenResult] {
        var results: [QuickOpenResult] = []
        
        // If empty, show recent files
        if searchText.isEmpty {
            results = recentService.recentFiles.prefix(10).map {
                QuickOpenResult(url: $0.url, matchScore: 100, isRecent: true)
            }
        } else {
            // Fuzzy search through all files
            let query = searchText.lowercased()
            
            results = allFiles.compactMap { url in
                let filename = url.lastPathComponent.lowercased()
                let path = url.path.lowercased()
                
                // Simple fuzzy matching
                if filename.contains(query) {
                    let score = filename == query ? 100 : (filename.hasPrefix(query) ? 80 : 50)
                    return QuickOpenResult(url: url, matchScore: score, isRecent: false)
                } else if path.contains(query) {
                    return QuickOpenResult(url: url, matchScore: 30, isRecent: false)
                }
                
                return nil
            }
            .sorted { $0.matchScore > $1.matchScore }
            .prefix(20)
            .map { $0 }
        }
        
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 18))
                    .onSubmit {
                        openSelectedFile()
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Results
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredResults.isEmpty {
                VStack {
                    Text("No files found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, result in
                            QuickOpenResultRow(
                                result: result,
                                isSelected: index == selectedIndex,
                                projectURL: viewModel.rootFolderURL
                            )
                            .id(index)
                            .onTapGesture {
                                openFile(result.url)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            loadAllFiles()
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredResults.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            openSelectedFile()
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
    
    private func loadAllFiles() {
        guard let rootURL = viewModel.rootFolderURL else { return }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var files: [URL] = []
            
            if let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let fileURL as URL in enumerator {
                    if !fileURL.hasDirectoryPath {
                        files.append(fileURL)
                    }
                    if files.count > 5000 {
                        break
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.allFiles = files
                self.isLoading = false
            }
        }
    }
    
    private func openSelectedFile() {
        guard selectedIndex < filteredResults.count else { return }
        let result = filteredResults[selectedIndex]
        openFile(result.url)
    }
    
    private func openFile(_ url: URL) {
        viewModel.openFile(at: url)
        recentService.addRecentFile(url)
        isPresented = false
    }
}

struct QuickOpenResult: Identifiable {
    let id = UUID()
    let url: URL
    let matchScore: Int
    let isRecent: Bool
}

struct QuickOpenResultRow: View {
    let result: QuickOpenResult
    let isSelected: Bool
    let projectURL: URL?
    
    var relativePath: String {
        if let projectURL = projectURL {
            return result.url.path.replacingOccurrences(of: projectURL.path + "/", with: "")
        }
        return result.url.path
    }
    
    var body: some View {
        HStack {
            Image(systemName: iconForFile(result.url))
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(result.url.lastPathComponent)
                        .font(.body)
                    
                    if result.isRecent {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(relativePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts": return "j.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "curlybraces"
        case "md": return "doc.text"
        case "txt": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif": return "photo"
        default: return "doc"
        }
    }
}

