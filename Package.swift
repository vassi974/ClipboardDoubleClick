// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ClipboardDoubleClick",
    defaultLocalization: "fr",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ClipboardDoubleClick",
            path: "Sources/ClipboardDoubleClick",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
