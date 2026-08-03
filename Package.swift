// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ClipboardDoubleClick",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ClipboardDoubleClick",
            path: "Sources/ClipboardDoubleClick"
        )
    ]
)
