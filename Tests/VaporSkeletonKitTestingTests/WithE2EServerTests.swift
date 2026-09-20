import Fluent
import Foundation
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitE2ESupport
import VaporSkeletonKitTesting

@Suite("With E2E Server (Dynamic Database)")
struct WithE2EServerTests {
    @Test("Arranca el servidor en un puerto efímero aislado y con BD generada dinámicamente UUID")
    func bindsEphemeralPortAndUsesDynamicDatabase() async throws {
        // Skip test if no POSTGRES_URL or CI is set, as it requires a real Postgres
        guard ProcessInfo.processInfo.environment["CI"] == "true" || ProcessInfo.processInfo.environment["DATABASE_URL"] != nil else {
            print("Skipping E2E server test as no real Postgres connection is configured.")
            return
        }

        // MOCK de las credenciales máster que en un consumidor real vendrían de su propio
        // `.env.local`/`.env` (ver `PostgresEnvironmentConfig`: esta función nunca lee
        // `Environment` por sí misma, es el llamador quien las resuelve).
        let masterConfig = PostgresEnvironmentConfig(
            databaseURL: Environment.get("DATABASE_URL"),
            host: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DATABASE_USERNAME") ?? "postgres",
            password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
            database: Environment.get("DATABASE_NAME") ?? "postgres",
            tlsDisabled: Environment.get("DATABASE_TLS") != "require"
        )

        // Ejecutamos pasándole la BD dinámica por parámetro
        try await withE2EServer(
            masterConfig: masterConfig,
            configure: { app, dynamicDB in
                // MOCK de `configureTestDatabase`
                let config = PostgresEnvironmentConfig(
                    databaseURL: Environment.get("DATABASE_URL"),
                    host: Environment.get("DATABASE_HOST") ?? "localhost",
                    port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
                    username: Environment.get("DATABASE_USERNAME") ?? "postgres",
                    password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
                    // IMPORTANTE: Respetamos el override dictado por el test suite
                    database: dynamicDB,
                    tlsDisabled: Environment.get("DATABASE_TLS") != "require"
                )

                app.databases.use(try makePostgresConfiguration(from: config), as: .psql)
                app.get("ping") { _ in "pong" }
            }
        ) { client in
            // Verifica puerto efímero asignado
            #expect(client.baseURL.port != nil)
            #expect(client.baseURL.port != 8080)
            
            // Comprobación de que la red es 100% alcanzable desde el exterior TCP
            let response = try await client.get("/ping")
            #expect(response.status == 200)
            let bodyString = String(decoding: response.body, as: UTF8.self)
            #expect(bodyString == "pong")
        }
    }
}
