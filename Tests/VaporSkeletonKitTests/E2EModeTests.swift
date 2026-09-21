import Foundation
import Testing
import Vapor

@testable import VaporSkeletonKit

/// Ver C1/C2 y A1/A2 en `docs/InformeDeAuditoria.md`: `registerE2EMode` no tenía
/// ninguna barrera real contra activarse en producción, pese a lo que la
/// documentación afirmaba; y `Scenery` (nombre de dominio incorrecto en inglés) se
/// renombró a `Scenario` en toda la API pública, incluido el campo JSON.
@Suite("E2E Mode")
struct E2EModeTests {
    @Test("Refuses to activate when app.environment is production")
    func refusesInProduction() async throws {
        let app = try await Application.make(.production)
        #expect(throws: E2EModeError.refusedInProduction) {
            try registerE2EMode(app, scenarioFactory: StubScenarioFactory())
        }
        try await app.asyncShutdown()
    }

    @Test("Still activates (fault injection reachable) outside production")
    func activatesOutsideProduction() async throws {
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

    /// Ver V12 en el informe de auditoría: cuando `scenarioFactory.make(scenario:)`
    /// lanza (p. ej. porque el identificador recibido no corresponde a ningún
    /// escenario conocido), Vapor lo trataba como un error interno no manejado y
    /// devolvía 500 — para un dato de entrada inválido enviado por el propio cliente,
    /// que debería ser un 400.
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
