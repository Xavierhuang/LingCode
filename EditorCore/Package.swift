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
        // NOTE: Version must match Xcode project requirement (602.0.0)
        .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0"),
        
        // Tree-sitter disabled due to scanner.c linker issues with SPM
        // The TreeSitterManager will use fallback regex-based extraction
        // To re-enable: uncomment dependencies below and in EditorParsers target
        // .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        // .package(url: "https://github.com/tree-sitter/tree-sitter-python", from: "0.23.0"),
        // .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", from: "0.23.0"),
        // .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.0"),
        // .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.23.0"),
    ],
    targets: [
        .target(
            name: "EditorCore",
            dependencies: [],
            path: "Sources/EditorCore"
        ),
        // EditorParsers: Uses SwiftSyntax for Swift, fallback for other languages
        .target(
            name: "EditorParsers",
            dependencies: [
                "EditorCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                // Tree-sitter disabled - using fallback implementation
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
