// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodexUsageCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CodexUsageCore", targets: ["CodexUsageCore"])],
    targets: [
        .target(name: "CodexUsageCore", path: "Sources", exclude: ["Widget", "App/Assets.xcassets", "Core/Assets.xcassets", "App/CodexUsageApp.swift", "Core/UsageCard.swift", "Core/RefreshUsageIntent.swift"], resources: [.process("Core/Resources")]),
        .testTarget(name: "CodexUsageCoreTests", dependencies: ["CodexUsageCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
