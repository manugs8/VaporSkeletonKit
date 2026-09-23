import Vapor
import VaporSkeletonKitE2ESupport

/// Arranca una `Application` real en un puerto efímero, sin ejecutar migraciones y sin
/// modo E2E, para verificar cómo reacciona la app de verdad ante un fallo genuino de
/// base de datos — no un valor que alguna middleware de test le entregue. `configure`
/// es responsabilidad del proyecto consumidor: normalmente su propio `configure(_:)`
/// apuntado a una base de datos deliberadamente inalcanzable (host/puerto que rechacen la
/// conexión), igual que `withTestApp`/`withE2EServer` no asumen ningún `configure` en
/// concreto.
///
/// A diferencia de `withE2EServer` (que siempre aprovisiona una base de datos real y
/// alcanzable), esta función nunca ejecuta `autoMigrate()` ni crea nada — el objetivo es
/// justo que la primera consulta real falle.
///
/// ```swift
/// func withUnreachableDatabaseServer(_ test: (E2EHTTPClient) async throws -> Void) async throws {
///     try await VaporSkeletonKitTesting.withUnreachableDatabaseServer(configure: { app in
///         try await configure(
///             app,
///             postgresEnvironment: PostgresEnvironmentConfig(
///                 databaseURL: nil, host: "127.0.0.1", port: 1, username: "postgres",
///                 password: "postgres", database: "postgres", tlsDisabled: true
///             ),
///             bearerAuthEnvironment: .disabled, runMigrations: false, e2eModeEnabled: false
///         )
///     }, test)
/// }
/// ```
///
/// - Parameters:
///   - configure: Configura la `Application` — rutas, base de datos deliberadamente
///     inalcanzable, etc. — exactamente igual que el `configure(_:)` propio de un
///     proyecto.
///   - test: El cuerpo del test, con un `E2EHTTPClient` ya apuntado al puerto efímero
///     real de esta `Application`.
public func withUnreachableDatabaseServer(
    configure: (Application) async throws -> Void,
    _ test: (E2EHTTPClient) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)

    do {
        try await configure(app)

        app.http.server.configuration.port = 0
        try await app.asyncBoot()
        try app.server.start()

        guard let localAddress = app.http.server.shared.localAddress, let port = localAddress.port else {
            fatalError("No se ha podido obtener el puerto efímero asignado localmente en withUnreachableDatabaseServer.")
        }

        let client = E2EHTTPClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        try await test(client)

        await app.server.shutdown()
    } catch {
        await app.server.shutdown()
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
