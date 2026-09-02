import MCP

/// A single MCP resource: a static or computed piece of context a client can read via
/// `resources/read`, identified by a URI.
///
/// Kept separate from ``MCPTool`` because resources and tools serve different purposes
/// in MCP (context vs. action). Nothing here knows about any particular business model.
public protocol MCPResource: Sendable {
    /// The resource's URI, e.g. `items://`.
    var uri: String { get }

    /// A short, human-readable name for display in MCP clients.
    var name: String { get }

    /// A description of what the resource contains.
    var resourceDescription: String? { get }

    /// The MIME type of the resource's contents.
    var mimeType: String? { get }

    /// Reads the current contents of the resource.
    ///
    /// Resources have no soft-error channel (unlike ``CallTool/Result``'s `isError`), so
    /// failures should be thrown as `MCPError` and are reported as JSON-RPC errors.
    func read() async throws -> [Resource.Content]
}

extension MCPResource {
    /// The MCP `Resource` descriptor advertised by `resources/list`.
    var descriptor: Resource {
        Resource(name: name, uri: uri, description: resourceDescription, mimeType: mimeType)
    }
}
