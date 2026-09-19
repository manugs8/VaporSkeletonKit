// swift-tools-version:6.0
import PackageDescription

// El modo de lenguaje Swift 6 fuerza la comprobación estricta y completa de
// concurrencia por defecto, lo cual equivale al build setting
// `SWIFT_STRICT_CONCURRENCY=complete` usado en modo Swift 5.
let package = Package(
    name: "VaporSkeletonKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VaporSkeletonKit", targets: ["VaporSkeletonKit"]),
        .library(name: "VaporSkeletonKitTesting", targets: ["VaporSkeletonKitTesting"]),
        .library(name: "VaporSkeletonKitE2ESupport", targets: ["VaporSkeletonKitE2ESupport"]),
        .library(name: "VaporSkeletonKitMCP", targets: ["VaporSkeletonKitMCP"]),
        .library(name: "VaporSkeletonKitMCPTesting", targets: ["VaporSkeletonKitMCPTesting"]),
        .library(name: "VaporSkeletonKitMCPE2ESupport", targets: ["VaporSkeletonKitMCPE2ESupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "VaporSkeletonKit",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
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
        .target(
            name: "VaporSkeletonKitMCP",
            dependencies: [
                .target(name: "VaporSkeletonKit"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporSkeletonKitMCPTests",
            dependencies: [
                .target(name: "VaporSkeletonKitMCP"),
                .target(name: "VaporSkeletonKitTesting"),
                .target(name: "VaporSkeletonKit"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "VaporSkeletonKitMCPTesting",
            dependencies: [
                .target(name: "VaporSkeletonKitTesting"),
                .target(name: "VaporSkeletonKitMCP"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporSkeletonKitMCPTestingTests",
            dependencies: [
                .target(name: "VaporSkeletonKitMCPTesting"),
                .target(name: "VaporSkeletonKitMCP"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "VaporSkeletonKitMCPE2ESupport",
            dependencies: [
                .target(name: "VaporSkeletonKitE2ESupport"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporSkeletonKitMCPE2ESupportTests",
            dependencies: [
                .target(name: "VaporSkeletonKitMCPE2ESupport"),
                .target(name: "VaporSkeletonKitE2ESupport"),
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
