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

    /// Proves the route depends only on the `HealthChecking` protocol, not a concrete
    /// database check — the injected stub decides the outcome regardless of `req.db`.
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

/// Configures a real Postgres connection for this suite — `registerHealthRoute` reads
/// `req.db` unconditionally (even the stub test below needs *some* database configured,
/// since the stub only ignores its *result*, not whether `req.db` resolves at all).
///
/// Same `DATABASE_*` variable names as every consuming project's own CI Postgres
/// service (§5.2), so this suite runs unmodified once this repo gets a CI workflow of
/// its own. With no env set, defaults to a plain local Postgres on `localhost` with TLS
/// disabled — the common local dev setup — rather than requiring TLS, unlike
/// `configure.swift`'s own default; override with `DATABASE_TLS=require` for the
/// stricter behavior.
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

/// A `HealthChecking` stub that always returns a fixed result, used to test the
/// `/health` route in isolation from a real database's query outcome.
private struct StubHealthChecker: HealthChecking {
    let result: HealthStatus

    func check(on database: any Database) async -> HealthStatus {
        result
    }
}
