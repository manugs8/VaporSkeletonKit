# Servidor MCP

El puente entre Vapor y el SDK de MCP: por qué se crea un `MCP.Server` nuevo en cada
petición, y cómo un `MCPToolError` llega al modelo sin tumbar la petición.

## El problema: MCP stateless sobre HTTP normal

[MCP](https://modelcontextprotocol.io) (Model Context Protocol) define cómo un agente
LLM descubre y llama herramientas expuestas por un servidor. El SDK oficial de Swift
(`swift-sdk`) trae su propio transporte HTTP, pero está pensado para un servidor
dedicado a MCP — no para convivir con las rutas REST normales de una `Application` de
Vapor ya existente, compartiendo la misma autenticación.

`mountMCPServer(_:name:version:instructions:tools:resources:path:)` resuelve esa
integración: monta `POST/GET/DELETE /mcp` (o el `path` que se le indique) sobre `app`,
convirtiendo entre los tipos HTTP de Vapor y los tipos `MCP.HTTPRequest`/`HTTPResponse`
agnósticos de framework que espera `StatelessHTTPServerTransport`.

## Un servidor nuevo por petición, no uno compartido

La decisión de diseño menos obvia de todo este kit: cada petición HTTP a `/mcp`
construye un `MCP.Server` **completamente nuevo**, lo usa una vez, y lo destruye.

![Ciclo de vida de una petición tools/call, desde el cliente MCP hasta la herramienta y de vuelta, mostrando que MCPHTTPBridge crea un MCP.Server y un StatelessHTTPServerTransport nuevos en cada petición.](flujo-peticion-mcp)

El motivo no es estilístico: el modo *stateless* del SDK de MCP **rechaza una segunda
llamada `initialize`** sobre un servidor ya inicializado, y ese modo no lleva ningún id
de sesión que permita distinguir entre clientes independientes conectados al mismo
servidor. Un único `MCP.Server` de larga duración, compartido entre peticiones, no
podría atender a un segundo cliente MCP una vez que el primero ya lo hubiera
inicializado. Construir un servidor nuevo (barato, en memoria, sin estado que
persista) por petición mantiene cada petición completamente aislada — el patrón
correcto para un transporte stateless sirviendo a múltiples clientes remotos sin
relación entre sí.

```swift
private func handleMCPRequest(_ req: Vapor.Request, /* ... */) async throws -> Vapor.Response {
    let mcpRequest = MCP.HTTPRequest(vaporRequest: req)
    let transport = StatelessHTTPServerTransport(/* ... */)
    let server = await MCPServerFactory.makeServer(/* ... */)

    try await server.start(transport: transport)
    let mcpResponse = await transport.handleRequest(mcpRequest)
    await server.stop()

    return mcpResponse.vaporResponse()
}
```

## Dos protocolos, cero conocimiento del dominio

``MCPTool`` y ``MCPResource`` son el único punto de conexión entre la infraestructura
MCP genérica de este kit y las herramientas propias de cada proyecto. Ninguno de los dos
protocolos, ni el código de `MCPServerFactory`/`MCPHTTPBridge` que los despacha, conoce
ningún modelo de negocio concreto:

```swift
public protocol MCPTool: Sendable {
    var name: String { get }
    var title: String? { get }
    var toolDescription: String { get }
    var inputSchema: Value { get }
    var outputSchema: Value? { get }
    func call(arguments: [String: Value]) async throws -> CallTool.Result
}
```

``GetHealthTool`` (ver <doc:ComprobacionesDeSalud>) es el único `MCPTool` que trae este
kit — todo lo demás lo implementa el proyecto consumidor para su propio dominio.

## `MCPToolError`: el canal de error que un modelo puede leer

Cuando una herramienta falla, hay dos formas de comunicarlo: un error de protocolo
JSON-RPC (que rompe la petición a nivel de transporte) o un resultado de herramienta con
`isError: true` (que el modelo recibe como una respuesta normal, aunque sin éxito, y
puede leer y ante la que puede reaccionar). ``MCPToolError`` es el segundo camino:

```swift
public enum MCPToolError: Error, Sendable {
    case invalidArgument(String)
    case notFound(String)
    case database(String)
    case internalError(String)
}
```

`MCPToolDispatch.call(_:tools:)` atrapa cualquier `MCPToolError` lanzado por
`tool.call(arguments:)` y lo convierte en ese resultado estructurado, incluyendo un
`kind` legible por máquina (`"invalid_argument"`, `"not_found"`, ...) además del mensaje,
para que el modelo llamador pueda bifurcar su lógica sin tener que parsear texto:

```swift
var callToolResult: CallTool.Result {
    CallTool.Result(
        content: [.text(text: message, annotations: nil, _meta: nil)],
        structuredContent: .object(["error": .string(kind), "message": .string(message)]),
        isError: true
    )
}
```

El único caso que **sí** se reporta como error de protocolo (`invalidParams`) es un
nombre de herramienta desconocido — eso indica un fallo del propio cliente (está
llamando a una herramienta que nunca se registró), no una condición de dominio de la que
el modelo pueda recuperarse cambiando sus argumentos.

Los recursos (``MCPResource``) no tienen ese canal de error "suave": al no representar
una acción sino contexto de solo lectura, un fallo al leerlos se lanza como `MCPError` y
se reporta como un error JSON-RPC normal.

## Autenticación: una capa por encima, no dentro de MCP

`mountMCPServer` no comprueba autenticación por sí mismo. Da por hecho que, si el
proyecto consumidor necesita proteger `/mcp`, ya ha adjuntado el middleware
correspondiente a `app` (p. ej. `WorkOSBearerAuth`) antes de llamar a esta función —
así REST y MCP comparten exactamente la misma comprobación, en el mismo punto de la
cadena de middleware, en lugar de que MCP reimplemente la suya propia a través del
`HTTPRequestValidator` del SDK. Esa alternativa además sería síncrona, mientras que
verificar un bearer token contra un JWKS remoto es inherentemente asíncrono — otro
motivo para dejarlo en manos del middleware de Vapor, que sí corre (y puede rechazar la
petición) antes de que el handler de MCP llegue siquiera a invocarse.
