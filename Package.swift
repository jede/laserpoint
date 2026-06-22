// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Laserpoint",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Laserpoint",
            path: "Sources/Laserpoint",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
