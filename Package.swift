// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JustClick",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JustClick", targets: ["JustClick"])],
    targets: [
        .target(name: "JustClickCore"),
        .target(name: "JustClickPasteKit", dependencies: ["JustClickCore"]),
        .executableTarget(name: "JustClick", dependencies: ["JustClickCore", "JustClickPasteKit"]),
        .executableTarget(name: "JustClickChecks", dependencies: ["JustClickCore"], path: "Tests/JustClickCoreTests"),
        .executableTarget(name: "JustClickVisionChecks", dependencies: ["JustClickPasteKit"], path: "Tests/JustClickVisionChecks"),
        .executableTarget(name: "JustClickPasteChecks", dependencies: ["JustClickPasteKit"], path: "Tests/JustClickPasteChecks")
    ],
    swiftLanguageModes: [.v5]
)
