import MCP

/// A domain-level failure raised by an ``MCPTool``.
///
/// Distinguishing these cases lets ``MCPToolDispatch`` report each one as a structured,
/// `isError: true` tool result the calling model can actually read and react to, instead
/// of a single generic error string.
public enum MCPToolError: Error, Sendable {
    /// The arguments passed to the tool were missing, malformed, or otherwise invalid
    /// (e.g. a non-UUID id, or an empty required field).
    case invalidArgument(String)

    /// The requested resource does not exist (e.g. no record with the given id).
    case notFound(String)

    /// The underlying database failed to complete the operation.
    case database(String)

    /// An unexpected failure occurred that doesn't fit the other cases.
    case internalError(String)

    /// A short, machine-readable label for this error case, included in structured
    /// output so callers can branch on it without parsing the message text.
    var kind: String {
        switch self {
        case .invalidArgument: return "invalid_argument"
        case .notFound: return "not_found"
        case .database: return "database_error"
        case .internalError: return "internal_error"
        }
    }

    /// The human-readable message describing this error.
    var message: String {
        switch self {
        case .invalidArgument(let message), .notFound(let message), .database(let message),
            .internalError(let message):
            return message
        }
    }

    /// Renders this error as a tool call result with `isError: true`, so the calling
    /// model sees it as a normal (if unsuccessful) tool response rather than a fatal
    /// transport error.
    var callToolResult: CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            structuredContent: .object(["error": .string(kind), "message": .string(message)]),
            isError: true
        )
    }
}
