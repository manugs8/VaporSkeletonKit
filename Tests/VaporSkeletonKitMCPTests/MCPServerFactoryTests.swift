import Foundation
import MCP
import Testing

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

private struct WriteTool: MCPTool {
    var name: String { "write" }
    var title: String? { nil }
    var toolDescription: String { "Writes something." }
    var inputSchema: Value { ["type": "object"] }
    var outputSchema: Value? { nil }
    var annotations: Tool.Annotations {
        .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
    }

    func call(arguments: [String: Value]) async throws -> CallTool.Result {
        CallTool.Result(content: [])
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

    @Test("A tool that declares annotations announces them in its descriptor")
    func descriptorCarriesAnnotations() async throws {
        let annotations = WriteTool().descriptor.annotations
        #expect(annotations.readOnlyHint == false)
        #expect(annotations.destructiveHint == false)
        #expect(annotations.idempotentHint == false)
    }

    @Test("A tool that declares none is announced without annotations")
    func descriptorWithoutAnnotationsIsEmpty() async throws {
        #expect(EchoTool().descriptor.annotations == nil)
        let json = String(decoding: try JSONEncoder().encode(EchoTool().descriptor), as: UTF8.self)
        #expect(!json.contains("annotations"))
    }

    @Test("Annotations reach the wire as part of the tool descriptor")
    func annotationsAreEncoded() async throws {
        let json = String(decoding: try JSONEncoder().encode(WriteTool().descriptor), as: UTF8.self)
        #expect(json.contains("\"readOnlyHint\":false"))
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
