# Testing y E2E

Los tres niveles de testing que sigue todo proyecto construido con este kit, y qué
utilidades aporta `VaporSkeletonKitTesting`/`VaporSkeletonKitE2ESupport` en cada uno.

## Tres niveles, cada uno probando lo que el anterior no puede

![Pirámide de testing en tres niveles: unitarios en la base (la mayoría), integración en el medio (con VaporSkeletonKitTesting), y E2E arriba (con VaporSkeletonKitE2ESupport, contra un servidor real).](piramide-testing)

- **Unitarios** — lógica de dominio pura, sin red ni base de datos. Responsabilidad
  exclusiva del proyecto consumidor; este kit no aporta nada aquí porque no hay lógica
  de dominio que probar.
- **Integración** — la app completa, montada en proceso, contra un Postgres real.
  Aportado por `VaporSkeletonKitTesting`.
- **E2E** — HTTP/MCP real contra un servidor ya en ejecución (a menudo la imagen Docker
  de producción, en un contenedor). Aportado por `VaporSkeletonKitE2ESupport`.

Cada nivel existe porque el anterior no puede detectar cierta clase de fallo: un test
unitario no puede detectar que una migración de Fluent falla contra Postgres real; un
test de integración en proceso no puede detectar que el `Dockerfile` de producción está
roto, o que dos procesos independientes (cliente y servidor) no logran hablar por HTTP
real.

## Integración: `withTestApp` + Postgres real

`withTestApp(environment:configure:test:)` (de `VaporSkeletonKitTesting`) arranca una `Application` de test real,
ejecuta el `configure(_:)` del propio proyecto, migra, ejecuta el test, y **siempre**
revierte las migraciones y apaga la app — incluso si `configure` o el test lanzan un
error:

```swift
func withMigratedApp(_ test: (Application) async throws -> Void) async throws {
    try await withTestApp(environment: ["AUTH_DISABLED": "true"], configure: configure, test: test)
}
```

`environment` establece variables de entorno de proceso (vía `setenv`) antes de que se
ejecute `Application.make(.testing)` — por ejemplo, el flag de un paquete de
autenticación para desactivarla en tests. Está vacío por defecto porque esta función no
asume ningún paquete de autenticación en concreto, el mismo principio que
``makePostgresConfiguration(from:)`` (ver <doc:ConfiguracionPostgres>).

`sendMCP(_:_:path:)` complementa a `withTestApp` para probar el servidor MCP montado
sobre esa misma `Application` de test, enviando una petición JSON-RPC tipada y
decodificando la respuesta tipada:

```swift
let response = try await sendMCP(app, ListTools.request(id: 1, ListTools.Parameters()))
let tools = try response.result.get().tools
```

## E2E: HTTP/MCP real, nunca en proceso

`VaporSkeletonKitE2ESupport` es deliberadamente ligero en dependencias — ni Vapor ni
Fluent —, porque una suite E2E no necesita la pila del servidor: habla con un servidor
que **ya está corriendo**, en otro proceso (o en otro contenedor por completo).

`E2EEnvironment.baseURL` (de `VaporSkeletonKitE2ESupport`) lee `E2E_BASE_URL`, con la dirección local de `swift run`
como valor por defecto, para que las mismas pruebas funcionen tanto contra un servidor
arrancado a mano en local como contra el contenedor que `reusable-e2e.yml` levanta en
CI.

`E2EHTTPClient` es un cliente REST mínimo:

```swift
let client = E2EHTTPClient(authToken: { try await myTokenSigner.validToken() })
let response = try await client.get("items", authenticated: false) // sin cabecera Authorization
let item = try await client.post("items", json: NewItem(name: "Widget"), as: Item.self)
```

`E2EMCPClient` construye un `MCP.Client` real sobre `HTTPClientTransport` — un cliente
MCP genuino, hablando HTTP/JSON-RPC real, exactamente como lo haría un agente externo:

```swift
let client = try await E2EMCPClient.connect(authToken: { try await myTokenSigner.validToken() })
let (content, isError) = try await client.callTool(name: "list_items")
```

Ambos comparten el mismo patrón que `PostgresEnvironmentConfig` y
`BearerAuthEnvironmentConfig`: `authToken` es un closure que produce el bearer token (o
`nil` para no enviar ninguno), llamado en cada petición — ninguno de los dos tipos
asume qué paquete de autenticación usa el proyecto consumidor, ni cachea el token entre
llamadas.

## `withRunningServer`: probando este kit consigo mismo

Los propios tests de `VaporSkeletonKitE2ESupportTests` en este repo necesitan un
servidor real escuchando para poder ejercitar `E2EHTTPClient`/`E2EMCPClient` de verdad
— no tendría sentido probar un cliente HTTP contra una `Application` en proceso, que es
justo lo que este cliente existe para evitar. `withRunningServer(port:mount:test:)`
arranca una `Application` real, la vincula a un socket TCP real en
`127.0.0.1:port`, y garantiza su desmontaje al terminar — la única pieza de este
artículo que no forma parte de la API pública del kit, porque es un detalle interno de
cómo este mismo repo se testea a sí mismo.
