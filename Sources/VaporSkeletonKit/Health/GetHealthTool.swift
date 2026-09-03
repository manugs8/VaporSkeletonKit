import MCP
import Vapor

/// Checks application and database health.
///
/// Equivalent to `GET /health` (``registerHealthRoute(_:)``) — reuses the same
/// `app.healthChecker`, rather than duplicating the check.
public struct GetHealthTool: MCPTool {
    let app: Application

    public init(app: Application) {
        self.app = app
    }

    public var name: String { "get_health" }
    public var title: String? { "Get Health" }
    public var toolDescription: String {
        "Checks the health of the application and its database connection."
    }

    public var inputSchema: Value {
        ["type": "object", "properties": [:], "additionalProperties": false]
    }

    public var outputSchema: Value? {
        [
            "type": "object",
            "properties": [
                "isHealthy": ["type": "boolean"],
                "message": ["type": "string"],
            ],
            "required": ["isHealthy", "message"],
        ]
    }

    public func call(arguments: [String: Value]) async throws -> CallTool.Result {
        let status = await app.healthChecker.check(on: app.db)
        return try CallTool.Result(
            content: [.text(text: status.message, annotations: nil, _meta: nil)],
            structuredContent: status
        )
    }
}
