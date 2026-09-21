import Fluent
import Testing

@testable import VaporSkeletonKit

/// Comprobar solo que `makePostgresConfiguration` "no lanza" dejaría pasar en verde un
/// bug que intercambiara usuario y contraseña, o ignorara `port`.
/// `dumpedConfiguration(_:)` hace transparente el `DatabaseConfigurationFactory` opaco
/// que devuelve la función para poder afirmar sobre su contenido real.
@Suite("Postgres Configuration")
struct PostgresConfigurationTests {
    @Test("Throws missingDatabaseEnvironment when neither databaseURL nor discrete fields are set")
    func missingEverything() {
        let config = PostgresEnvironmentConfig(
            databaseURL: nil, host: nil, port: nil, username: nil, password: nil, database: nil,
            tlsDisabled: false)
        #expect(throws: PostgresConfigurationError.self) {
            _ = try makePostgresConfiguration(from: config)
        }
    }

    @Test("Throws missingDatabaseEnvironment when only some discrete fields are set")
    func partialDiscreteFields() {
        let config = PostgresEnvironmentConfig(
            databaseURL: nil, host: "localhost", port: nil, username: nil, password: "secret", database: nil,
            tlsDisabled: true)
        #expect(throws: PostgresConfigurationError.self) {
            _ = try makePostgresConfiguration(from: config)
        }
    }

    @Test("Builds a configuration from a databaseURL, and always forces TLS to .require regardless of sslmode")
    func fromDatabaseURL() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: "postgres://urluser:urlpass@example.com/urldb?sslmode=disable",
            host: nil, port: nil, username: nil, password: nil, database: nil, tlsDisabled: false)
        let dumped = try dumpedConfiguration(config)

        #expect(dumped.contains(#"host: "example.com""#))
        #expect(dumped.contains("port: 5432"))
        #expect(dumped.contains(#"username: "urluser""#))
        #expect(dumped.contains(#"some: "urlpass""#))
        #expect(dumped.contains(#"some: "urldb""#))
        // El propio comentario de PostgresConfiguration.swift documenta por qué: Neon
        // (el proveedor de producción) exige TLS en cada conexión, así que se ignora
        // deliberadamente lo que diga la propia URL sobre TLS.
        #expect(dumped.contains("TLS.Base.require"))
    }

    @Test("Builds a configuration from discrete fields, honoring an explicit port and tlsDisabled")
    func fromDiscreteFieldsTLSDisabled() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: nil, host: "127.0.0.1", port: 5555, username: "app", password: "app-secret",
            database: "appdb", tlsDisabled: true)
        let dumped = try dumpedConfiguration(config)

        #expect(dumped.contains(#"host: "127.0.0.1""#))
        #expect(dumped.contains("port: 5555"))
        #expect(dumped.contains(#"username: "app""#))
        #expect(dumped.contains(#"some: "app-secret""#))
        #expect(dumped.contains(#"some: "appdb""#))
        #expect(dumped.contains("TLS.Base.disable"))
    }

    @Test("Falls back to the IANA Postgres port when port is nil")
    func fromDiscreteFieldsDefaultPort() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: nil, host: "127.0.0.1", port: nil, username: "app", password: "app", database: "app",
            tlsDisabled: true)
        let dumped = try dumpedConfiguration(config)

        #expect(dumped.contains("port: 5432"))
    }

    @Test("Prefers databaseURL over discrete fields when both are present — the discrete values never appear")
    func prefersDatabaseURL() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: "postgres://urluser:urlpass@example.com/urldb?sslmode=disable",
            host: "ignored-host", port: 1, username: "ignored-user", password: "ignored-pass",
            database: "ignored-db", tlsDisabled: true)
        let dumped = try dumpedConfiguration(config)

        #expect(dumped.contains(#"host: "example.com""#))
        #expect(dumped.contains(#"username: "urluser""#))
        #expect(!dumped.contains("ignored"))
        // tlsDisabled: true en los campos discretos, ignorados — sigue forzando .require.
        #expect(dumped.contains("TLS.Base.require"))
    }
}

/// `makePostgresConfiguration` devuelve un `DatabaseConfigurationFactory` opaco — el
/// `PostgresConnection.Configuration` que construye internamente no es alcanzable por
/// ninguna API pública (el tipo que lo contiene no lo expone, y declarar
/// PostgresKit/PostgresNIO como dependencia de este target de test solo para nombrar
/// ese tipo sería desproporcionado para lo que necesita un test unitario). `Mirror`
/// evita ese problema sin tocar `Package.swift`: expone las propiedades almacenadas
/// sin importar su nivel de acceso, y solo necesita `Fluent` (ya importado arriba)
/// para sostener el `any DatabaseConfiguration` con el que se recorre.
private func dumpedConfiguration(_ config: PostgresEnvironmentConfig) throws -> String {
    let factory = try makePostgresConfiguration(from: config)
    var output = ""
    dump(factory.make(), to: &output)
    return output
}
