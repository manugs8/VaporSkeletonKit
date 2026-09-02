import Fluent
import FluentPostgresDriver
import Vapor

/// The environment-derived values needed to build a Postgres database configuration.
///
/// Two configuration styles are supported:
///
/// 1. A single `databaseURL` connection string (the format Neon provides directly).
///    This is the production path: Neon requires TLS on every connection, so it is
///    always established with `.require`.
/// 2. Discrete `host`, `port`, `username`, `password`, and `database` values, used when
///    `databaseURL` is `nil`. This is the local development path (e.g. a Postgres
///    running on `localhost`), so TLS defaults to required but can be turned off with
///    `tlsDisabled`.
///
/// The caller reads its own process environment (however it names its variables) and
/// passes the resulting values in here — this type never reads `Environment` itself,
/// mirroring how `WorkOSBearerAuth`'s `BearerAuthEnvironmentConfig` is populated by its
/// caller.
public struct PostgresEnvironmentConfig: Sendable {
    public let databaseURL: String?
    public let host: String?
    public let port: Int?
    public let username: String?
    public let password: String?
    public let database: String?
    public let tlsDisabled: Bool

    /// Creates a new configuration from already-read environment values.
    public init(
        databaseURL: String?,
        host: String?,
        port: Int?,
        username: String?,
        password: String?,
        database: String?,
        tlsDisabled: Bool
    ) {
        self.databaseURL = databaseURL
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.tlsDisabled = tlsDisabled
    }
}

/// Errors that can occur while assembling a Postgres database configuration.
public enum PostgresConfigurationError: Error, CustomStringConvertible, Sendable {
    /// Neither `databaseURL` nor the discrete host/username/password/database values were
    /// fully set.
    case missingDatabaseEnvironment

    public var description: String {
        switch self {
        case .missingDatabaseEnvironment:
            return "Missing database configuration. Set databaseURL, or all of " +
                "host, username, password, and database."
        }
    }
}

/// Builds a Postgres database configuration from an already-read set of environment
/// values.
///
/// - Parameter config: The environment-derived configuration values.
/// - Throws: `PostgresConfigurationError.missingDatabaseEnvironment` if neither
///   `config.databaseURL` nor the full set of discrete fields is present.
/// - Returns: A `DatabaseConfigurationFactory` ready to be registered on `app.databases`.
public func makePostgresConfiguration(from config: PostgresEnvironmentConfig) throws -> DatabaseConfigurationFactory {
    if let databaseURL = config.databaseURL {
        var sqlConfiguration = try SQLPostgresConfiguration(url: databaseURL)
        sqlConfiguration.coreConfiguration.tls = .require(try makeNIOSSLContext())
        return .postgres(configuration: sqlConfiguration)
    }

    guard
        let host = config.host,
        let username = config.username,
        let password = config.password,
        let database = config.database
    else {
        throw PostgresConfigurationError.missingDatabaseEnvironment
    }
    let port = config.port ?? SQLPostgresConfiguration.ianaPortNumber

    let tls: PostgresConnection.Configuration.TLS = config.tlsDisabled
        ? .disable
        : .require(try makeNIOSSLContext())

    let sqlConfiguration = SQLPostgresConfiguration(
        hostname: host,
        port: port,
        username: username,
        password: password,
        database: database,
        tls: tls
    )
    return .postgres(configuration: sqlConfiguration)
}

/// Builds a permissive TLS context suitable for managed Postgres providers (e.g. Neon)
/// whose certificates are signed by a public CA but which are reached without pinning.
private func makeNIOSSLContext() throws -> NIOSSLContext {
    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.certificateVerification = .none
    return try NIOSSLContext(configuration: tlsConfiguration)
}
