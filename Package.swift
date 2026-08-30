// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidIsland",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "LiquidIsland",
            path: "Sources/LiquidIsland",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                // Новый дизайн macOS выдаётся по версии SDK, записанной в
                // бинарнике. SwiftPM пишет туда версию платформы — с 15.0
                // система рисует приложению старый вид, и никакие настройки
                // этого не меняют. Записываем 26.0: с неё началось стекло.
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", "15.0",
                    "-Xlinker", "26.0"
                ])
            ]
        )
    ]
)
