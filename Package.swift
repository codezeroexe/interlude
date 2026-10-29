// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Interlude",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Interlude"),
        .testTarget(name: "InterludeTests", dependencies: ["Interlude"]),
    ],
    swiftLanguageModes: [.v5]
)
