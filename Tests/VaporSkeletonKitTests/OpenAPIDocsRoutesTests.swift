import Foundation
import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

/// Ver V9 en el informe de auditoría: `docsTitle` se interpolaba en crudo dentro del
/// `<title>` de la página Swagger UI. Un proyecto consumidor que derive ese título de
/// algo no del todo estático (nombre de entorno, configuración externa...) podía acabar
/// inyectando HTML/JS en una página servida por el propio backend.
@Suite("OpenAPI Docs Routes")
struct OpenAPIDocsRoutesTests {
    @Test("GET /docs HTML-escapes a title containing markup, instead of injecting it raw")
    func escapesMaliciousTitle() async throws {
        let app = try await Application.make(.testing)
        do {
            let maliciousTitle = "</title><script>alert(1)</script>"
            registerOpenAPIDocs(app, specData: Data(), docsTitle: maliciousTitle)

            try await app.testing().test(.GET, "docs") { res async throws in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(!body.contains("<script>alert(1)</script>"))
                #expect(body.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("GET /docs renders a plain title as-is")
    func rendersPlainTitle() async throws {
        let app = try await Application.make(.testing)
        do {
            registerOpenAPIDocs(app, specData: Data(), docsTitle: "Finance API Docs")

            try await app.testing().test(.GET, "docs") { res async throws in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("<title>Finance API Docs</title>"))
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("GET /openapi.yaml serves the given spec data unmodified")
    func servesSpecDataAsIs() async throws {
        let app = try await Application.make(.testing)
        do {
            let yaml = "openapi: 3.0.0\ninfo:\n  title: Test\n"
            registerOpenAPIDocs(app, specData: Data(yaml.utf8), docsTitle: "Docs")

            try await app.testing().test(.GET, "openapi.yaml") { res async throws in
                #expect(res.status == .ok)
                #expect(res.body.string == yaml)
                #expect(res.headers.contentType == HTTPMediaType(type: "application", subType: "yaml"))
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
