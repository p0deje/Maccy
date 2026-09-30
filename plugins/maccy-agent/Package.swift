// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "maccy-agent",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "maccy-agent",
            path: "Sources/maccy-agent"
        )
    ]
)