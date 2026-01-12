//
//  SymbolOutlineView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct Symbol: Identifiable {
    let id = UUID()
    let name: String
    let kind: SymbolKind
    let line: Int
    let children: [Symbol]
    
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
    }
}

class SymbolParser {
    static let shared = SymbolParser()
    
    private init() {}
    
    func parseSymbols(from content: String, language: String?) -> [Symbol] {
        guard let language = language?.lowercased() else { return [] }
        
        switch language {
        case "swift":
            return parseSwiftSymbols(from: content)
        case "python":
            return parsePythonSymbols(from: content)
        case "javascript", "typescript":
            return parseJSSymbols(from: content)
        default:
            return parseGenericSymbols(from: content)
        }
    }
    
    private func parseSwiftSymbols(from content: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Class
            if trimmed.range(of: #"class\s+(\w+)"#, options: .regularExpression) != nil {
                let name = extractName(from: trimmed, after: "class ")
                symbols.append(Symbol(name: name, kind: .classSymbol, line: index + 1, children: []))
            }
            // Struct
            else if trimmed.range(of: #"struct\s+(\w+)"#, options: .regularExpression) != nil {
                let name = extractName(from: trimmed, after: "struct ")
                symbols.append(Symbol(name: name, kind: .structSymbol, line: index + 1, children: []))
            }
            // Enum
            else if trimmed.range(of: #"enum\s+(\w+)"#, options: .regularExpression) != nil {
                let name = extractName(from: trimmed, after: "enum ")
                symbols.append(Symbol(name: name, kind: .enumSymbol, line: index + 1, children: []))
            }
            // Protocol
            else if trimmed.range(of: #"protocol\s+(\w+)"#, options: .regularExpression) != nil {
                let name = extractName(from: trimmed, after: "protocol ")
                symbols.append(Symbol(name: name, kind: .interface, line: index + 1, children: []))
            }
            // Function
            else if trimmed.range(of: #"func\s+(\w+)"#, options: .regularExpression) != nil {
                let name = extractName(from: trimmed, after: "func ")
                symbols.append(Symbol(name: name + "()", kind: .function, line: index + 1, children: []))
            }
            // Property
            else if trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ") {
                let prefix = trimmed.hasPrefix("var ") ? "var " : "let "
                let name = extractName(from: trimmed, after: prefix)
                let kind: Symbol.SymbolKind = trimmed.hasPrefix("let ") ? .constant : .variable
                symbols.append(Symbol(name: name, kind: kind, line: index + 1, children: []))
            }
        }
        
        return symbols
    }
    
    private func parsePythonSymbols(from content: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Class
            if trimmed.hasPrefix("class ") {
                let name = extractName(from: trimmed, after: "class ")
                    .components(separatedBy: "(").first ?? ""
                    .replacingOccurrences(of: ":", with: "")
                symbols.append(Symbol(name: name, kind: .classSymbol, line: index + 1, children: []))
            }
            // Function
            else if trimmed.hasPrefix("def ") {
                let name = extractName(from: trimmed, after: "def ")
                    .components(separatedBy: "(").first ?? ""
                symbols.append(Symbol(name: name + "()", kind: .function, line: index + 1, children: []))
            }
        }
        
        return symbols
    }
    
    private func parseJSSymbols(from content: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Class
            if trimmed.hasPrefix("class ") {
                let name = extractName(from: trimmed, after: "class ")
                    .components(separatedBy: " ").first ?? ""
                symbols.append(Symbol(name: name, kind: .classSymbol, line: index + 1, children: []))
            }
            // Function
            else if trimmed.hasPrefix("function ") {
                let name = extractName(from: trimmed, after: "function ")
                    .components(separatedBy: "(").first ?? ""
                symbols.append(Symbol(name: name + "()", kind: .function, line: index + 1, children: []))
            }
            // Arrow function with const
            else if trimmed.hasPrefix("const ") && trimmed.contains("=>") {
                let name = extractName(from: trimmed, after: "const ")
                    .components(separatedBy: " ").first ?? ""
                symbols.append(Symbol(name: name + "()", kind: .function, line: index + 1, children: []))
            }
            // Export
            else if trimmed.hasPrefix("export ") {
                // Handle exports
                if trimmed.contains("class ") {
                    let name = extractName(from: trimmed, after: "class ")
                        .components(separatedBy: " ").first ?? ""
                    symbols.append(Symbol(name: name, kind: .classSymbol, line: index + 1, children: []))
                } else if trimmed.contains("function ") {
                    let name = extractName(from: trimmed, after: "function ")
                        .components(separatedBy: "(").first ?? ""
                    symbols.append(Symbol(name: name + "()", kind: .function, line: index + 1, children: []))
                }
            }
        }
        
        return symbols
    }
    
    private func parseGenericSymbols(from content: String) -> [Symbol] {
        // Generic parser for unknown languages
        var symbols: [Symbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Look for function-like patterns
            if let range = trimmed.range(of: #"\b(\w+)\s*\("#, options: .regularExpression) {
                let match = String(trimmed[range])
                let name = match.replacingOccurrences(of: "(", with: "").trimmingCharacters(in: .whitespaces)
                if !["if", "for", "while", "switch", "catch"].contains(name) {
                    symbols.append(Symbol(name: name + "()", kind: .function, line: index + 1, children: []))
                }
            }
        }
        
        return symbols
    }
    
    private func extractName(from line: String, after prefix: String) -> String {
        guard let range = line.range(of: prefix) else { return "" }
        let afterPrefix = String(line[range.upperBound...])
        let components = afterPrefix.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components.first ?? ""
    }
}

struct SymbolOutlineView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var symbols: [Symbol] = []
    @State private var searchText: String = ""
    
    var filteredSymbols: [Symbol] {
        if searchText.isEmpty {
            return symbols
        }
        return symbols.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
            
            TextField("Filter symbols...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            if symbols.isEmpty {
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
                        Button(action: {
                            goToSymbol(symbol)
                        }) {
                            HStack {
                                Image(systemName: symbol.kind.rawValue)
                                    .foregroundColor(colorForKind(symbol.kind))
                                    .frame(width: 20)
                                
                                Text(symbol.name)
                                    .font(.system(.body, design: .monospaced))
                                
                                Spacer()
                                
                                Text(":\(symbol.line)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 250)
        .onAppear {
            refreshSymbols()
        }
        .onChange(of: viewModel.editorState.activeDocumentId) { _, _ in
            refreshSymbols()
        }
    }
    
    private func refreshSymbols() {
        guard let document = viewModel.editorState.activeDocument else {
            symbols = []
            return
        }
        
        symbols = SymbolParser.shared.parseSymbols(from: document.content, language: document.language)
    }
    
    private func goToSymbol(_ symbol: Symbol) {
        // TODO: Navigate to line
        NotificationCenter.default.post(
            name: NSNotification.Name("GoToLine"),
            object: nil,
            userInfo: ["line": symbol.line]
        )
    }
    
    private func colorForKind(_ kind: Symbol.SymbolKind) -> Color {
        switch kind {
        case .classSymbol, .structSymbol: return .orange
        case .function, .method: return .purple
        case .variable, .property, .field: return .blue
        case .constant: return .cyan
        case .enumSymbol, .enumMember: return .green
        case .interface: return .yellow
        default: return .gray
        }
    }
}

