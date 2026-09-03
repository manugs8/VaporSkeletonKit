import Foundation
import MCP

/// Construye un `MCP.Client` real conectado sobre `HTTPClientTransport` — un cliente
/// MCP genuino que habla HTTP/JSON-RPC real con un servidor en ejecución, de la misma
/// forma en que lo haría un agente externo, en lugar de manejar el servidor en proceso.
public enum E2EMCPClient {
    /// Conecta un `MCP.Client` nuevo, adjuntando `Authorization: Bearer <token>` desde
    /// `authToken` en cada petición.
    ///
    /// - Parameters:
    ///   - baseURL: El servidor al que conectar. Por defecto, ``E2EEnvironment/baseURL``.
    ///   - path: La ruta sobre la que está montado el servidor MCP. Por defecto,
    ///     `"mcp"`, igual que el valor por defecto de `mountMCPServer(_:...)`.
    ///   - clientName: El nombre que este cliente reporta en el handshake `initialize`.
    ///   - clientVersion: La versión que este cliente reporta en el handshake
    ///     `initialize`.
    ///   - authenticated: Pasa `false` para conectar sin token, incluso si `authToken`
    ///     produciría uno — usado por los escenarios que verifican que se rechazan las
    ///     peticiones no autenticadas.
    ///   - authToken: Produce el bearer token que se adjunta cuando `authenticated` es
    ///     `true`, o `nil` para no enviar ninguna cabecera `Authorization`. Esta función
    ///     no asume ningún paquete de autenticación en concreto. Por defecto, nunca
    ///     adjunta ningún token.
    public static func connect(
        baseURL: URL = E2EEnvironment.baseURL,
        path: String = "mcp",
        clientName: String = "E2ETests",
        clientVersion: String = "1.0.0",
        authenticated: Bool = true,
        authToken: @Sendable () async throws -> String? = { nil }
    ) async throws -> Client {
        let token = authenticated ? try await authToken() : nil
        let transport = HTTPClientTransport(
            endpoint: baseURL.appendingPathComponent(path),
            streaming: false,
            requestModifier: { request in
                guard let token else { return request }
                var request = request
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }
        )
        let client = Client(name: clientName, version: clientVersion)
        _ = try await client.connect(transport: transport)
        return client
    }
}
