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
    /// Necesita *alguna* base de datos registrada (sin ninguna, `registerHealthRoute`
    /// responde "No database configured." sin consultar al checker), pero no un
    /// Postgres alcanzable: `databases.use(...)` no abre ninguna conexión, y el stub
    /// nunca consulta `req.db`. Por eso no lleva el guard de `hasRealPostgresConfigured`.
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

/// Registra una conexión Postgres para esta suite. Registrarla no conecta: solo los
/// tests que llegan a consultar `req.db` de verdad (`healthyWithRealDatabase`)
/// necesitan un Postgres alcanzable, y por eso son los únicos con guard.
///
/// Mismos nombres de variable `DATABASE_*` que usa cualquier proyecto consumidor, así
/// que esta suite se ejecuta sin modificaciones en local. Sin ninguna variable de
/// entorno establecida, usa por defecto un Postgres local sencillo en `localhost` con
/// TLS desactivado — la configuración habitual de desarrollo local — en lugar de exigir
/// TLS, a diferencia del valor por defecto del propio `configure.swift`; sobreescribe con
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

/// Política de skip unificada para toda suite que necesite un Postgres real.
/// `.enabled(if:)` (en vez de un `guard ... else { return }` dentro del test) hace que
/// Swift Testing reporte estos tests como *skipped* en vez de como un verde engañoso.
let hasRealPostgresConfigured =
    ProcessInfo.processInfo.environment["CI"] == "true" || ProcessInfo.processInfo.environment["DATABASE_URL"] != nil

let dbSkipReason: Comment = "Requires a real Postgres connection (set CI=true or DATABASE_URL)."
