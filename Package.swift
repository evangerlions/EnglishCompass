// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnglishCompass",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EnglishCompass", targets: ["EnglishCompass"])],
    targets: [
        .target(name: "AssistantCore"),
        .executableTarget(name: "EnglishCompass", dependencies: ["AssistantCore"]),
        .testTarget(name: "AssistantCoreTests", dependencies: ["AssistantCore"]),
        .testTarget(name: "EnglishCompassTests", dependencies: ["EnglishCompass"])
    ],
    swiftLanguageModes: [.v5]
)
