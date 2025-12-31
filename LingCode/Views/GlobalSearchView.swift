//
//  GlobalSearchView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct GlobalSearchView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    @State private var searchText: String = ""
    @State private var useRegex: Bool = false
    @State private var caseSensitive: Bool = false
    @State private var useSemanticSearch: Bool = false
    @State private var searchResults: [GlobalSearchResult] = []
    @State private var semanticResults: [SemanticSearchResult] = []
    @State private var isSearching: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Search in Files")
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            HStack {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit {
                        performSearch()
                    }
                
                Button(action: {
                    performSearch()
                }) {
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(searchText.isEmpty || isSearching)
                
                Toggle("Regex", isOn: $useRegex)
                Toggle("Case Sensitive", isOn: $caseSensitive)
                Toggle("Semantic", isOn: $useSemanticSearch)
                    .help("Use AI to understand search intent and find relevant code")
            }
            .padding(.horizontal)
            
            Divider()
            
            if !searchResults.isEmpty || !semanticResults.isEmpty {
                HStack {
                    if useSemanticSearch {
                        Text("\(semanticResults.count) semantic results")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(searchResults.count) results in \(Set(searchResults.map { $0.filePath }).count) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if useSemanticSearch {
                        // Show semantic results grouped by file
                        ForEach(groupedSemanticResults.keys.sorted(), id: \.self) { filePath in
                            if let results = groupedSemanticResults[filePath] {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Image(systemName: "doc")
                                        Text(filePath)
                                            .font(.headline)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    
                                    ForEach(results) { result in
                                        SemanticSearchResultRow(result: result) {
                                            openFile(at: result.filePath, line: result.line)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // Show regular text search results
                        ForEach(groupedResults.keys.sorted(), id: \.self) { filePath in
                            if let results = groupedResults[filePath] {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Image(systemName: "doc")
                                        Text(filePath)
                                            .font(.headline)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    
                                    ForEach(results) { result in
                                        GlobalSearchResultRow(result: result) {
                                            openFile(at: result.filePath, line: result.line)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            isFocused = true
        }
        .onChange(of: searchText) { oldValue, newValue in
            if newValue.isEmpty {
                searchResults = []
                semanticResults = []
            }
        }
    }
    
    private var groupedResults: [String: [GlobalSearchResult]] {
        Dictionary(grouping: searchResults) { $0.filePath }
    }
    
    private var groupedSemanticResults: [String: [SemanticSearchResult]] {
        Dictionary(grouping: semanticResults) { $0.filePath }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty,
              let rootURL = viewModel.rootFolderURL else { return }
        
        isSearching = true
        searchResults = []
        semanticResults = []
        
        if useSemanticSearch {
            Task {
                let results = await SemanticSearchService.shared.search(
                    query: searchText,
                    in: rootURL
                )
                await MainActor.run {
                    self.semanticResults = results
                    self.isSearching = false
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let results = searchInDirectory(rootURL, searchText: searchText, useRegex: useRegex, caseSensitive: caseSensitive)
                
                DispatchQueue.main.async {
                    self.searchResults = results
                    self.isSearching = false
                }
            }
        }
    }
    
    private func searchInDirectory(_ url: URL, searchText: String, useRegex: Bool, caseSensitive: Bool) -> [GlobalSearchResult] {
        var results: [GlobalSearchResult] = []
        
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [URLResourceKey.isRegularFileKey],
            options: options
        ) else {
            return results
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [URLResourceKey.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            // Skip binary files and large files
            if let content = try? String(contentsOf: fileURL, encoding: .utf8),
               content.count < 1_000_000 {
                let fileResults = searchInFile(content, filePath: fileURL.path, searchText: searchText, useRegex: useRegex, caseSensitive: caseSensitive)
                results.append(contentsOf: fileResults)
            }
        }
        
        return results
    }
    
    private func searchInFile(_ content: String, filePath: String, searchText: String, useRegex: Bool, caseSensitive: Bool) -> [GlobalSearchResult] {
        var results: [GlobalSearchResult] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (lineIndex, line) in lines.enumerated() {
            var found = false
            
            if useRegex {
                let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
                if let regex = try? NSRegularExpression(pattern: searchText, options: options) {
                    let range = NSRange(location: 0, length: line.utf16.count)
                    found = regex.firstMatch(in: line, options: [], range: range) != nil
                }
            } else {
                let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
                found = line.range(of: searchText, options: options) != nil
            }
            
            if found {
                results.append(GlobalSearchResult(
                    filePath: filePath,
                    line: lineIndex + 1,
                    column: 1,
                    text: line,
                    matchText: searchText
                ))
            }
        }
        
        return results
    }
    
    private func openFile(at path: String, line: Int) {
        let url = URL(fileURLWithPath: path)
        viewModel.openFile(at: url)
        // TODO: Navigate to specific line
    }
}

struct GlobalSearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let line: Int
    let column: Int
    let text: String
    let matchText: String
}

struct GlobalSearchResultRow: View {
    let result: GlobalSearchResult
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(result.line)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
                
                Text(result.text)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SemanticSearchResultRow: View {
    let result: SemanticSearchResult
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(result.line)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.text)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                        
                        if let explanation = result.explanation {
                            Text(explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", result.relevanceScore))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

