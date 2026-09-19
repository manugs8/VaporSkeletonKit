import MCP
import Vapor
import VaporTesting

/// Un fallo que indica que la ruta MCP nunca produjo una respuesta JSON-RPC decodificable.
public enum MCPTestError: Error {
    case missingResponse
}

/// Envía una única petición JSON-RPC a la ruta montada por `mountMCPServer(_:...)` y
/// decodifica la respuesta tipada — para usar en tests de integración basados en
/// `VaporTesting` contra una `Application` en proceso.
///
/// - Parameters:
///   - app: La `Application` de test sobre la que está montado el servidor MCP.
///   - request: La petición MCP tipada a enviar.
///   - path: La ruta sobre la que está montado el servidor. Por defecto, `"mcp"`,
///     igual que el valor por defecto de `mountMCPServer(_:...)`.
public func sendMCP<M: MCP.Method>(
    _ app: Application,
    _ request: MCP.Request<M>,
    path: String = "mcp"
) async throws -> MCP.Response<M> {
    var response: MCP.Response<M>?
    try await app.testing().test(
        .POST, path,
        beforeRequest: { req in
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
            try req.content.encode(request, as: .json)
        },
        afterResponse: { res async throws in
            response = try res.content.decode(MCP.Response<M>.self)
        }
    )
    guard let response else { throw MCPTestError.missingResponse }
    return response
}
