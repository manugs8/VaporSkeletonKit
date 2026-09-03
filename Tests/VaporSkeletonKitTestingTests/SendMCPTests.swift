import MCP
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitTesting

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

@Suite("Send MCP")
struct SendMCPTests {
    @Test("Lists the mounted tools")
    func listsTools() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            let response = try await sendMCP(app, ListTools.request(id: 1, ListTools.Parameters()))

            #expect(try response.result.get().tools.map(\.name) == ["echo"])
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Calls a mounted tool and decodes its result")
    func callsTool() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            let response = try await sendMCP(
                app, CallTool.request(id: 2, CallTool.Parameters(name: "echo", arguments: ["text": "hi"])))

            let result = try response.result.get()
            #expect(result.isError != true)
            guard case .text(let text, _, _) = result.content.first else {
                Issue.record("Expected a text content item")
                return
            }
            #expect(text == "hi")
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
