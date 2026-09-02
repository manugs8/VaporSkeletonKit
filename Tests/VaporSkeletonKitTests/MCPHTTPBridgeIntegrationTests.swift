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

@Suite("MCP HTTP Bridge Integration Tests")
struct MCPHTTPBridgeIntegrationTests {
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
            
            struct InitializeResponse: Decodable {
                let jsonrpc: String
                let id: String
                let result: ResultBody
                
                struct ResultBody: Decodable {
                    let protocolVersion: String
                    let serverInfo: ServerInfo
                }
                
                struct ServerInfo: Decodable {
                    let name: String
                    let version: String
                }
            }
            
            let data = Data(buffer: res.body)
            let response = try JSONDecoder().decode(InitializeResponse.self, from: data)
            
            #expect(response.jsonrpc == "2.0")
            #expect(response.id == "1")
            #expect(response.result.protocolVersion == "2024-11-05")
            #expect(response.result.serverInfo.name == "TestServer")
            #expect(response.result.serverInfo.version == "1.0")
        }
        
        try await app.asyncShutdown()
    }

    @Test("Initializes then calls a tool and returns its result")
    func testCallTool() async throws {
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
        }

        try await app.test(.POST, "mcp") { req in
            let callRequest = """
            {
                "jsonrpc": "2.0",
                "id": "2",
                "method": "tools/call",
                "params": {
                    "name": "echo",
                    "arguments": {
                        "text": "Hello, MCP!"
                    }
                }
            }
            """
            req.body = .init(string: callRequest)
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
        } afterResponse: { res in
            #expect(res.status == .ok)

            struct CallToolResponse: Decodable {
                let jsonrpc: String
                let id: String
                let result: ResultBody

                struct ResultBody: Decodable {
                    let content: [ContentItem]
                }

                struct ContentItem: Decodable {
                    let type: String
                    let text: String
                }
            }

            let data = Data(buffer: res.body)
            let response = try JSONDecoder().decode(CallToolResponse.self, from: data)

            #expect(response.jsonrpc == "2.0")
            #expect(response.id == "2")
            #expect(response.result.content.count == 1)
            #expect(response.result.content.first?.type == "text")
            #expect(response.result.content.first?.text == "Hello, MCP!")
        }

        try await app.asyncShutdown()
    }
}
