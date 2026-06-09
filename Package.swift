// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lost",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "LostUI", targets: ["LostUI"]),
        .executable(name: "LostApp", targets: ["LostApp"]),
    ],
    targets: [
        .target(
            name: "GameCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "LostUI",
            dependencies: ["GameCore"]
        ),
        .executableTarget(
            name: "LostApp",
            dependencies: ["LostUI"]
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"]
        ),
    ]
)
