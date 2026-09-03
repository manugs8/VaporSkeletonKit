// swift-tools-version:6.0
import PackageDescription

// Swift 6 language mode enforces complete strict concurrency checking by default,
// which is the equivalent of the `SWIFT_STRICT_CONCURRENCY=complete` build setting
// used in Swift 5 mode.
let package = Package(
    name: "VaporSkeletonKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VaporSkeletonKit", targets: ["VaporSkeletonKit"]),
        // Separate from `VaporSkeletonKit` itself, same split WorkOSBearerAuth uses for
        // its own `WorkOSBearerAuthTesting`: a consuming project's own test target links
        // this to get the same `withTestApp`/`sendMCP` helpers this repo's tests use,
        // instead of copy-pasting them.
        .library(name: "VaporSkeletonKitTesting", targets: ["VaporSkeletonKitTesting"]),
        // Deliberately dependency-light (no Vapor/Fluent), same reasoning as
        // `VaporSkeletonKitTesting`/`WorkOSBearerAuthTesting`: E2E suites talk real
        // HTTP/MCP to an already-running server (often the production Docker image),
        // never an in-process `Application`, so they have no reason to link the
        // server-side stack. Safe to share with a deterministic seed target too.
        .library(name: "VaporSkeletonKitE2ESupport", targets: ["VaporSkeletonKitE2ESupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ],
    targets: [
        .target(
            name: "VaporSkeletonKit",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporSkeletonKitTests",
            dependencies: [
                .target(name: "VaporSkeletonKit"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "VaporSkeletonKitTesting",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporSkeletonKitTestingTests",
            dependencies: [
                .target(name: "VaporSkeletonKitTesting"),
                .target(name: "VaporSkeletonKit"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "VaporSkeletonKitE2ESupport",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporSkeletonKitE2ESupportTests",
            dependencies: [
                .target(name: "VaporSkeletonKitE2ESupport"),
                .target(name: "VaporSkeletonKit"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

var swiftSettings: [SwiftSetting] {
    [.enableUpcomingFeature("ExistentialAny")]
}
