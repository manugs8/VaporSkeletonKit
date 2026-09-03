import Fluent
import FluentPostgresDriver
import Vapor

/// An abstraction over a service capable of reporting whether its dependencies are healthy.
///
/// Conforming types back the `/health` route registered by ``registerHealthRoute(_:)``.
/// Depending on this protocol rather than a concrete type keeps the health check
/// testable: production code can inject `DatabaseHealthChecker`, while tests can inject
/// a stub that returns a fixed result.
public protocol HealthChecking: Sendable {
    /// Checks the health of the underlying dependency.
    ///
    /// - Parameter database: The database to check connectivity against.
    /// - Returns: A `HealthStatus` describing the outcome of the check.
    func check(on database: any Database) async -> HealthStatus
}

extension Application {
    private struct HealthCheckerKey: StorageKey {
        typealias Value = any HealthChecking
    }

    /// The `HealthChecking` implementation used by the `/health` route.
    ///
    /// Defaults to `DatabaseHealthChecker` if never set. Tests can override this with a
    /// stub implementation to exercise the route without a real database.
    public var healthChecker: any HealthChecking {
        get {
            self.storage[HealthCheckerKey.self] ?? DatabaseHealthChecker()
        }
        set {
            self.storage[HealthCheckerKey.self] = newValue
        }
    }
}

/// A `HealthChecking` implementation that verifies database connectivity by executing a
/// trivial query directly against the configured Postgres connection.
public struct DatabaseHealthChecker: HealthChecking {
    /// Creates a new database health checker.
    public init() {}

    /// Runs `SELECT 1` against the given database to confirm the connection is alive.
    ///
    /// - Parameter database: The database to check connectivity against.
    /// - Returns: A healthy `HealthStatus` if the query succeeds, otherwise an unhealthy
    ///   one describing the failure.
    public func check(on database: any Database) async -> HealthStatus {
        guard let postgres = database as? any PostgresDatabase else {
            return HealthStatus(isHealthy: false, message: "Configured database is not PostgreSQL.")
        }
        do {
            _ = try await postgres.simpleQuery("SELECT 1").get()
            return HealthStatus(isHealthy: true, message: "Database connection is healthy.")
        } catch {
            return HealthStatus(isHealthy: false, message: "Database connection failed: \(error)")
        }
    }
}

/// The result of a health check, returned as the JSON body of `GET /health`.
public struct HealthStatus: Content, Equatable, Sendable {
    /// Whether the checked dependency is reachable and functioning.
    public let isHealthy: Bool

    /// A human-readable description of the check result.
    public let message: String

    /// Creates a new health status.
    ///
    /// - Parameters:
    ///   - isHealthy: Whether the checked dependency is healthy.
    ///   - message: A human-readable description of the result.
    public init(isHealthy: Bool, message: String) {
        self.isHealthy = isHealthy
        self.message = message
    }
}
