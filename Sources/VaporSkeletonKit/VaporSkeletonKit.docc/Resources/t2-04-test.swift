import MCP
import Testing
import Vapor
import VaporSkeletonKitTesting

@testable import App

@Suite("List Widgets Tool")
struct ListWidgetsToolTests {
    @Test("Lists the widgets currently stored")
    func listsWidgets() async throws {
        try await withTestApp(configure: configure) { app in
            let response = try await sendMCP(
                app, CallTool.request(id: 1, CallTool.Parameters(name: "list_widgets", arguments: [:])))

            let result = try response.result.get()
            #expect(result.isError != true)
        }
    }
}
