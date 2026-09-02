import MCP
import Vapor

/// Mounts an MCP server at `POST/GET/DELETE <path>` (`/mcp` by default), bridging
/// Vapor's HTTP types to the framework-agnostic `MCP.HTTPRequest`/`HTTPResponse` types
/// used by `StatelessHTTPServerTransport`.
///
/// This file is the only place that needs to know both "Vapor" and "MCP transport" —
/// `MCPTool`/`MCPResource`/`MCPServerFactory` don't import Vapor at all.
///
/// `Request`/`Response` are spelled out as `Vapor.Request`/`Vapor.Response` throughout
/// this file because the `MCP` module also exports generic `Request<M>`/`Response<M>`
/// JSON-RPC message types of its own, which would otherwise be ambiguous.
///
/// - Parameters:
///   - app: The `Application` to mount the route on.
///   - name: The name the MCP server advertises to any client that connects.
///   - version: The server's version string.
///   - instructions: Free-text guidance shown to the connecting model about what this
///     server's tools/resources are for.
///   - tools: The tools to expose via `tools/list`/`tools/call`.
///   - resources: The resources to expose via `resources/list`/`resources/read`.
///   - path: The route path to mount the server on. Defaults to `"mcp"`.
public func mountMCPServer(
    _ app: Application,
    name: String,
    version: String,
    instructions: String,
    tools: [any MCPTool],
    resources: [any MCPResource] = [],
    path: PathComponent = "mcp"
) throws {
    let handler: (@Sendable (Vapor.Request) async throws -> Vapor.Response) = { req in
        try await handleMCPRequest(
            req, name: name, version: version, instructions: instructions, tools: tools, resources: resources)
    }
    for method in [Vapor.HTTPMethod.GET, .POST, .DELETE] {
        app.on(method, path, body: .collect, use: handler)
    }

    app.logger.info(
        "MCP server mounted at /\(path.description)",
        metadata: ["tools": .array(tools.map { .string($0.name) })]
    )
}

/// Handles a single HTTP request against the MCP route by spinning up a fresh, isolated
/// `MCP.Server` + `StatelessHTTPServerTransport` pair, running the request through it,
/// and tearing it back down.
///
/// A single long-lived `MCP.Server` cannot be reused across independent MCP clients in
/// stateless mode: the SDK rejects a second `initialize` call on an already-initialized
/// server, and stateless mode carries no session id to tell clients apart. Building a new
/// (cheap, in-memory) server per request keeps every request fully isolated, which is the
/// correct pattern for a stateless transport serving multiple, unrelated remote clients.
private func handleMCPRequest(
    _ req: Vapor.Request,
    name: String,
    version: String,
    instructions: String,
    tools: [any MCPTool],
    resources: [any MCPResource]
) async throws -> Vapor.Response {
    let mcpRequest = MCP.HTTPRequest(vaporRequest: req)

    // Authentication (if any) happens one layer up, in whatever middleware the caller
    // attaches to `app` before calling `mountMCPServer` — shared with the rest of the
    // app instead of MCP having its own separate check — rather than through the MCP
    // SDK's own `HTTPRequestValidator` pipeline: that pipeline is synchronous, but
    // verifying a bearer token against a remote JWKS is inherently asynchronous, and
    // Vapor's middleware chain already runs (and can reject the request) before this
    // handler is ever invoked.
    let validators: [any HTTPRequestValidator] = [
        OriginValidator.disabled,
        AcceptHeaderValidator(mode: .jsonOnly),
        ContentTypeValidator(),
        ProtocolVersionValidator(),
    ]

    let transport = StatelessHTTPServerTransport(
        validationPipeline: StandardValidationPipeline(validators: validators),
        logger: req.logger
    )
    let server = await MCPServerFactory.makeServer(
        name: name, version: version, instructions: instructions, tools: tools, resources: resources)

    try await server.start(transport: transport)
    let mcpResponse = await transport.handleRequest(mcpRequest)
    await server.stop()

    return mcpResponse.vaporResponse()
}

extension MCP.HTTPRequest {
    /// Converts a Vapor request into the framework-agnostic request type the MCP
    /// transport expects. Assumes the route was registered with `body: .collect` so the
    /// full body is already buffered and synchronously available.
    fileprivate init(vaporRequest req: Vapor.Request) {
        var headers: [String: String] = [:]
        for (name, value) in req.headers {
            // Case-insensitive lookup is handled by `HTTPRequest.header(_:)`; first
            // occurrence wins, matching how the validators only ever read single-value
            // headers (Accept, Content-Type, Authorization, session id, etc).
            if headers[name] == nil {
                headers[name] = value
            }
        }

        let body = req.body.data.map { Data(buffer: $0) }

        self.init(
            method: req.method.rawValue,
            headers: headers,
            body: body,
            path: req.url.path
        )
    }
}

extension MCP.HTTPResponse {
    /// Converts an MCP transport response into a Vapor `Response`.
    fileprivate func vaporResponse() -> Vapor.Response {
        let status = Vapor.HTTPResponseStatus(statusCode: statusCode)
        var vaporHeaders = Vapor.HTTPHeaders()
        for (name, value) in headers {
            vaporHeaders.add(name: name, value: value)
        }

        switch self {
        case .accepted, .ok:
            return Vapor.Response(status: status, headers: vaporHeaders)
        case .data(let data, _):
            return Vapor.Response(status: status, headers: vaporHeaders, body: .init(data: data))
        case .error:
            return Vapor.Response(
                status: status, headers: vaporHeaders, body: .init(data: bodyData ?? Data()))
        case .stream(let stream, _):
            let body = Vapor.Response.Body(stream: { writer in
                Task {
                    do {
                        for try await chunk in stream {
                            try await writer.write(.buffer(.init(data: chunk))).get()
                        }
                        try await writer.write(.end).get()
                    } catch {
                        try? await writer.write(.error(error)).get()
                    }
                }
            })
            return Vapor.Response(status: status, headers: vaporHeaders, body: body)
        }
    }
}
