// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LiquidIsland",
            path: "Sources/LiquidIsland",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
