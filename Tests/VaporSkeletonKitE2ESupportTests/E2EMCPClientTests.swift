import MCP
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitE2ESupport

private struct EchoTool: MCPTool {
    var name: String { "echo" }
    var title: String? { "Echo" }
    var toolDescription: String { "Echoes back the given text." }
    var inputSchema: Value { ["type": "object", "properties": ["text": ["type": "string"]]] }
    var outputSchema: Value? { nil }

    func call(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let text)? = arguments["text"] else {
            throw MCPToolError.invalidArgument("Missing 'text' argument.")
        }
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}

private actor HeaderCapture {
    private(set) var lastAuthorization: String?
    func capture(_ value: String?) { lastAuthorization = value }
}

private struct CaptureAuthMiddleware: AsyncMiddleware {
    let capture: HeaderCapture

    func respond(to request: Vapor.Request, chainingTo next: any AsyncResponder) async throws -> Vapor.Response {
        await capture.capture(request.headers.first(name: .authorization))
        return try await next.respond(to: request)
    }
}

@Suite("E2E MCP Client")
struct E2EMCPClientTests {
    @Test("Connects and calls a mounted tool over a real HTTP round trip")
    func callsToolOverRealHTTP() async throws {
        try await withRunningServer(port: 18095, mount: mountEchoMCPServer) { baseURL in
            let client = try await E2EMCPClient.connect(baseURL: baseURL, authenticated: false)
            let result = try await client.callTool(name: "echo", arguments: ["text": "hi"])

            guard case .text(let text, _, _) = result.content.first else {
                Issue.record("Expected a text content item")
                return
            }
            #expect(text == "hi")
        }
    }

    @Test("Attaches the token produced by authToken to every request")
    func attachesAuthToken() async throws {
        let capture = HeaderCapture()

        try await withRunningServer(
            port: 18096,
            mount: { app in
                app.middleware.use(CaptureAuthMiddleware(capture: capture))
                try mountEchoMCPServer(app)
            }
        ) { baseURL in
            let client = try await E2EMCPClient.connect(baseURL: baseURL, authToken: { "abc123" })
            _ = try await client.callTool(name: "echo", arguments: ["text": "hi"])
        }

        #expect(await capture.lastAuthorization == "Bearer abc123")
    }
}

private func mountEchoMCPServer(_ app: Application) throws {
    try mountMCPServer(app, name: "TestServer", version: "1.0.0", instructions: "", tools: [EchoTool()])
}
