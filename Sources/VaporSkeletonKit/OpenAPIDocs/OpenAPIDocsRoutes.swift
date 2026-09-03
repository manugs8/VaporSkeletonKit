import Foundation
import Vapor

/// Registra `GET /openapi.yaml` (sirve el documento OpenAPI en crudo que impulsa un
/// servidor basado en `swift-openapi-generator`) y `GET /docs` (una página Swagger UI
/// autocontenida, cargada desde un CDN público, que apunta a él) — para importar en
/// Postman o cualquier otra herramienta compatible con OpenAPI, y para explorar la API
/// desde un navegador sin ninguna herramienta adicional.
///
/// - Parameters:
///   - app: La `Application` sobre la que registrar las rutas.
///   - specFilePath: Ruta al fichero YAML de OpenAPI, relativa al directorio de trabajo
///     de la aplicación (p. ej. `"Sources/App/openapi.yaml"`).
///   - docsTitle: El `<title>` de la página Swagger UI, p. ej. `"<Proyecto> API Docs"`.
public func registerOpenAPIDocs(_ app: Application, specFilePath: String, docsTitle: String) {
    app.get("openapi.yaml") { req in
        try await openAPISpecHandler(req, specFilePath: specFilePath)
    }
    app.get("docs") { _ in
        swaggerUIHandler(docsTitle: docsTitle)
    }
}

@Sendable
private func openAPISpecHandler(_ req: Request, specFilePath: String) async throws -> Response {
    let path = req.application.directory.workingDirectory + specFilePath
    guard FileManager.default.fileExists(atPath: path) else {
        throw Abort(.notFound)
    }
    return try await req.fileio.asyncStreamFile(at: path, mediaType: .init(type: "application", subType: "yaml"))
}

private func swaggerUIHandler(docsTitle: String) -> Response {
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>\(docsTitle)</title>
        <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
    </head>
    <body>
        <div id="swagger-ui"></div>
        <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
        <script>
            window.onload = () => {
                window.ui = SwaggerUIBundle({
                    url: "/openapi.yaml",
                    dom_id: "#swagger-ui"
                });
            };
        </script>
    </body>
    </html>
    """
    return Response(status: .ok, headers: ["content-type": "text/html; charset=utf-8"], body: .init(string: html))
}
