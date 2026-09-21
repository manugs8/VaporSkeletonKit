// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyProject",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "VaporSkeletonKit", package: "VaporSkeletonKit"),
                .product(name: "VaporSkeletonKitMCP", package: "VaporSkeletonKit"),
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporSkeletonKitTesting", package: "VaporSkeletonKit"),
                .product(name: "VaporSkeletonKitMCPTesting", package: "VaporSkeletonKit"),
            ]
        ),
    ]
)
