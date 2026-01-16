# SwiftSyntax Integration Guide

## Status
✅ **Parser Service Created**: `SwiftSyntaxParser.swift` is ready with regex fallback
⏳ **Package Not Added**: SwiftSyntax package needs to be added via Xcode

## Quick Setup (5 minutes)

### Step 1: Add SwiftSyntax Package
1. Open `LingCode.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/apple/swift-syntax.git`
4. Select version: **509.0.0** (or latest stable)
5. Click **Add Package**
6. Select **SwiftSyntax** product
7. Add to **LingCode** target
8. Click **Add Package**

### Step 2: Update SwiftSyntaxParser.swift
Once the package is added, replace the placeholder in `SwiftSyntaxParser.extractSymbolsWithSwiftSyntax()`:

```swift
#if canImport(SwiftSyntax)
import SwiftSyntax
import SwiftSyntaxBuilder

private func extractSymbolsWithSwiftSyntax(from content: String, filePath: String) -> [CodeSymbol] {
    guard let sourceFile = try? SyntaxParser.parse(source: content) else {
        return extractSymbolsWithRegex(from: content, filePath: filePath)
    }
    
    var symbols: [CodeSymbol] = []
    let visitor = SymbolExtractorVisitor(filePath: filePath)
    visitor.walk(sourceFile)
    return visitor.symbols
}

private class SymbolExtractorVisitor: SyntaxVisitor {
    var symbols: [CodeSymbol] = []
    let filePath: String
    
    init(filePath: String) {
        self.filePath = filePath
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.identifier.text
        let startLine = node.positionAfterSkippingLeadingTrivia.line
        let endLine = node.endPosition.line
        let signature = node.signature.description
        
        symbols.append(CodeSymbol(
            name: name,
            kind: .function,
            filePath: filePath,
            startLine: startLine,
            endLine: endLine,
            signature: signature,
            content: node.description
        ))
        return .visitChildren
    }
    
    // Similar for ClassDeclSyntax, StructDeclSyntax, etc.
}
#else
// Fallback to regex
#endif
```

## Benefits
- **Robust Parsing**: Handles multi-line definitions, comments, generics correctly
- **No False Positives**: Won't match keywords in strings or comments
- **Accurate Line Ranges**: AST provides exact start/end positions
- **Future-Proof**: Works with any Swift syntax, including new language features

## Current State
The parser currently uses regex fallback, which works but is brittle. Once SwiftSyntax is added, it will automatically use the robust AST parser.
