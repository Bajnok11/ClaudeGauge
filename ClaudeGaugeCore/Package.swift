// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeGaugeCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClaudeGaugeCore",
            targets: ["ClaudeGaugeCore"]
        )
    ],
    targets: [
        .target(
            name: "ClaudeGaugeCore",
            path: "Sources/ClaudeGaugeCore"
        ),
        .testTarget(
            name: "ClaudeGaugeCoreTests",
            dependencies: ["ClaudeGaugeCore"],
            path: "Tests/ClaudeGaugeCoreTests"
        )
    ]
)
