import Logging
import NIOCore
import NIOPosix
import Vapor

/// Boots a Vapor `Application` and runs it until shutdown — the environment-detection,
/// logging bootstrap, and lifecycle boilerplate that's identical across every project
/// built from this kit, so a project's `@main` entrypoint only has to say what its own
/// `configure(_:)` does.
///
/// ```swift
/// @main
/// enum Entrypoint {
///     static func main() async throws {
///         try await runApp(configure: configure)
///     }
/// }
/// ```
///
/// If `configure` throws, the error is logged and the `Application` is shut down before
/// being rethrown — the server never starts serving on a half-configured app.
///
/// - Parameter configure: Configures the `Application` (database, migrations, routes,
///   etc.) before it starts serving.
public func runApp(configure: (Application) async throws -> Void) async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)

    let app = try await Application.make(env)
    try await runApp(app, configure: configure)
}

/// The testable core of ``runApp(configure:)``: runs `configure` against an
/// already-booted `Application`, then serves until shutdown.
///
/// Split out from ``runApp(configure:)`` so it can be exercised in tests against
/// `Application.make(.testing)` directly, without going through
/// `Environment.detect()`/`LoggingSystem.bootstrap(from:)` — the latter can only run
/// once per process, so it isn't something a test suite can call more than once.
///
/// - Parameters:
///   - app: An already-booted `Application`.
///   - configure: Configures the `Application` before it starts serving.
func runApp(_ app: Application, configure: (Application) async throws -> Void) async throws {
    do {
        try await configure(app)
    } catch {
        app.logger.report(error: error)
        try? await app.asyncShutdown()
        throw error
    }

    try await app.execute()
    try await app.asyncShutdown()
}
