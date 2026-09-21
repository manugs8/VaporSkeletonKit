import Fluent
import Testing
import Vapor
@testable import VaporSkeletonKit
@testable import VaporSkeletonKitMCP

/// Ver V8 en `docs/InformeDeAuditoria.md`: `app.db` hace `fatalError` si no hay ninguna
/// base de datos configurada — `GetHealthTool` (como `registerHealthRoute(_:)`) ahora lo
/// comprueba antes en vez de tumbar el proceso entero por un endpoint de diagnóstico.
@Suite("Get Health Tool")
struct GetHealthToolTests {
    @Test("Reports unhealthy when no database is configured, instead of crashing")
    func unhealthyWhenNoDatabaseConfigured() async throws {
        let app = try await Application.make(.testing)
        do {
            let tool = GetHealthTool(app: app)
            let result = try await tool.call(arguments: [:])

            guard case .text(let text, _, _) = result.content.first else {
                Issue.record("Expected a text content item")
                return
            }
            #expect(text == "No database configured.")
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Requiere una base de datos real registrada: `app.healthChecker` decide el
    /// resultado, pero `app.databases.ids().isEmpty` (el único guard) sigue exigiendo
    /// que exista *alguna*, igual que en `HealthRouteTests`.
    @Test("Reports healthy when the database is reachable")
    func healthyWithRealDatabase() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == "true"
            || ProcessInfo.processInfo.environment["DATABASE_URL"] != nil
        else {
            return
        }
        let app = try await Application.make(.testing)
        do {
            try configureTestDatabase(app)
            let tool = GetHealthTool(app: app)
            let result = try await tool.call(arguments: [:])

            #expect(result.isError == nil)
            guard case .text(let text, _, _) = result.content.first else {
                Issue.record("Expected a text content item")
                return
            }
            #expect(text == "Database connection is healthy.")
            guard case .object(let structured) = result.structuredContent else {
                Issue.record("Expected structured content")
                return
            }
            #expect(structured["isHealthy"] == .bool(true))
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Demuestra que la herramienta depende solo del protocolo `HealthChecking`, igual
    /// que `registerHealthRoute(_:)` — y que un chequeo fallido se reporta como *dato*
    /// (`isHealthy: false` en `structuredContent`), no como un fallo de ejecución de la
    /// herramienta (`isError`): quien llama ha recibido con éxito la respuesta a "¿está
    /// sana la base de datos?", aunque la respuesta sea "no".
    @Test("Reports unhealthy, without isError, when the checker fails")
    func unhealthyWhenCheckerFails() async throws {
        let app = try await Application.make(.testing)
        do {
            try configureTestDatabase(app)
            app.healthChecker = StubHealthChecker(result: HealthStatus(isHealthy: false, message: "boom"))
            let tool = GetHealthTool(app: app)
            let result = try await tool.call(arguments: [:])

            #expect(result.isError == nil)
            guard case .text(let text, _, _) = result.content.first else {
                Issue.record("Expected a text content item")
                return
            }
            #expect(text == "boom")
            guard case .object(let structured) = result.structuredContent else {
                Issue.record("Expected structured content")
                return
            }
            #expect(structured["isHealthy"] == .bool(false))
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

/// Mismos nombres de variable `DATABASE_*` que `HealthRouteTests` — ver el comentario
/// de esa suite para el razonamiento completo.
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

private struct StubHealthChecker: HealthChecking {
    let result: HealthStatus

    func check(on database: any Database) async -> HealthStatus {
        result
    }
}
