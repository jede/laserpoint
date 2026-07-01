// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Laserpoint",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/nicklockwood/Expression", from: "0.13.0")
    ],
    targets: [
        .executableTarget(
            name: "Laserpoint",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Expression", package: "Expression")
            ],
            path: "Sources/Laserpoint",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "LaserpointTests",
            dependencies: ["Laserpoint"],
            path: "Tests/LaserpointTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
