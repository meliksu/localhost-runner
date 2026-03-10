// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalhostRunner",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LocalhostRunnerCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "LocalhostRunner",
            dependencies: ["LocalhostRunnerCore"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "LocalhostRunnerTests",
            dependencies: ["LocalhostRunnerCore"],
            path: "Tests",
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-plugin-path",
                    "-Xfrontend", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins"
                ])
            ]
        ),
    ]
)
