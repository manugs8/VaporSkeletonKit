import Fluent
import FluentPostgresDriver
import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

@Suite("Health Route")
struct HealthRouteTests {
    @Test("Reports healthy when the database is reachable")
    func healthyWithRealDatabase() async throws {
        let app = try await Application.make(.testing)
        do {
            try configureTestDatabase(app)
            registerHealthRoute(app)

            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                let status = try res.content.decode(HealthStatus.self)
                #expect(status.isHealthy)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Demuestra que la ruta depende solo del protocolo `HealthChecking`, no de una
    /// comprobación de base de datos concreta — el stub inyectado decide el resultado
    /// independientemente de `req.db`.
    @Test("Reports unhealthy and 503 when the checker fails")
    func unhealthyWhenCheckerFails() async throws {
        let app = try await Application.make(.testing)
        do {
            try configureTestDatabase(app)
            app.healthChecker = StubHealthChecker(result: HealthStatus(isHealthy: false, message: "boom"))
            registerHealthRoute(app)

            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .serviceUnavailable)
                let status = try res.content.decode(HealthStatus.self)
                #expect(status.isHealthy == false)
                #expect(status.message == "boom")
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

/// Configura una conexión Postgres real para esta suite — `registerHealthRoute` lee
/// `req.db` incondicionalmente (incluso el test con stub de abajo necesita *alguna*
/// base de datos configurada, ya que el stub solo ignora su *resultado*, no si
/// `req.db` llega a resolverse).
///
/// Mismos nombres de variable `DATABASE_*` que usa el propio servicio Postgres de CI de
/// cualquier proyecto consumidor (§5.2), así que esta suite se ejecuta sin
/// modificaciones ahora que este repo tiene su propio workflow de CI
/// (`.github/workflows/ci.yml`). Sin ninguna variable de entorno establecida, usa por
/// defecto un Postgres local sencillo en `localhost` con TLS desactivado — la
/// configuración habitual de desarrollo local — en lugar de exigir TLS, a diferencia
/// del valor por defecto del propio `configure.swift`; sobreescribe con
/// `DATABASE_TLS=require` para el comportamiento más estricto.
private func configureTestDatabase(_ app: Application) throws {
    app.databases.use(
        try makePostgresConfiguration(from: PostgresEnvironmentConfig(
            databaseURL: Environment.get("DATABASE_URL"),
            host: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DATABASE_USERNAME") ?? "postgres",
            password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
            database: Environment.get("DATABASE_NAME") ?? "postgres",
            tlsDisabled: Environment.get("DATABASE_TLS") != "require"
        )),
        as: .psql
    )
}

/// Un stub de `HealthChecking` que siempre devuelve un resultado fijo, usado para
/// testear la ruta `/health` de forma aislada del resultado real de una consulta a la
/// base de datos.
private struct StubHealthChecker: HealthChecking {
    let result: HealthStatus

    func check(on database: any Database) async -> HealthStatus {
        result
    }
}
