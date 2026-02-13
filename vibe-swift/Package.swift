// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeToText",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VibeToText", targets: ["VibeToText"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/ggerganov/whisper.spm.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "VibeToText",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "whisper", package: "whisper.spm"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
