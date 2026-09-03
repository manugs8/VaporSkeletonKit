import MCP

/// Una única herramienta MCP: un nombre, un esquema JSON estricto de entrada/salida y
/// un handler.
///
/// Este protocolo es el punto de conexión reutilizable entre la infraestructura MCP
/// genérica (`MCPServerFactory`, `MCPHTTPBridge`) y las herramientas propias de un
/// dominio de negocio en la app consumidora. Nada en este fichero conoce ningún modelo
/// de negocio concreto.
public protocol MCPTool: Sendable {
    /// El nombre único de la herramienta, tal y como lo envían los clientes en
    /// `tools/call`.
    var name: String { get }

    /// Un título corto y legible para mostrar en clientes MCP.
    var title: String? { get }

    /// Una descripción de lo que hace la herramienta, mostrada al modelo.
    var toolDescription: String { get }

    /// El JSON Schema que describe los argumentos esperados por la herramienta.
    var inputSchema: Value { get }

    /// El JSON Schema que describe la salida estructurada de la herramienta, si la hay.
    var outputSchema: Value? { get }

    /// Ejecuta la herramienta con los argumentos dados.
    ///
    /// Lanza ``MCPToolError`` para cualquier fallo que el llamador (un agente LLM)
    /// pueda razonablemente ver y ante el que pueda reaccionar — argumentos inválidos,
    /// no encontrado, error de base de datos o error interno. Estos se reportan de
    /// vuelta como un resultado de herramienta con `isError: true`, no como un error
    /// JSON-RPC a nivel de transporte.
    func call(arguments: [String: Value]) async throws -> CallTool.Result
}

extension MCPTool {
    /// El descriptor `Tool` de MCP anunciado por `tools/list`.
    var descriptor: Tool {
        Tool(
            name: name,
            title: title,
            description: toolDescription,
            inputSchema: inputSchema,
            outputSchema: outputSchema
        )
    }
}
