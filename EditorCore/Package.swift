// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EditorCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "EditorCore",
            targets: ["EditorCore"]
        ),
        // Expose parsers as a separate product for optional use
        .library(
            name: "EditorParsers",
            targets: ["EditorParsers"]
        ),
    ],
    dependencies: [
        // SwiftSyntax (for Swift parsing)
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        
        // SwiftTreeSitter (Core wrapper)
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.8.0"),
        
        // Language Grammars
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.21.0")
    ],
    targets: [
        .target(
            name: "EditorCore",
            dependencies: [],
            path: "Sources/EditorCore"
        ),
        // New Target: Dedicated to Parsing to keep Core lightweight
        .target(
            name: "EditorParsers",
            dependencies: [
                "EditorCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
            ],
            path: "Sources/EditorParsers"
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore", "EditorParsers"],
            path: "Tests/EditorCoreTests"
        ),
    ]
)
