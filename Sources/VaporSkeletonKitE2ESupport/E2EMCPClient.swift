import Foundation
import MCP

/// Builds a real `MCP.Client` connected over `HTTPClientTransport` — a genuine MCP
/// client talking real HTTP/JSON-RPC to a running server, the same way an external
/// agent would, rather than driving the server in-process.
public enum E2EMCPClient {
    /// Connects a fresh `MCP.Client`, attaching `Authorization: Bearer <token>` from
    /// `authToken` to every request.
    ///
    /// - Parameters:
    ///   - baseURL: The server to connect to. Defaults to ``E2EEnvironment/baseURL``.
    ///   - path: The route the MCP server is mounted on. Defaults to `"mcp"`, matching
    ///     `mountMCPServer(_:...)`'s own default.
    ///   - clientName: The name this client reports in the `initialize` handshake.
    ///   - clientVersion: The version this client reports in the `initialize` handshake.
    ///   - authenticated: Pass `false` to connect without a token, even if `authToken`
    ///     would produce one — used by "rejects unauthenticated requests" scenarios.
    ///   - authToken: Produces the bearer token attached when `authenticated` is `true`,
    ///     or `nil` to send no `Authorization` header. This function doesn't assume any
    ///     particular auth package. Defaults to never attaching a token.
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
