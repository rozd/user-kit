// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UserKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "UserKit",
            targets: ["UserKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "UserKit",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "UserKitTests",
            dependencies: ["UserKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
