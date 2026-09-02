import MCP
import Testing

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

private struct StaticResource: MCPResource {
    var uri: String { "static://greeting" }
    var name: String { "greeting" }
    var resourceDescription: String? { "A static greeting." }
    var mimeType: String? { "text/plain" }

    func read() async throws -> [Resource.Content] {
        [.text("hello", uri: uri, mimeType: mimeType)]
    }
}

@Suite("MCP Tool/Resource Dispatch")
struct MCPServerFactoryTests {
    @Test("Dispatching a known tool call returns a successful result")
    func dispatchesKnownTool() async throws {
        let result = await MCPToolDispatch.call(
            CallTool.Parameters(name: "echo", arguments: ["text": "hi"]),
            tools: [EchoTool()]
        )
        #expect(result.isError != true)
    }

    @Test("Dispatching an unknown tool name reports isError")
    func dispatchesUnknownToolAsError() async throws {
        let result = await MCPToolDispatch.call(
            CallTool.Parameters(name: "does_not_exist", arguments: [:]),
            tools: [EchoTool()]
        )
        #expect(result.isError == true)
    }

    @Test("A thrown MCPToolError surfaces as isError rather than a transport failure")
    func toolErrorSurfacesAsIsError() async throws {
        let result = await MCPToolDispatch.call(
            CallTool.Parameters(name: "echo", arguments: [:]),
            tools: [EchoTool()]
        )
        #expect(result.isError == true)
    }

    @Test("Reading a known resource returns its contents")
    func readsKnownResource() async throws {
        let result = try await MCPToolDispatch.read(
            ReadResource.Parameters(uri: "static://greeting"),
            resources: [StaticResource()]
        )
        #expect(result.contents.first?.text == "hello")
    }

    @Test("Reading an unknown resource URI throws")
    func readingUnknownResourceThrows() async throws {
        await #expect(throws: MCPError.self) {
            _ = try await MCPToolDispatch.read(
                ReadResource.Parameters(uri: "static://missing"),
                resources: [StaticResource()]
            )
        }
    }

    @Test("makeServer builds a server from the given name/version/instructions without throwing")
    func makeServerBuildsSuccessfully() async throws {
        _ = await MCPServerFactory.makeServer(
            name: "Test Server",
            version: "0.0.1",
            instructions: "Test instructions.",
            tools: [EchoTool()],
            resources: [StaticResource()]
        )
    }
}
