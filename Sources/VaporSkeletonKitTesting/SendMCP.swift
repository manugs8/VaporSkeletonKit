import MCP
import Vapor
import VaporTesting

/// A failure indicating the MCP route never produced a decodable JSON-RPC response.
public enum MCPTestError: Error {
    case missingResponse
}

/// Sends a single JSON-RPC request to the route mounted by `mountMCPServer(_:...)` and
/// decodes the typed response — for use in `VaporTesting`-based integration tests
/// against an in-process `Application`.
///
/// - Parameters:
///   - app: The test `Application` the MCP server is mounted on.
///   - request: The typed MCP request to send.
///   - path: The route path the server is mounted on. Defaults to `"mcp"`, matching
///     `mountMCPServer(_:...)`'s own default.
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
