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
        // Separado del propio `VaporSkeletonKit`, el mismo split que usa WorkOSBearerAuth
        // para su propio `WorkOSBearerAuthTesting`: el target de tests de un proyecto
        // consumidor enlaza esto para obtener las mismas utilidades `withTestApp`/
        // `sendMCP` que usan los tests de este repo, en lugar de copiarlas y pegarlas.
        .library(name: "VaporSkeletonKitTesting", targets: ["VaporSkeletonKitTesting"]),
        // Deliberadamente ligero en dependencias (sin Vapor/Fluent), mismo razonamiento
        // que `VaporSkeletonKitTesting`/`WorkOSBearerAuthTesting`: las suites E2E hablan
        // HTTP/MCP real con un servidor ya en ejecución (normalmente la imagen Docker de
        // producción), nunca con una `Application` en proceso, así que no tienen motivo
        // para enlazar la pila del lado del servidor. Seguro de compartir también con un
        // target de seed determinista.
        .library(name: "VaporSkeletonKitE2ESupport", targets: ["VaporSkeletonKitE2ESupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        // Solo se usa como plugin de comando (`generate-documentation`/
        // `preview-documentation`) para el catálogo DocC en
        // Sources/VaporSkeletonKit/VaporSkeletonKit.docc — no se enlaza en ningún
        // producto, así que no añade peso en tiempo de ejecución a ningún consumidor.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
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
