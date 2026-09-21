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
///   - specData: Los datos del fichero YAML de OpenAPI (ej. obtenidos de un paquete
///     externo que lo expone como `Data`).
///   - docsTitle: El `<title>` de la página Swagger UI, p. ej. `"<Proyecto> API Docs"`.
public func registerOpenAPIDocs(_ app: Application, specData: Data, docsTitle: String) {
    app.get("openapi.yaml") { _ in
        openAPISpecHandler(specData: specData)
    }
    app.get("docs") { _ in
        swaggerUIHandler(docsTitle: docsTitle)
    }
}

private func openAPISpecHandler(specData: Data) -> Response {
    var headers = HTTPHeaders()
    headers.contentType = .init(type: "application", subType: "yaml")
    let body = Response.Body(buffer: ByteBuffer(data: specData))
    return Response(status: .ok, headers: headers, body: body)
}

private func swaggerUIHandler(docsTitle: String) -> Response {
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>\(htmlEscaped(docsTitle))</title>
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

/// Escapa los caracteres con significado especial en HTML para que `text` pueda
/// interpolarse en el cuerpo de una página sin que un `docsTitle` con `<`, `>`, `&`
/// o comillas rompa la estructura del documento o inyecte markup/JS.
private func htmlEscaped(_ text: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(text.count)
    for character in text {
        switch character {
        case "&": escaped += "&amp;"
        case "<": escaped += "&lt;"
        case ">": escaped += "&gt;"
        case "\"": escaped += "&quot;"
        case "'": escaped += "&#39;"
        default: escaped.append(character)
        }
    }
    return escaped
}
