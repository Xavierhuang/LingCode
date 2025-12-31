//
//  SearchView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var searchText: String = ""
    @State private var replaceText: String = ""
    @State private var useRegex: Bool = false
    @State private var caseSensitive: Bool = false
    @State private var wholeWords: Bool = false
    @State private var searchResults: [SearchResult] = []
    @State private var selectedResultIndex: Int = 0
    @Binding var isPresented: Bool
    @FocusState private var searchFieldFocused: Bool
    
    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Find & Replace")
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
                Text("\(searchResults.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !searchResults.isEmpty {
                    Button(action: {
                        navigateToPrevious()
                    }) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(selectedResultIndex == 0)
                    
                    Button(action: {
                        navigateToNext()
                    }) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(selectedResultIndex >= searchResults.count - 1)
                }
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Find", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFieldFocused)
                        .onSubmit {
                            performSearch()
                        }
                    
                    Button(action: {
                        performSearch()
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(searchText.isEmpty)
                }
                
                HStack {
                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: {
                        performReplace()
                    }) {
                        Text("Replace")
                    }
                    .disabled(searchText.isEmpty || replaceText.isEmpty)
                }
                
                HStack {
                    Toggle("Regex", isOn: $useRegex)
                    Toggle("Case Sensitive", isOn: $caseSensitive)
                    Toggle("Whole Words", isOn: $wholeWords)
                }
            }
            .padding(.horizontal)
            
            if !searchResults.isEmpty {
                Divider()
                
                List(selection: $selectedResultIndex) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                        SearchResultRow(result: result, isSelected: index == selectedResultIndex) {
                            navigateToResult(result)
                        }
                        .tag(index)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 450, height: 600)
        .onAppear {
            searchFieldFocused = true
        }
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty {
                performSearch()
            } else {
                searchResults = []
            }
        }
    }
    
    private func navigateToPrevious() {
        if selectedResultIndex > 0 {
            selectedResultIndex -= 1
            navigateToResult(searchResults[selectedResultIndex])
        }
    }
    
    private func navigateToNext() {
        if selectedResultIndex < searchResults.count - 1 {
            selectedResultIndex += 1
            navigateToResult(searchResults[selectedResultIndex])
        }
    }
    
    private func performSearch() {
        guard let document = viewModel.editorState.activeDocument else { return }
        guard !searchText.isEmpty else { return }
        
        searchResults = []
        let content = document.content
        let lines = content.components(separatedBy: .newlines)
        
        var options: String.CompareOptions = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        
        for (lineIndex, line) in lines.enumerated() {
            if useRegex {
                if let regex = try? NSRegularExpression(pattern: searchText, options: caseSensitive ? [] : [.caseInsensitive]) {
                    let range = NSRange(location: 0, length: line.utf16.count)
                    let matches = regex.matches(in: line, options: [], range: range)
                    
                    for match in matches {
                        let matchRange = Range(match.range, in: line)!
                        let matchedText = String(line[matchRange])
                        let column = line.distance(from: line.startIndex, to: matchRange.lowerBound)
                        
                        searchResults.append(SearchResult(
                            line: lineIndex + 1,
                            column: column,
                            text: matchedText,
                            fullLine: line
                        ))
                    }
                }
            } else {
                var searchRange = line.startIndex..<line.endIndex
                while let range = line.range(of: searchText, options: options, range: searchRange) {
                    let column = line.distance(from: line.startIndex, to: range.lowerBound)
                    searchResults.append(SearchResult(
                        line: lineIndex + 1,
                        column: column,
                        text: searchText,
                        fullLine: line
                    ))
                    
                    searchRange = range.upperBound..<line.endIndex
                }
            }
        }
    }
    
    private func performReplace() {
        guard let document = viewModel.editorState.activeDocument else { return }
        guard !searchText.isEmpty else { return }
        
        var content = document.content
        
        if useRegex {
            if let regex = try? NSRegularExpression(pattern: searchText, options: caseSensitive ? [] : [.caseInsensitive]) {
                let range = NSRange(location: 0, length: content.utf16.count)
                content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: replaceText)
            }
        } else {
            var options: String.CompareOptions = []
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            content = content.replacingOccurrences(of: searchText, with: replaceText, options: options)
        }
        
        document.content = content
        document.isModified = true
        viewModel.updateDocumentContent(content)
        
        performSearch()
    }
    
    private func navigateToResult(_ result: SearchResult) {
        // TODO: Navigate to line/column in editor
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let line: Int
    let column: Int
    let text: String
    let fullLine: String
}

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Line \(result.line), Column \(result.column)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.fullLine)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

