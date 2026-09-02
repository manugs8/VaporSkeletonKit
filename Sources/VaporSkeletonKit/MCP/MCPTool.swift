import MCP

/// A single MCP tool: a name, a strict input/output JSON schema, and a handler.
///
/// This protocol is the reusable seam between generic MCP plumbing (`MCPServerFactory`,
/// `MCPHTTPBridge`) and a consuming app's own domain-specific tools. Nothing in this
/// file knows about any particular business model.
public protocol MCPTool: Sendable {
    /// The tool's unique name, as sent by clients in `tools/call`.
    var name: String { get }

    /// A short, human-readable title for display in MCP clients.
    var title: String? { get }

    /// A description of what the tool does, shown to the model.
    var toolDescription: String { get }

    /// The JSON Schema describing the tool's expected arguments.
    var inputSchema: Value { get }

    /// The JSON Schema describing the tool's structured output, if any.
    var outputSchema: Value? { get }

    /// Executes the tool with the given arguments.
    ///
    /// Throw ``MCPToolError`` for any failure the caller (an LLM agent) can reasonably
    /// see and react to — invalid arguments, not-found, database, or internal errors.
    /// These are reported back as a tool result with `isError: true`, not as a
    /// transport-level JSON-RPC error.
    func call(arguments: [String: Value]) async throws -> CallTool.Result
}

extension MCPTool {
    /// The MCP `Tool` descriptor advertised by `tools/list`.
    var descriptor: Tool {
        Tool(
            name: name,
            title: title,
            description: toolDescription,
            inputSchema: inputSchema,
            outputSchema: outputSchema
        )
    }
}
