// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalhostPanel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LocalhostPanel", targets: ["LocalhostPanel"]),
    ],
    targets: [
        .target(name: "PanelCore"),
        .executableTarget(name: "LocalhostPanel", dependencies: ["PanelCore"]),
        .testTarget(name: "PanelCoreTests", dependencies: ["PanelCore"]),
    ],
    swiftLanguageModes: [.v5]
)
