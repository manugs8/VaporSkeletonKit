import MCP

/// Construye un `MCP.Server` nuevo y completamente configurado a partir de un conjunto
/// de herramientas y recursos.
///
/// Los llamadores deben construir un servidor nuevo (y un transporte nuevo) por cada
/// petición HTTP en lugar de reutilizar una única instancia de larga duración — ver
/// `MCPHTTPBridge` para el motivo.
public enum MCPServerFactory {
    /// - Parameters:
    ///   - name: El nombre que el servidor anuncia a cualquier cliente que se conecte.
    ///   - version: La cadena de versión del servidor.
    ///   - instructions: Guía en texto libre mostrada al modelo conectado sobre para
    ///     qué sirven las herramientas/recursos de este servidor.
    ///   - tools: Las herramientas a exponer vía `tools/list`/`tools/call`.
    ///   - resources: Los recursos a exponer vía `resources/list`/`resources/read`.
    public static func makeServer(
        name: String,
        version: String,
        instructions: String,
        tools: [any MCPTool],
        resources: [any MCPResource]
    ) async -> MCP.Server {
        let server = MCP.Server(
            name: name,
            version: version,
            instructions: instructions,
            capabilities: .init(
                resources: resources.isEmpty ? nil : .init(),
                tools: .init()
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools.map(\.descriptor))
        }

        await server.withMethodHandler(CallTool.self) { params in
            await MCPToolDispatch.call(params, tools: tools)
        }

        if !resources.isEmpty {
            await server.withMethodHandler(ListResources.self) { _ in
                ListResources.Result(resources: resources.map(\.descriptor))
            }

            await server.withMethodHandler(ReadResource.self) { params in
                try await MCPToolDispatch.read(params, resources: resources)
            }
        }

        return server
    }
}

/// Despacha peticiones `tools/call` y `resources/read` a la herramienta o recurso
/// registrado que coincida por nombre/URI.
enum MCPToolDispatch {
    /// Enruta una petición `tools/call`, convirtiendo cualquier ``MCPToolError``
    /// lanzado (u otro error) en un resultado con `isError: true` en lugar de un fallo
    /// a nivel de transporte.
    ///
    /// Un nombre de herramienta desconocido es el único caso que se reporta como un
    /// error de protocolo JSON-RPC (`invalidParams`), ya que eso indica un fallo del
    /// cliente y no una condición de dominio recuperable.
    static func call(_ params: CallTool.Parameters, tools: [any MCPTool]) async -> CallTool.Result {
        guard let tool = tools.first(where: { $0.name == params.name }) else {
            return MCPToolError.invalidArgument("Unknown tool: \(params.name)").callToolResult
        }
        do {
            return try await tool.call(arguments: params.arguments ?? [:])
        } catch let error as MCPToolError {
            return error.callToolResult
        } catch {
            return MCPToolError.internalError(String(describing: error)).callToolResult
        }
    }

    /// Enruta una petición `resources/read`. Los recursos no tienen un canal de error
    /// "suave", así que los fallos se lanzan como `MCPError` y se muestran como errores
    /// JSON-RPC.
    static func read(
        _ params: ReadResource.Parameters,
        resources: [any MCPResource]
    ) async throws -> ReadResource.Result {
        guard let resource = resources.first(where: { $0.uri == params.uri }) else {
            throw MCPError.invalidParams("Unknown resource: \(params.uri)")
        }
        do {
            return ReadResource.Result(contents: try await resource.read())
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(String(describing: error))
        }
    }
}
