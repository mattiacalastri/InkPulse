// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkPulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "InkPulse",
            path: "Sources",
            resources: [.copy("../Resources")]
        ),
        .testTarget(
            name: "InkPulseTests",
            dependencies: ["InkPulse"],
            path: "Tests"
        ),
    ]
)
