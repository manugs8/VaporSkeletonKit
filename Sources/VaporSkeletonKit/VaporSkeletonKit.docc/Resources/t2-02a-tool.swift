import MCP
import Vapor

struct ListWidgetsTool: MCPTool {
    let app: Application

    var name: String { "list_widgets" }
    var title: String? { "List Widgets" }
    var toolDescription: String { "Lists every widget currently stored." }
    var inputSchema: Value { ["type": "object", "properties": [:]] }
    var outputSchema: Value? { nil }

    func call(arguments: [String: Value]) async throws -> CallTool.Result {
        let widgets = try await Widget.query(on: app.db).all()
        let names = widgets.map(\.name).joined(separator: ", ")
        return CallTool.Result(content: [.text(text: names, annotations: nil, _meta: nil)])
    }
}
