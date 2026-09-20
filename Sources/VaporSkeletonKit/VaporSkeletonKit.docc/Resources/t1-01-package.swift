// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyProject",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "1.3.5"),
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
