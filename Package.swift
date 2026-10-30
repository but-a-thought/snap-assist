// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapAssist",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SnapAssist",
            path: "Sources/SnapAssist",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
