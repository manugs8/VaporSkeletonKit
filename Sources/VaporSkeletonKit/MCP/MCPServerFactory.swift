import MCP

/// Builds a fresh, fully-wired `MCP.Server` from a set of tools and resources.
///
/// Callers must build a new server (and a new transport) per HTTP request rather than
/// reusing one long-lived instance — see `MCPHTTPBridge` for why.
public enum MCPServerFactory {
    /// - Parameters:
    ///   - name: The name the server advertises to any client that connects.
    ///   - version: The server's version string.
    ///   - instructions: Free-text guidance shown to the connecting model about what
    ///     this server's tools/resources are for.
    ///   - tools: The tools to expose via `tools/list`/`tools/call`.
    ///   - resources: The resources to expose via `resources/list`/`resources/read`.
    public static func makeServer(
        name: String,
        version: String,
        instructions: String,
        tools: [any MCPTool],
        resources: [any MCPResource]
    ) async -> MCP.Server {
        let server = MCP.Server(
            name: name,
            version: version,
            instructions: instructions,
            capabilities: .init(
                resources: resources.isEmpty ? nil : .init(),
                tools: .init()
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools.map(\.descriptor))
        }

        await server.withMethodHandler(CallTool.self) { params in
            await MCPToolDispatch.call(params, tools: tools)
        }

        if !resources.isEmpty {
            await server.withMethodHandler(ListResources.self) { _ in
                ListResources.Result(resources: resources.map(\.descriptor))
            }

            await server.withMethodHandler(ReadResource.self) { params in
                try await MCPToolDispatch.read(params, resources: resources)
            }
        }

        return server
    }
}

/// Dispatches `tools/call` and `resources/read` requests to the matching registered
/// tool or resource by name/URI.
enum MCPToolDispatch {
    /// Routes a `tools/call` request, converting any thrown ``MCPToolError`` (or other
    /// error) into an `isError: true` result rather than a transport-level failure.
    ///
    /// An unknown tool name is the one case reported as a JSON-RPC protocol error
    /// (`invalidParams`), since that indicates a client bug rather than a recoverable
    /// domain condition.
    static func call(_ params: CallTool.Parameters, tools: [any MCPTool]) async -> CallTool.Result {
        guard let tool = tools.first(where: { $0.name == params.name }) else {
            return MCPToolError.invalidArgument("Unknown tool: \(params.name)").callToolResult
        }
        do {
            return try await tool.call(arguments: params.arguments ?? [:])
        } catch let error as MCPToolError {
            return error.callToolResult
        } catch {
            return MCPToolError.internalError(String(describing: error)).callToolResult
        }
    }

    /// Routes a `resources/read` request. Resources have no soft-error channel, so
    /// failures are thrown as `MCPError` and surfaced as JSON-RPC errors.
    static func read(
        _ params: ReadResource.Parameters,
        resources: [any MCPResource]
    ) async throws -> ReadResource.Result {
        guard let resource = resources.first(where: { $0.uri == params.uri }) else {
            throw MCPError.invalidParams("Unknown resource: \(params.uri)")
        }
        do {
            return ReadResource.Result(contents: try await resource.read())
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(String(describing: error))
        }
    }
}
