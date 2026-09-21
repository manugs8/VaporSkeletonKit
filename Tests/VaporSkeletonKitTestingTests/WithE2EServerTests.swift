import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitE2ESupport
import VaporSkeletonKitTesting

@Suite("With E2E Server (Dynamic Database)")
struct WithE2EServerTests {
    @Test(
        "Arranca el servidor en un puerto efímero aislado y con BD generada dinámicamente UUID",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
    func bindsEphemeralPortAndUsesDynamicDatabase() async throws {
        // Ejecutamos pasándole la BD dinámica por parámetro
        try await withE2EServer(
            masterConfig: testMasterConfig(),
            configure: { app, dynamicDB in
                app.databases.use(try makePostgresConfiguration(from: testMasterConfig(database: dynamicDB)), as: .psql)
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

    /// Lo que justifica que `withE2EServer` exista: que la BD dinámica se elimina de
    /// verdad, en éxito y en fallo.
    @Test(
        "Drops the ephemeral database once the test body finishes successfully",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
    func dropsDatabaseOnSuccess() async throws {
        var capturedDatabaseName = ""
        try await withE2EServer(
            masterConfig: testMasterConfig(),
            configure: { app, dynamicDB in
                capturedDatabaseName = dynamicDB
                app.get("ping") { _ in "pong" }
            }
        ) { client in
            _ = try await client.get("/ping")
        }

        #expect(!capturedDatabaseName.isEmpty)
        let stillExists = try await databaseExists(capturedDatabaseName)
        #expect(!stillExists)
    }

    @Test(
        "Drops the ephemeral database even when the test body throws",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
    func dropsDatabaseOnFailure() async throws {
        struct BoomError: Error {}
        var capturedDatabaseName = ""

        await #expect(throws: BoomError.self) {
            try await withE2EServer(
                masterConfig: testMasterConfig(),
                configure: { app, dynamicDB in
                    capturedDatabaseName = dynamicDB
                    app.get("ping") { _ in "pong" }
                }
            ) { _ in
                throw BoomError()
            }
        }

        #expect(!capturedDatabaseName.isEmpty)
        let stillExists = try await databaseExists(capturedDatabaseName)
        #expect(!stillExists)
    }

    /// Sin guard a propósito: no necesita ningún Postgres, sino justo lo contrario — uno
    /// inalcanzable. Si `CREATE DATABASE` falla, `withE2EServer` debe propagar el error
    /// (apagando la `Application` ya creada) sin llegar a invocar `configure` ni `test`.
    @Test("Propagates a failure to create the ephemeral database, without running configure or test")
    func propagatesDatabaseCreationFailure() async throws {
        var configureRan = false
        var testRan = false
        let unreachableMaster = PostgresEnvironmentConfig(
            databaseURL: nil, host: "127.0.0.1", port: 1, username: "postgres", password: "postgres",
            database: "postgres", tlsDisabled: true
        )

        await #expect(throws: (any Error).self) {
            try await withE2EServer(
                masterConfig: unreachableMaster,
                configure: { _, _ in configureRan = true }
            ) { _ in
                testRan = true
            }
        }

        #expect(!configureRan)
        #expect(!testRan)
    }

    /// Dos invocaciones concurrentes reciben cada una su propia base de datos (vía
    /// UUID) y su propio puerto (vía `port: 0`) — insertar en una no debe ser visible
    /// desde la otra, y ambas deben completarse sin pisarse.
    @Test(
        "Two concurrent invocations get fully isolated databases and ports",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
    func isolatesConcurrentInvocations() async throws {
        async let first = runIsolatedInsertAndCount(label: "first")
        async let second = runIsolatedInsertAndCount(label: "second")
        let (firstResult, secondResult) = try await (first, second)

        // Cada servidor solo ve su propia fila — si ambos hubieran acabado
        // compartiendo la misma base de datos (p. ej. una colisión de UUID, o
        // `dynamicDB` ignorado), alguno de los dos vería 2 en vez de 1.
        #expect(firstResult.count == 1)
        #expect(secondResult.count == 1)
        #expect(firstResult.port != secondResult.port)
    }
}

private func runIsolatedInsertAndCount(label: String) async throws -> (port: Int, count: Int) {
    var port = 0
    var count = 0
    try await withE2EServer(
        masterConfig: testMasterConfig(),
        configure: { app, dynamicDB in
            app.databases.use(try makePostgresConfiguration(from: testMasterConfig(database: dynamicDB)), as: .psql)
            app.migrations.add(CreateIsolationMarker())
            app.post("marker") { req async throws -> HTTPStatus in
                try await IsolationMarker(label: label).save(on: req.db)
                return .ok
            }
            app.get("marker-count") { req async throws -> CountResponse in
                CountResponse(count: try await IsolationMarker.query(on: req.db).count())
            }
        }
    ) { client in
        port = client.baseURL.port ?? 0
        try await client.post("marker")
        count = try await client.get("marker-count", as: CountResponse.self).count
    }
    return (port, count)
}

private struct CountResponse: Content {
    let count: Int
}

private final class IsolationMarker: Model, @unchecked Sendable {
    static let schema = "e2e_server_isolation_markers"

    @ID(key: .id) var id: UUID?
    @Field(key: "label") var label: String

    init() {}
    init(id: UUID? = nil, label: String) {
        self.id = id
        self.label = label
    }
}

private struct CreateIsolationMarker: AsyncMigration {
    var name: String { "CreateIsolationMarker" }

    func prepare(on database: any Database) async throws {
        try await database.schema(IsolationMarker.schema)
            .id()
            .field("label", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(IsolationMarker.schema).delete()
    }
}

/// Política de skip unificada para toda suite de este target que necesite un Postgres
/// real (aquí y en `WithTestAppTests.swift`). `.enabled(if:)` (en vez de un
/// `guard ... else { return }` dentro del test) hace que Swift Testing reporte estos
/// tests como *skipped* en vez de como un verde engañoso.
let hasRealPostgresConfigured =
    ProcessInfo.processInfo.environment["CI"] == "true" || ProcessInfo.processInfo.environment["DATABASE_URL"] != nil

let dbSkipReason: Comment = "Requires a real Postgres connection (set CI=true or DATABASE_URL)."

/// MOCK de las credenciales máster que en un consumidor real vendrían de su propio
/// `.env.local`/`.env` (ver `PostgresEnvironmentConfig`: esta función nunca lee
/// `Environment` por sí misma, es el llamador quien las resuelve). `database:` permite
/// reusar esta misma función para construir tanto la config máster (`CREATE`/`DROP
/// DATABASE`) como la de la app contra la BD dinámica ya aprovisionada.
private func testMasterConfig(database: String? = nil) -> PostgresEnvironmentConfig {
    PostgresEnvironmentConfig(
        databaseURL: Environment.get("DATABASE_URL"),
        host: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
        username: Environment.get("DATABASE_USERNAME") ?? "postgres",
        password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
        database: database ?? Environment.get("DATABASE_NAME") ?? "postgres",
        tlsDisabled: Environment.get("DATABASE_TLS") != "require"
    )
}

/// `withE2EServer` (`WithE2EApp.swift`) no expone ningún modo de comprobar si la BD
/// dinámica sigue existiendo — se conecta directamente, con las mismas credenciales
/// máster, para preguntárselo a `pg_database`.
private func databaseExists(_ name: String) async throws -> Bool {
    let adminApp = try await Application.make(.testing)
    adminApp.databases.use(try makePostgresConfiguration(from: testMasterConfig()), as: .psql)
    do {
        guard let sql = adminApp.db as? any SQLDatabase else {
            fatalError("Expected app.db to resolve as a SQLDatabase.")
        }
        let rows = try await sql.raw("SELECT 1 FROM pg_database WHERE datname = \(bind: name)").all()
        try await adminApp.asyncShutdown()
        return !rows.isEmpty
    } catch {
        try? await adminApp.asyncShutdown()
        throw error
    }
}
