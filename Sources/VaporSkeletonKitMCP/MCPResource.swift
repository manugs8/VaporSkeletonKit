import MCP

/// Un único recurso MCP: un contenido estático o calculado que un cliente puede leer
/// mediante `resources/read`, identificado por una URI.
///
/// Se mantiene separado de ``MCPTool`` porque los recursos y las herramientas cumplen
/// propósitos distintos en MCP (contexto frente a acción). Nada aquí conoce ningún
/// modelo de negocio concreto.
public protocol MCPResource: Sendable {
    /// La URI del recurso, p. ej. `items://`.
    var uri: String { get }

    /// Un nombre corto y legible para mostrar en clientes MCP.
    var name: String { get }

    /// Una descripción de lo que contiene el recurso.
    var resourceDescription: String? { get }

    /// El tipo MIME del contenido del recurso.
    var mimeType: String? { get }

    /// Lee el contenido actual del recurso.
    ///
    /// Los recursos no tienen un canal de error "suave" (a diferencia del `isError` de
    /// `CallTool.Result`), así que los fallos deben lanzarse como `MCPError` y se
    /// reportan como errores JSON-RPC.
    func read() async throws -> [Resource.Content]
}

extension MCPResource {
    /// El descriptor `Resource` de MCP anunciado por `resources/list`.
    var descriptor: Resource {
        Resource(name: name, uri: uri, description: resourceDescription, mimeType: mimeType)
    }
}
