import Fluent
import Foundation
import Testing
import Vapor

@testable import VaporSkeletonKit

/// `.serialized`: los tests de `reset:` migran/revierten la misma tabla
/// (`e2e_mode_reset_widgets`) contra el Postgres real y compartido de esta suite — en
/// paralelo se pisarían entre sí en `_fluent_migrations`.
@Suite("E2E Mode", .serialized)
struct E2EModeTests {
    /// La barrera es *fail-closed*: no basta con no ser `.production`. `development` es
    /// el entorno que usa Vapor cuando el proceso arranca sin `--env`, así que un
    /// despliegue de producción que olvide declararse como tal caería ahí.
    @Test(
        "Refuses to activate in any environment other than testing",
        arguments: ["production", "development", "staging"]
    )
    func refusesOutsideTesting(environmentName: String) async throws {
        let app = try await Application.make(Environment(name: environmentName))
        #expect(throws: E2EModeError.requiresTestingEnvironment(current: environmentName)) {
            try registerE2EMode(app, scenarioFactory: StubScenarioFactory())
        }
        try await app.asyncShutdown()
    }

    @Test("Activates (fault injection reachable) in the testing environment")
    func activatesInTesting() async throws {
        let app = try await Application.make(.testing)
        do {
            try registerE2EMode(app, scenarioFactory: StubScenarioFactory())

            try await app.testing().test(.DELETE, "_test/fault", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("PrepareScenarioRequest decodes the \"scenario\" JSON key")
    func decodesScenarioKey() throws {
        let json = Data(#"{"scenario":"empty_dashboard","reset":false}"#.utf8)
        let request = try JSONDecoder().decode(PrepareScenarioRequest.self, from: json)
        #expect(request.scenario == "empty_dashboard")
        #expect(request.reset == false)
    }

    @Test("POST /e2e/prepare dispatches the decoded scenario to the factory")
    func dispatchesScenarioToFactory() async throws {
        let app = try await Application.make(.testing)
        do {
            let recorder = Recorder()
            try registerE2EMode(app, scenarioFactory: RecordingScenarioFactory(recorder: recorder))

            try await app.testing().test(
                .POST, "e2e/prepare",
                beforeRequest: { req in
                    try req.content.encode(PrepareScenarioRequest(scenario: "empty_dashboard", reset: false))
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            #expect(await recorder.appliedScenario == "empty_dashboard")
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Cuando `scenarioFactory.make(scenario:)` lanza (p. ej. porque el identificador
    /// recibido no corresponde a ningún escenario conocido), es un dato de entrada
    /// inválido enviado por el propio cliente: 400, no el 500 que Vapor daría ante un
    /// error que no es `AbortError`.
    @Test("POST /e2e/prepare returns 400 (not 500) when the factory rejects an unknown scenario")
    func returns400ForUnknownScenario() async throws {
        let app = try await Application.make(.testing)
        do {
            try registerE2EMode(app, scenarioFactory: ThrowingScenarioFactory())

            try await app.testing().test(
                .POST, "e2e/prepare",
                beforeRequest: { req in
                    try req.content.encode(PrepareScenarioRequest(scenario: "no_existe", reset: false))
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// `hasRealPostgresConfigured`/`dbSkipReason`: definidos en `HealthRouteTests.swift`
    /// (mismo target) — una única política de skip para toda esta suite de tests, en
    /// vez de que cada fichero repita su propio criterio.
    @Test(
        "POST /e2e/prepare with reset:true actually truncates application tables",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
    func resetTrueTruncatesRealData() async throws {
        let app = try await Application.make(.testing)
        do {
            try configureTestDatabase(app)
            app.migrations.add(CreateWidget())
            try await app.autoMigrate()

            try await Widget(name: "before-reset").save(on: app.db)
            #expect(try await Widget.query(on: app.db).count() == 1)

            try registerE2EMode(app, scenarioFactory: RecordingScenarioFactory(recorder: Recorder()))

            try await app.testing().test(
                .POST, "e2e/prepare",
                beforeRequest: { req in
                    try req.content.encode(PrepareScenarioRequest(scenario: "empty_dashboard", reset: true))
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            #expect(try await Widget.query(on: app.db).count() == 0)

            // _fluent_migrations no se trunca (excluida explícitamente en la query
            // TRUNCATE de E2EMode.swift) — si se hubiera truncado, Fluent no sabría
            // que CreateWidget ya se aplicó y volvería a intentar el CREATE TABLE de
            // su prepare(), que lanzaría por tabla duplicada.
            try await app.autoMigrate()
        } catch {
            try? await app.autoRevert()
            try? await app.asyncShutdown()
            throw error
        }
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    @Test(
        "POST /e2e/prepare with reset:false leaves application tables untouched",
        .enabled(if: hasRealPostgresConfigured, dbSkipReason)
    )
    func resetFalseLeavesDataUntouched() async throws {
        let app = try await Application.make(.testing)
        do {
            try configureTestDatabase(app)
            app.migrations.add(CreateWidget())
            try await app.autoMigrate()

            try await Widget(name: "untouched").save(on: app.db)
            #expect(try await Widget.query(on: app.db).count() == 1)

            try registerE2EMode(app, scenarioFactory: RecordingScenarioFactory(recorder: Recorder()))

            try await app.testing().test(
                .POST, "e2e/prepare",
                beforeRequest: { req in
                    try req.content.encode(PrepareScenarioRequest(scenario: "empty_dashboard", reset: false))
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            #expect(try await Widget.query(on: app.db).count() == 1)
            #expect(try await Widget.query(on: app.db).first()?.name == "untouched")
        } catch {
            try? await app.autoRevert()
            try? await app.asyncShutdown()
            throw error
        }
        try await app.autoRevert()
        try await app.asyncShutdown()
    }
}

/// Mismos nombres de variable `DATABASE_*` que `HealthRouteTests`/`WithTestAppTests` —
/// ver el comentario de esas suites para el razonamiento completo.
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

/// Una tabla de aplicación mínima contra la que ejercitar `reset: true`/`false` —
/// cualquier modelo real serviría, lo único que importa es que viva en el schema
/// `public` junto a `_fluent_migrations`.
private final class Widget: Model, @unchecked Sendable {
    static let schema = "e2e_mode_reset_widgets"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String

    init() {}
    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

private struct CreateWidget: AsyncMigration {
    // Fluent deriva el nombre por defecto a partir del tipo — un nombre explícito es
    // obligatorio para una migración `private` (el contexto mangled no vale).
    var name: String { "CreateWidget" }

    func prepare(on database: any Database) async throws {
        try await database.schema(Widget.schema)
            .id()
            .field("name", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Widget.schema).delete()
    }
}

private struct StubScenarioFactory: E2EScenarioFactory {
    func make(scenario: String) throws -> any E2EScenario {
        fatalError("No se espera invocar la factory en estos tests.")
    }
}

private actor Recorder {
    private(set) var appliedScenario: String?
    func record(_ scenario: String) { appliedScenario = scenario }
}

private struct RecordingScenarioFactory: E2EScenarioFactory {
    let recorder: Recorder
    func make(scenario: String) throws -> any E2EScenario {
        RecordingScenario(name: scenario, recorder: recorder)
    }
}

private struct RecordingScenario: E2EScenario {
    let name: String
    let recorder: Recorder
    func apply(req: Request) async throws {
        await recorder.record(name)
    }
}

private struct UnknownScenarioNameError: Error {}

private struct ThrowingScenarioFactory: E2EScenarioFactory {
    func make(scenario: String) throws -> any E2EScenario {
        throw UnknownScenarioNameError()
    }
}
