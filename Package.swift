// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacGHActionsNotifier",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacGHActionsNotifier", targets: ["MacGHActionsNotifier"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "MacGHActionsNotifier",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
