import MCP
import Vapor

/// Monta un servidor MCP en `POST/GET/DELETE <path>` (`/mcp` por defecto), haciendo de
/// puente entre los tipos HTTP de Vapor y los tipos `MCP.HTTPRequest`/`HTTPResponse`,
/// agnósticos de framework, que usa `StatelessHTTPServerTransport`.
///
/// Este fichero es el único lugar que necesita conocer tanto "Vapor" como "transporte
/// MCP" — `MCPTool`/`MCPResource`/`MCPServerFactory` no importan Vapor en absoluto.
///
/// `Request`/`Response` se escriben explícitamente como `Vapor.Request`/`Vapor.Response`
/// en todo este fichero porque el módulo `MCP` también exporta sus propios tipos
/// genéricos de mensaje JSON-RPC `Request<M>`/`Response<M>`, que de otro modo serían
/// ambiguos.
///
/// - Parameters:
///   - app: La `Application` sobre la que montar la ruta.
///   - name: El nombre que el servidor anuncia a cualquier cliente que se conecte.
///   - version: La cadena de versión del servidor.
///   - instructions: Guía en texto libre mostrada al modelo conectado sobre para qué
///     sirven las herramientas/recursos de este servidor.
///   - tools: Las herramientas a exponer vía `tools/list`/`tools/call`.
///   - resources: Los recursos a exponer vía `resources/list`/`resources/read`.
///   - path: La ruta sobre la que montar el servidor. Por defecto, `"mcp"`.
public func mountMCPServer(
    _ app: Application,
    name: String,
    version: String,
    instructions: String,
    tools: [any MCPTool],
    resources: [any MCPResource] = [],
    path: PathComponent = "mcp"
) throws {
    let handler: (@Sendable (Vapor.Request) async throws -> Vapor.Response) = { req in
        try await handleMCPRequest(
            req, name: name, version: version, instructions: instructions, tools: tools, resources: resources)
    }
    for method in [Vapor.HTTPMethod.GET, .POST, .DELETE] {
        app.on(method, path, body: .collect, use: handler)
    }

    app.logger.info(
        "MCP server mounted at /\(path.description)",
        metadata: ["tools": .array(tools.map { .string($0.name) })]
    )
}

/// Maneja una única petición HTTP contra la ruta MCP levantando un par
/// `MCP.Server` + `StatelessHTTPServerTransport` nuevo y aislado, ejecutando la
/// petición a través de él, y desmontándolo de nuevo.
///
/// Un único `MCP.Server` de larga duración no se puede reutilizar entre clientes MCP
/// independientes en modo stateless: el SDK rechaza una segunda llamada a `initialize`
/// sobre un servidor ya inicializado, y el modo stateless no lleva ningún id de sesión
/// que permita distinguir entre clientes. Construir un servidor nuevo (barato, en
/// memoria) por petición mantiene cada petición completamente aislada, que es el patrón
/// correcto para un transporte stateless que sirve a múltiples clientes remotos y sin
/// relación entre sí.
private func handleMCPRequest(
    _ req: Vapor.Request,
    name: String,
    version: String,
    instructions: String,
    tools: [any MCPTool],
    resources: [any MCPResource]
) async throws -> Vapor.Response {
    let mcpRequest = MCP.HTTPRequest(vaporRequest: req)

    // La autenticación (si la hay) ocurre una capa por encima, en el middleware que sea
    // que el llamador adjunte a `app` antes de llamar a `mountMCPServer` — compartida
    // con el resto de la app en lugar de que MCP tenga su propia comprobación separada
    // — en vez de a través del propio pipeline `HTTPRequestValidator` del SDK de MCP:
    // ese pipeline es síncrono, pero verificar un bearer token contra un JWKS remoto es
    // inherentemente asíncrono, y la cadena de middleware de Vapor ya se ejecuta (y
    // puede rechazar la petición) antes de que este handler llegue siquiera a
    // invocarse.
    let validators: [any HTTPRequestValidator] = [
        OriginValidator.disabled,
        AcceptHeaderValidator(mode: .jsonOnly),
        ContentTypeValidator(),
        ProtocolVersionValidator(),
    ]

    let transport = StatelessHTTPServerTransport(
        validationPipeline: StandardValidationPipeline(validators: validators),
        logger: req.logger
    )
    let server = await MCPServerFactory.makeServer(
        name: name, version: version, instructions: instructions, tools: tools, resources: resources)

    try await server.start(transport: transport)
    let mcpResponse = await transport.handleRequest(mcpRequest)
    await server.stop()

    return mcpResponse.vaporResponse()
}

extension MCP.HTTPRequest {
    /// Convierte una petición de Vapor en el tipo de petición agnóstico de framework
    /// que espera el transporte MCP. Asume que la ruta se registró con
    /// `body: .collect`, de modo que el cuerpo completo ya está bufferizado y
    /// disponible de forma síncrona.
    fileprivate init(vaporRequest req: Vapor.Request) {
        var headers: [String: String] = [:]
        for (name, value) in req.headers {
            // La búsqueda insensible a mayúsculas la gestiona
            // `HTTPRequest.header(_:)`; gana la primera aparición, igual que hacen los
            // validadores, que solo leen cabeceras de valor único (Accept,
            // Content-Type, Authorization, id de sesión, etc).
            if headers[name] == nil {
                headers[name] = value
            }
        }

        let body = req.body.data.map { Data(buffer: $0) }

        self.init(
            method: req.method.rawValue,
            headers: headers,
            body: body,
            path: req.url.path
        )
    }
}

extension MCP.HTTPResponse {
    /// Convierte una respuesta del transporte MCP en una `Response` de Vapor.
    fileprivate func vaporResponse() -> Vapor.Response {
        let status = Vapor.HTTPResponseStatus(statusCode: statusCode)
        var vaporHeaders = Vapor.HTTPHeaders()
        for (name, value) in headers {
            vaporHeaders.add(name: name, value: value)
        }

        switch self {
        case .accepted, .ok:
            return Vapor.Response(status: status, headers: vaporHeaders)
        case .data(let data, _):
            return Vapor.Response(status: status, headers: vaporHeaders, body: .init(data: data))
        case .error:
            return Vapor.Response(
                status: status, headers: vaporHeaders, body: .init(data: bodyData ?? Data()))
        case .stream(let stream, _):
            let body = Vapor.Response.Body(stream: { writer in
                Task {
                    do {
                        for try await chunk in stream {
                            try await writer.write(.buffer(.init(data: chunk))).get()
                        }
                        try await writer.write(.end).get()
                    } catch {
                        try? await writer.write(.error(error)).get()
                    }
                }
            })
            return Vapor.Response(status: status, headers: vaporHeaders, body: body)
        }
    }
}
