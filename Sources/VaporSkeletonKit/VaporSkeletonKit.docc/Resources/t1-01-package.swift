// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyProject",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporSkeletonKit", package: "VaporSkeletonKit"),
            ]
        ),
    ]
)
