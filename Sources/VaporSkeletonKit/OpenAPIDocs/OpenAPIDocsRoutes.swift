import Foundation
import Vapor

/// Registers `GET /openapi.yaml` (serves the raw OpenAPI document driving a
/// `swift-openapi-generator`-based server) and `GET /docs` (a self-contained Swagger UI
/// page, loaded from a public CDN, pointing at it) — for import into Postman or any
/// other OpenAPI-aware tool, and for browsing the API from a browser without any extra
/// tooling.
///
/// - Parameters:
///   - app: The `Application` to register the routes on.
///   - specFilePath: Path to the OpenAPI YAML file, relative to the application's
///     working directory (e.g. `"Sources/App/openapi.yaml"`).
///   - docsTitle: The `<title>` of the Swagger UI page, e.g. `"<Project> API Docs"`.
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
