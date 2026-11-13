// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabStation",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TabStation",
            path: "Sources/TabStation",
            // AppKit + CGEventTap + legacy C window-list APIs are not fully
            // Sendable-clean, so we compile in Swift 5 language mode.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)