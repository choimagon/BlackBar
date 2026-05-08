// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BlackBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "BlackBar",
            targets: ["BlackBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BlackBar"
        )
    ]
)
