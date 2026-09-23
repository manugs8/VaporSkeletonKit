import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitTesting

@Suite("withUnreachableDatabaseServer")
struct WithUnreachableDatabaseServerTests {
    @Test("Configures the app, boots it on a real ephemeral port, and shuts it down after")
    func happyPath() async throws {
        var configureRan = false

        try await withUnreachableDatabaseServer(
            configure: { app in
                configureRan = true
                app.get("ping") { _ in "pong" }
            },
            { client in
                let response = try await client.get("ping")
                #expect(response.status == 200)
            }
        )

        #expect(configureRan)
    }

    @Test("Propagates an error thrown by the test body, after still shutting down")
    func propagatesTestErrors() async throws {
        struct BoomError: Error {}

        await #expect(throws: BoomError.self) {
            try await withUnreachableDatabaseServer(
                configure: { app in app.get("ping") { _ in "pong" } },
                { _ in throw BoomError() }
            )
        }
    }

    @Test("A route that genuinely can't reach the database surfaces a real failure, not a stub")
    func realDatabaseFailureSurfaces() async throws {
        try await withUnreachableDatabaseServer(
            configure: { app in
                app.databases.use(
                    try makePostgresConfiguration(from: PostgresEnvironmentConfig(
                        databaseURL: nil, host: "127.0.0.1", port: 1, username: "postgres",
                        password: "postgres", database: "postgres", tlsDisabled: true
                    )),
                    as: .psql
                )
                app.get("needs-db") { req async throws -> String in
                    _ = try await (req.db as! any SQLDatabase).raw("SELECT 1").all()
                    return "unreachable"
                }
            },
            { client in
                let response = try await client.get("needs-db")
                #expect(response.status == 500)
            }
        )
    }
}
