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
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EditorCore",
            dependencies: [],
            path: "Sources/EditorCore"
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore"],
            path: "Tests/EditorCoreTests"
        ),
    ]
)
