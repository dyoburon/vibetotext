// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordGalaxy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WordGalaxy",
            path: "Sources/WordGalaxy",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
