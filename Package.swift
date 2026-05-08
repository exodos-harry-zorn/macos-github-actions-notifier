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
    targets: [
        .executableTarget(
            name: "MacGHActionsNotifier",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
