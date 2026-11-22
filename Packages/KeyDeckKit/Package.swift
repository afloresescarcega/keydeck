// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyDeckKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "KeyDeckKit",
            targets: ["KeyDeckKit"]
        )
    ],
    targets: [
        .target(
            name: "KeyDeckKit",
            path: "Sources/KeyDeckKit"
        ),
        .testTarget(
            name: "KeyDeckKitTests",
            dependencies: ["KeyDeckKit"],
            path: "Tests/KeyDeckKitTests"
        )
    ]
)
