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

/// Versión exacta de `swagger-ui-dist` servida desde unpkg, junto con los hashes SRI
/// (SHA-384) de esos dos ficheros concretos — calculados a partir del contenido
/// descargado del CDN para esta versión. Fijar la versión (en vez de un rango como
/// `@5`) y el hash asegura que, aunque el CDN sirva algo distinto de lo esperado, el
/// navegador se niegue a ejecutarlo/aplicarlo en vez de cargarlo silenciosamente.
private let swaggerUIDistVersion = "5.33.0"
private let swaggerUICSSIntegrity = "sha384-Ov4/wv3j2bmct8cDc5X4ngJZohVPzEmc6uDPH8WeljUxO5vtoykvMEfbu9Vh6RaW"
private let swaggerUIBundleJSIntegrity = "sha384-YDALVcy8kj8yltLBVi1vBiBAUqdxvus673gM8XKwiy6aDUJFXivF/KCufekjYbVf"

private func swaggerUIHandler(docsTitle: String) -> Response {
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>\(docsTitle)</title>
        <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@\(swaggerUIDistVersion)/swagger-ui.css" integrity="\(swaggerUICSSIntegrity)" crossorigin="anonymous">
    </head>
    <body>
        <div id="swagger-ui"></div>
        <script src="https://unpkg.com/swagger-ui-dist@\(swaggerUIDistVersion)/swagger-ui-bundle.js" integrity="\(swaggerUIBundleJSIntegrity)" crossorigin="anonymous"></script>
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
