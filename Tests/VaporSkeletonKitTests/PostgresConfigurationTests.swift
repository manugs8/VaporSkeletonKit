import Fluent
import Testing

@testable import VaporSkeletonKit

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

    @Test("Builds a configuration from a databaseURL")
    func fromDatabaseURL() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: "postgres://user:pass@example.com/db?sslmode=require",
            host: nil, port: nil, username: nil, password: nil, database: nil, tlsDisabled: false)
        _ = try makePostgresConfiguration(from: config)
    }

    @Test("Builds a configuration from discrete fields with TLS disabled")
    func fromDiscreteFieldsTLSDisabled() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: nil, host: "127.0.0.1", port: nil, username: "app", password: "app", database: "app",
            tlsDisabled: true)
        _ = try makePostgresConfiguration(from: config)
    }

    @Test("Prefers databaseURL over discrete fields when both are present")
    func prefersDatabaseURL() throws {
        let config = PostgresEnvironmentConfig(
            databaseURL: "postgres://user:pass@example.com/db?sslmode=require",
            host: "ignored", port: 1, username: "ignored", password: "ignored", database: "ignored",
            tlsDisabled: true)
        _ = try makePostgresConfiguration(from: config)
    }
}
