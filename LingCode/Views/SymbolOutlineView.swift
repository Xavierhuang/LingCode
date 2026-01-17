//
//  SymbolOutlineView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//  Updated for Phase 6: AST-Based Intelligent Outline
//

import SwiftUI

// MARK: - UI Models

struct Symbol: Identifiable {
    let id = UUID()
    let name: String
    let kind: SymbolKind
    let line: Int
    let children: [Symbol]
    
    // Mapped strictly to SF Symbols
    enum SymbolKind: String {
        case file = "doc"
        case module = "shippingbox"
        case namespace = "folder"
        case package = "archivebox"
        case classSymbol = "c.square"
        case method = "m.square"
        case property = "p.square"
        case field = "number"
        case constructor = "hammer"
        case enumSymbol = "e.square"
        case interface = "i.square"
        case function = "f.square"
        case variable = "v.square"
        case constant = "k.square"
        case string = "text.quote"
        case number = "number.square"
        case boolean = "checkmark.square"
        case array = "square.stack"
        case object = "cube"
        case key = "key"
        case null = "circle.slash"
        case enumMember = "list.number"
        case structSymbol = "s.square"
        case event = "bolt"
        case `operator` = "plus.forwardslash.minus"
        case typeParameter = "t.square"
        case `extension` = "puzzlepiece"
    }
}

// MARK: - Outline View

struct SymbolOutlineView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var symbols: [Symbol] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    
    var filteredSymbols: [Symbol] {
        if searchText.isEmpty {
            return symbols
        }
        // Simple recursive search could be added here,
        // currently filters top-level only or flat list if you flatten it.
        // For outline, usually filtering the visible nodes is enough.
        return symbols.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("Outline")
                    .font(.headline)
                Spacer()
                Button(action: {
                    refreshSymbols()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Search
            TextField("Filter symbols...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Content
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Indexing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if symbols.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No symbols found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredSymbols) { symbol in
                        SymbolRow(symbol: symbol, onSelect: goToSymbol)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 250)
        .onAppear {
            refreshSymbols()
        }
        // React to file switching
        .onChange(of: viewModel.editorState.activeDocumentId) { oldValue, newValue in
            refreshSymbols()
        }
        // React to save events (optional, if you have a publisher for it)
    }
    
    private func refreshSymbols() {
        guard let document = viewModel.editorState.activeDocument,
              let fileURL = document.filePath else {
            symbols = []
            return
        }
        
        isLoading = true
        
        // Use production-grade AST indexing
        Task {
            // This runs on background thread via ASTIndex actor/queue
            let astSymbols = await ASTIndex.shared.getSymbolsAsync(for: fileURL)
            
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    symbols = buildSymbolHierarchy(from: astSymbols)
                    isLoading = false
                }
            }
        }
    }
    
    /// Convert ASTSymbols to UI Symbols with hierarchy
    private func buildSymbolHierarchy(from astSymbols: [ASTSymbol]) -> [Symbol] {
        // Map parent_name -> [Children]
        var symbolMap: [String: [ASTSymbol]] = [:]
        var rootSymbols: [ASTSymbol] = []
        
        for astSymbol in astSymbols {
            if let parent = astSymbol.parent, !parent.isEmpty {
                if symbolMap[parent] == nil {
                    symbolMap[parent] = []
                }
                symbolMap[parent]?.append(astSymbol)
            } else {
                rootSymbols.append(astSymbol)
            }
        }
        
        // Recursive converter
        func convertASTSymbol(_ astSymbol: ASTSymbol) -> Symbol {
            // Potential Limitation: Parent lookup by name can collision if nested types share names.
            // Acceptable for V1.
            let children = symbolMap[astSymbol.name]?.map { convertASTSymbol($0) } ?? []
            
            return Symbol(
                name: astSymbol.name,
                kind: mapASTKindToSymbolKind(astSymbol.kind),
                line: astSymbol.range.lowerBound + 1, // Convert 0-based to 1-based line index
                children: children.sorted { $0.line < $1.line }
            )
        }
        
        // Return sorted roots
        return rootSymbols
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { convertASTSymbol($0) }
    }
    
    private func mapASTKindToSymbolKind(_ kind: ASTSymbol.Kind) -> Symbol.SymbolKind {
        switch kind {
        case .classSymbol: return .classSymbol
        case .structSymbol: return .structSymbol
        case .enumSymbol: return .enumSymbol
        case .protocolSymbol: return .interface
        case .function: return .function
        case .method: return .method
        case .variable: return .variable
        case .property: return .property
        case .extension: return .extension
        case .import: return .module
        }
    }
    
    private func goToSymbol(_ symbol: Symbol) {
        // Dispatch event to EditorView
        NotificationCenter.default.post(
            name: NSNotification.Name("GoToLine"),
            object: nil,
            userInfo: ["line": symbol.line]
        )
    }
}

// MARK: - Symbol Row

struct SymbolRow: View {
    let symbol: Symbol
    let onSelect: (Symbol) -> Void
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Expand/Collapse Chevron
                if !symbol.children.isEmpty {
                    Button(action: {
                        withAnimation(.snappy) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Spacer().frame(width: 12)
                }
                
                // Clickable Row Content
                Button(action: { onSelect(symbol) }) {
                    HStack(spacing: 6) {
                        Image(systemName: symbol.kind.rawValue)
                            .foregroundColor(colorForKind(symbol.kind))
                            .font(.system(size: 11))
                        
                        Text(symbol.name)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 2)
            
            // Recursive Children
            if isExpanded && !symbol.children.isEmpty {
                ForEach(symbol.children) { child in
                    SymbolRow(symbol: child, onSelect: onSelect)
                        .padding(.leading, 16) // Indentation
                }
            }
        }
    }
    
    private func colorForKind(_ kind: Symbol.SymbolKind) -> Color {
        switch kind {
        case .classSymbol, .structSymbol: return .orange
        case .function, .method: return .purple
        case .variable, .property, .field: return .blue
        case .constant: return .cyan
        case .enumSymbol, .enumMember: return .green
        case .interface, .extension: return .yellow
        case .module: return .red
        default: return .gray
        }
    }
}
