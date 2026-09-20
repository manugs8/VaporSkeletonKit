import Testing
import Vapor

@testable import VaporSkeletonKit

/// Ver C1/C2 en `docs/InformeDeAuditoria.md`: `registerE2EMode` no tenía ninguna
/// barrera real contra activarse en producción, pese a lo que la documentación
/// afirmaba.
@Suite("E2E Mode")
struct E2EModeTests {
    @Test("Refuses to activate when app.environment is production")
    func refusesInProduction() async throws {
        let app = try await Application.make(.production)
        do {
            #expect(throws: (any Error).self) {
                try registerE2EMode(app, sceneryFactory: StubSceneryFactory())
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Still activates (fault injection reachable) outside production")
    func activatesOutsideProduction() async throws {
        let app = try await Application.make(.testing)
        do {
            try registerE2EMode(app, sceneryFactory: StubSceneryFactory())

            try await app.testing().test(.DELETE, "_test/fault", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

private struct StubSceneryFactory: SceneryFactoryProtocol {
    func make(scenery: String) throws -> any E2Escenery {
        fatalError("No se espera invocar la factory en estos tests.")
    }
}
