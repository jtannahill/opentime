// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenTimeUI",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "OpenTimeUI", targets: ["OpenTimeUI"])
    ],
    targets: [
        .target(
            name: "OpenTimeUI",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OpenTimeUITests",
            dependencies: ["OpenTimeUI"]
        )
    ]
)
