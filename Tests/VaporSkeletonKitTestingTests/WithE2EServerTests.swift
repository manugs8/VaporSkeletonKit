import Fluent
import Foundation
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitE2ESupport
import VaporSkeletonKitTesting

@Suite("With E2E Server")
struct WithE2EServerTests {
    @Test("Arranca el servidor en un puerto propio, migra y permite llamadas reales de red, con E2E_MODE en true")
    func bindsEphemeralPortAndHandlesTraffic() async throws {
        var host = ""
        var originalEnv = ProcessInfo.processInfo.environment["E2E_MODE"]

        try await withE2EServer(
            environment: ["TEST_FLAG_E2E": "ON"],
            configure: { app in
                try configureTestDatabase(app)
                app.get("ping") { _ in "pong" }
            }
        ) { client in
            // Verifica puerto efímero.
            #expect(client.baseURL.port != nil)
            #expect(client.baseURL.port != 8080)
            
            // Verifica las variables en el proceso.
            #expect(ProcessInfo.processInfo.environment["E2E_MODE"] == "true")
            #expect(ProcessInfo.processInfo.environment["TEST_FLAG_E2E"] == "ON")
            #expect(client.baseURL.host == "127.0.0.1")
            
            // Realiza una petición TCP HTTP pura
            let response = try await client.get("/ping")
            #expect(response.status == 200)
            let bodyString = String(decoding: response.body, as: UTF8.self)
            #expect(bodyString == "pong")
        }
    }

    @Test("Propaga el error tras limpiar si el test falla")
    func propagatesTestErrors() async throws {
        struct BoomError: Error {}

        await #expect(throws: BoomError.self) {
            try await withE2EServer(configure: configureTestDatabase) { client in
                throw BoomError()
            }
        }
    }
}

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
