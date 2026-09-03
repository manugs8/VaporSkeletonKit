import Fluent
import FluentPostgresDriver
import Vapor

/// Los valores derivados del entorno necesarios para construir una configuración de
/// base de datos Postgres.
///
/// Se admiten dos estilos de configuración:
///
/// 1. Una única cadena de conexión `databaseURL` (el formato que proporciona Neon
///    directamente). Este es el camino de producción: Neon exige TLS en cada conexión,
///    así que siempre se establece con `.require`.
/// 2. Valores discretos de `host`, `port`, `username`, `password` y `database`, usados
///    cuando `databaseURL` es `nil`. Este es el camino de desarrollo local (p. ej. un
///    Postgres corriendo en `localhost`), así que TLS es obligatorio por defecto pero
///    se puede desactivar con `tlsDisabled`.
///
/// El llamador lee su propio entorno de proceso (con los nombres de variable que
/// prefiera) y pasa aquí los valores resultantes — este tipo nunca lee `Environment`
/// por sí mismo, siguiendo el mismo patrón con el que `BearerAuthEnvironmentConfig` de
/// `WorkOSBearerAuth` es rellenado por quien la usa.
public struct PostgresEnvironmentConfig: Sendable {
    public let databaseURL: String?
    public let host: String?
    public let port: Int?
    public let username: String?
    public let password: String?
    public let database: String?
    public let tlsDisabled: Bool

    /// Crea una nueva configuración a partir de valores de entorno ya leídos.
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

/// Errores que pueden ocurrir al ensamblar una configuración de base de datos Postgres.
public enum PostgresConfigurationError: Error, CustomStringConvertible, Sendable {
    /// Ni `databaseURL` ni los valores discretos de host/username/password/database
    /// estaban completos.
    case missingDatabaseEnvironment

    public var description: String {
        switch self {
        case .missingDatabaseEnvironment:
            return "Missing database configuration. Set databaseURL, or all of " +
                "host, username, password, and database."
        }
    }
}

/// Construye una configuración de base de datos Postgres a partir de un conjunto de
/// valores de entorno ya leídos.
///
/// - Parameter config: Los valores de configuración derivados del entorno.
/// - Throws: `PostgresConfigurationError.missingDatabaseEnvironment` si ni
///   `config.databaseURL` ni el conjunto completo de campos discretos están presentes.
/// - Returns: Un `DatabaseConfigurationFactory` listo para registrarse en
///   `app.databases`.
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

/// Construye un contexto TLS permisivo, adecuado para proveedores gestionados de
/// Postgres (p. ej. Neon) cuyos certificados están firmados por una CA pública pero a
/// los que se accede sin pinning.
private func makeNIOSSLContext() throws -> NIOSSLContext {
    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.certificateVerification = .none
    return try NIOSSLContext(configuration: tlsConfiguration)
}
