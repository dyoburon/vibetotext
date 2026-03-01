// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DontAngerTheAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DontAngerTheAI",
            path: "Sources/DontAngerTheAI",
            resources: [
                .copy("Web"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
