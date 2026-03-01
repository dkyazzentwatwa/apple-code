// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "apple-code",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "apple-code",
            path: "Sources/AppleCode"
        )
    ]
)
