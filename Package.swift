// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    // Clipskein's internal names stay stable so resources and existing tooling still resolve.
    name: "ClipNest",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipNest", targets: ["ClipNest"])
    ],
    targets: [
        .executableTarget(
            name: "ClipNest",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ClipNestTests", dependencies: ["ClipNest"])
    ]
)
