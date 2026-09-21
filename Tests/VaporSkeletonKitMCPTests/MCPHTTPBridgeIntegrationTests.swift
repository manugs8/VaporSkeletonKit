import MCP
import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit
@testable import VaporSkeletonKitMCP

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
        do {
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
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Initializes then calls a tool and returns its result")
    func testCallTool() async throws {
        let app = try await Application.make(.testing)
        do {
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
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Sin `do/catch` a propósito, a diferencia del resto de tests de este fichero:
    /// `#expect(throws:)` nunca deja escapar el error de su closure (registra un issue
    /// y sigue), así que nada entre `Application.make` y `asyncShutdown()` puede lanzar
    /// aquí — envolverlo en `do/catch` sería código inalcanzable (el compilador avisa).
    @Test("Refuses to mount when two tools share the same name")
    func rejectsDuplicateToolNames() async throws {
        let app = try await Application.make(.testing)
        #expect(throws: MCPServerMountError.duplicateToolName("echo")) {
            try mountMCPServer(
                app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool(), EchoTool()]
            )
        }
        try await app.asyncShutdown()
    }

    @Test("Refuses to mount when two resources share the same uri")
    func rejectsDuplicateResourceURIs() async throws {
        let app = try await Application.make(.testing)
        #expect(throws: MCPServerMountError.duplicateResourceURI("static://greeting")) {
            try mountMCPServer(
                app, name: "TestServer", version: "1.0", instructions: "", tools: [],
                resources: [StaticResource(), StaticResource()]
            )
        }
        try await app.asyncShutdown()
    }

    /// `StatelessHTTPServerTransport.handleRequest` solo entiende `POST` — `GET`/`DELETE`
    /// caen en su rama `default`, que responde `405` con `Allow: POST`, sin llegar
    /// siquiera a la validación ni al despacho JSON-RPC.
    @Test("GET responds 405 Method Not Allowed")
    func getRespondsMethodNotAllowed() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            try await app.test(.GET, "mcp") { res in
                #expect(res.status == .methodNotAllowed)
                #expect(res.headers.first(name: "Allow") == "POST")
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("DELETE responds 405 Method Not Allowed")
    func deleteRespondsMethodNotAllowed() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            try await app.test(.DELETE, "mcp") { res in
                #expect(res.status == .methodNotAllowed)
                #expect(res.headers.first(name: "Allow") == "POST")
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Mounts at a custom path instead of the \"mcp\" default")
    func mountsAtACustomPath() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(
                app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()], path: "custom-mcp"
            )

            try await app.test(.POST, "custom-mcp") { req in
                req.body = .init(string: Self.initializeRequestBody)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
            } afterResponse: { res in
                #expect(res.status == .ok)
            }

            // El default "mcp" nunca se registró — nada responde ahí.
            try await app.test(.POST, "mcp") { req in
                req.body = .init(string: Self.initializeRequestBody)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
            } afterResponse: { res in
                #expect(res.status == .notFound)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Rejects a request that doesn't accept application/json with 406")
    func rejectsMissingAcceptHeader() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            try await app.test(.POST, "mcp") { req in
                req.body = .init(string: Self.callToolRequestBody)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "text/html")
            } afterResponse: { res in
                #expect(res.status == .notAcceptable)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Rejects a Content-Type other than application/json with 415")
    func rejectsWrongContentType() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            try await app.test(.POST, "mcp") { req in
                req.body = .init(string: Self.callToolRequestBody)
                req.headers.contentType = .plainText
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
            } afterResponse: { res in
                #expect(res.status == .unsupportedMediaType)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Rejects an unsupported MCP-Protocol-Version header with 400")
    func rejectsUnsupportedProtocolVersion() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            try await app.test(.POST, "mcp") { req in
                req.body = .init(string: Self.callToolRequestBody)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
                req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "1999-01-01")
            } afterResponse: { res in
                #expect(res.status == .badRequest)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// `mountMCPServer` monta `OriginValidator.disabled` a propósito (pensado para
    /// despliegues en la nube, donde el rebinding de DNS no es una amenaza relevante) —
    /// un `Origin` que un `.localhost()` rechazaría no debe tener ningún efecto aquí.
    @Test("Doesn't reject an unrecognized Origin header — origin validation is disabled")
    func doesNotRejectOnOrigin() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(app, name: "TestServer", version: "1.0", instructions: "", tools: [EchoTool()])

            try await app.test(.POST, "mcp") { req in
                req.body = .init(string: Self.initializeRequestBody)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
                req.headers.replaceOrAdd(name: .origin, value: "http://evil.example.com")
            } afterResponse: { res in
                #expect(res.status == .ok)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Lists and reads a resource over real HTTP requests")
    func listsAndReadsResourcesOverHTTP() async throws {
        let app = try await Application.make(.testing)
        do {
            try mountMCPServer(
                app, name: "TestServer", version: "1.0", instructions: "", tools: [], resources: [StaticResource()]
            )

            try await app.test(.POST, "mcp") { req in
                let listRequest = """
                {
                    "jsonrpc": "2.0",
                    "id": "1",
                    "method": "resources/list"
                }
                """
                req.body = .init(string: listRequest)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
            } afterResponse: { res in
                #expect(res.status == .ok)

                struct ListResourcesResponse: Decodable {
                    let result: ResultBody
                    struct ResultBody: Decodable {
                        let resources: [ResourceItem]
                    }
                    struct ResourceItem: Decodable {
                        let uri: String
                        let name: String
                        let mimeType: String?
                    }
                }

                let response = try JSONDecoder().decode(ListResourcesResponse.self, from: Data(buffer: res.body))
                #expect(response.result.resources.count == 1)
                #expect(response.result.resources.first?.uri == "static://greeting")
                #expect(response.result.resources.first?.name == "greeting")
                #expect(response.result.resources.first?.mimeType == "text/plain")
            }

            try await app.test(.POST, "mcp") { req in
                let readRequest = """
                {
                    "jsonrpc": "2.0",
                    "id": "2",
                    "method": "resources/read",
                    "params": {
                        "uri": "static://greeting"
                    }
                }
                """
                req.body = .init(string: readRequest)
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: .accept, value: "application/json")
            } afterResponse: { res in
                #expect(res.status == .ok)

                struct ReadResourceResponse: Decodable {
                    let result: ResultBody
                    struct ResultBody: Decodable {
                        let contents: [ContentItem]
                    }
                    struct ContentItem: Decodable {
                        let uri: String
                        let text: String?
                    }
                }

                let response = try JSONDecoder().decode(ReadResourceResponse.self, from: Data(buffer: res.body))
                #expect(response.result.contents.count == 1)
                #expect(response.result.contents.first?.uri == "static://greeting")
                #expect(response.result.contents.first?.text == "hello")
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private static let initializeRequestBody = """
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

    private static let callToolRequestBody = """
        {
            "jsonrpc": "2.0",
            "id": "1",
            "method": "tools/call",
            "params": {
                "name": "echo",
                "arguments": {
                    "text": "hi"
                }
            }
        }
        """
}

private struct StaticResource: MCPResource {
    var uri: String { "static://greeting" }
    var name: String { "greeting" }
    var resourceDescription: String? { "A static greeting." }
    var mimeType: String? { "text/plain" }

    func read() async throws -> [Resource.Content] {
        [.text("hello", uri: uri, mimeType: mimeType)]
    }
}
