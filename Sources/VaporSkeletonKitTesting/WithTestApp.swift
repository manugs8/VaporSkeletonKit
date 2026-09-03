import Fluent
import Vapor

/// Boots a fully configured test `Application` — including running Fluent migrations —
/// executes `test` against it, then guarantees teardown (reverting migrations and
/// shutting the app down) even if `test` throws.
///
/// This is the "real Postgres, full app mounted in-process via `VaporTesting`" tier of
/// the three-tier testing strategy every project built from this kit follows (pure
/// logic / real-database integration / real-HTTP E2E). Requires a reachable Postgres
/// instance — whatever `configure` connects to.
///
/// ```swift
/// func withMigratedApp(_ test: (Application) async throws -> Void) async throws {
///     try await withTestApp(environment: ["AUTH_DISABLED": "true"], configure: configure, test: test)
/// }
/// ```
///
/// - Parameters:
///   - environment: Process environment variables to set (via `setenv`) before
///     `Application.make(.testing)` runs — e.g. a bearer-auth package's own
///     "disable auth for tests" flag. Empty by default: this function doesn't assume
///     any particular auth package or variable name, same as `makePostgresConfiguration`
///     not reading `Environment` itself.
///   - configure: Configures the `Application` (database, migrations, routes, etc.),
///     exactly like a project's own `configure(_:)`.
///   - test: The test body to execute with the live, migrated application.
public func withTestApp(
    environment: [String: String] = [:],
    configure: (Application) async throws -> Void,
    test: (Application) async throws -> Void
) async throws {
    for (key, value) in environment {
        setenv(key, value, 1)
    }

    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        try await app.autoMigrate()
        try await test(app)
        try await app.autoRevert()
    } catch {
        try? await app.autoRevert()
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
