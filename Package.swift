// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UserKit",
    platforms: [
        .iOS(.v18),
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
                // Match the consumer app's "Approachable Concurrency" dialect so
                // async-closure isolation lines up across the package boundary
                // (else protocol conformances mismatch: nonisolated(nonsending) vs @concurrent).
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "UserKitTests",
            dependencies: ["UserKit"],
            swiftSettings: [
                // Match the consumer app's "Approachable Concurrency" dialect so
                // async-closure isolation lines up across the package boundary
                // (else protocol conformances mismatch: nonisolated(nonsending) vs @concurrent).
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
