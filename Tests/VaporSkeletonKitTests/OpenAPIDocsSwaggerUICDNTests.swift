import Foundation
import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

/// Sin una versión exacta ni un hash de integridad (SRI), un cambio en el CDN — o un
/// CDN comprometido — podría servir JS distinto sin que el navegador lo rechazara.
/// `swaggerUIHandler` fija una versión exacta y añade `integrity`/`crossorigin` a los
/// dos recursos cargados desde el CDN.
@Suite("OpenAPI Docs Swagger UI CDN")
struct OpenAPIDocsSwaggerUICDNTests {
    @Test("The CSS and JS CDN tags pin an exact version and carry a matching SRI hash")
    func pinsVersionAndSRI() async throws {
        let app = try await Application.make(.testing)
        do {
            registerOpenAPIDocs(app, specData: Data(), docsTitle: "Docs")

            try await app.testing().test(.GET, "docs") { res async throws in
                #expect(res.status == .ok)
                let body = res.body.string

                // Versión exacta fijada, no un rango como "@5".
                #expect(body.contains("swagger-ui-dist@5.33.0/swagger-ui.css"))
                #expect(body.contains("swagger-ui-dist@5.33.0/swagger-ui-bundle.js"))
                #expect(!body.contains("swagger-ui-dist@5/"))

                // Hashes SHA-384 reales de esos ficheros exactos (calculados en la
                // documentación de este PR a partir del contenido descargado del CDN).
                #expect(body.contains(
                    "integrity=\"sha384-Ov4/wv3j2bmct8cDc5X4ngJZohVPzEmc6uDPH8WeljUxO5vtoykvMEfbu9Vh6RaW\""
                ))
                #expect(body.contains(
                    "integrity=\"sha384-YDALVcy8kj8yltLBVi1vBiBAUqdxvus673gM8XKwiy6aDUJFXivF/KCufekjYbVf\""
                ))
                #expect(body.contains("crossorigin=\"anonymous\""))
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
