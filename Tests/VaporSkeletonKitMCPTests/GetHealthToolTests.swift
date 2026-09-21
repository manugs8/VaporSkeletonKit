import Testing
import Vapor
@testable import VaporSkeletonKit
@testable import VaporSkeletonKitMCP

/// Ver V8 en `docs/InformeDeAuditoria.md`: `app.db` hace `fatalError` si no hay ninguna
/// base de datos configurada — `GetHealthTool` (como `registerHealthRoute(_:)`) ahora lo
/// comprueba antes en vez de tumbar el proceso entero por un endpoint de diagnóstico.
@Suite("Get Health Tool")
struct GetHealthToolTests {
    @Test("Reports unhealthy when no database is configured, instead of crashing")
    func unhealthyWhenNoDatabaseConfigured() async throws {
        let app = try await Application.make(.testing)
        do {
            let tool = GetHealthTool(app: app)
            let result = try await tool.call(arguments: [:])

            guard case .text(let text, _, _) = result.content.first else {
                Issue.record("Expected a text content item")
                return
            }
            #expect(text == "No database configured.")
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
