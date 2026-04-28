// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibePulse",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "VibePulse",
            path: "VibePulse",
            exclude: [
                "Resources/claude-pulse-hook.py",
                "VibePulse.entitlements"
            ],
            resources: [
                .copy("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "VibePulseTests",
            dependencies: ["VibePulse"],
            path: "Tests/VibePulseTests"
        )
    ]
)
