import Fluent
import FluentPostgresDriver
import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

@Suite("Health Route")
struct HealthRouteTests {
    @Test(
        "Reports healthy when the database is reachable",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
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
    ///
    /// Sigue necesitando `configureTestDatabase(app)` (y por tanto el mismo guard):
    /// `registerHealthRoute` lee `req.db` incondicionalmente, así que sin ninguna base
    /// de datos registrada fallaría antes de llegar siquiera al stub. Antes de
    /// unificar la política de skip (ver "Calidad de los tests existentes" en
    /// `docs/InformeDeAuditoria.md`) este test no tenía guard — fallaba sin red/Postgres,
    /// inconsistente con `healthyWithRealDatabase` en el mismo fichero.
    @Test(
        "Reports unhealthy and 503 when the checker fails",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
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

    @Test("Reports unhealthy and 503 when no database is configured, instead of crashing")
    func unhealthyWhenNoDatabaseConfigured() async throws {
        let app = try await Application.make(.testing)
        do {
            // A propósito, ninguna llamada a configureTestDatabase(app) — este test
            // existe justo para probar el caso "cero bases de datos registradas",
            // donde req.db haría fatalError sin la guarda de registerHealthRoute(_:).
            registerHealthRoute(app)

            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .serviceUnavailable)
                let status = try res.content.decode(HealthStatus.self)
                #expect(status.isHealthy == false)
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
/// Mismos nombres de variable `DATABASE_*` que se usan localmente y en entornos
/// cualquier proyecto consumidor (§5.2), así que esta suite se ejecuta sin
/// modificaciones en local. Sin ninguna variable de entorno establecida, usa por
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

/// Política de skip unificada para toda suite que necesite un Postgres real — ver
/// "Calidad de los tests existentes" en `docs/InformeDeAuditoria.md`. `.enabled(if:)`
/// (en vez de un `guard ... else { return }` dentro del test) hace que Swift Testing
/// reporte estos tests como *skipped* en vez de como un verde engañoso.
let hasRealPostgresConfigured =
    ProcessInfo.processInfo.environment["CI"] == "true" || ProcessInfo.processInfo.environment["DATABASE_URL"] != nil

let dbSkipReason: Comment = "Requires a real Postgres connection (set CI=true or DATABASE_URL)."
