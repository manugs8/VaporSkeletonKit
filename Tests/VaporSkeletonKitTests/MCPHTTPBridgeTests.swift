import MCP
import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

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

@Suite("MCP HTTP Bridge Tests")
struct MCPHTTPBridgeTests {
    @Test("Mounts route and responds to requests")
    func testMountRoute() async throws {
        let app = try await Application.make(.testing)
        
        try mountMCPServer(
            app,
            name: "TestServer",
            version: "1.0",
            instructions: "Testing instructions",
            tools: [EchoTool()]
        )
        
        try await app.test(.POST, "mcp") { req in
            let initRequest = """
            {
                "jsonrpc": "2.0",
                "id": "1",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "test-client",
                        "version": "1.0"
                    }
                }
            }
            """
            req.body = .init(string: initRequest)
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
        } afterResponse: { res in
            #expect(res.status == .ok)
            let body = res.body.string
            #expect(body.contains("protocolVersion"))
            #expect(body.contains("2024-11-05"))
        }
        
        try await app.asyncShutdown()
    }
}
