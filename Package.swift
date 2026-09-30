// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portscope",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Portscope", targets: ["Portscope"]),
    ],
    targets: [
        .target(name: "PortscopeCore"),
        .executableTarget(name: "Portscope", dependencies: ["PortscopeCore"]),
        .testTarget(name: "PortscopeCoreTests", dependencies: ["PortscopeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
