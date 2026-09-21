# VaporSkeletonKit

Infraestructura genérica y libre de lógica de negocio para backends Vapor 4 + Fluent +
PostgreSQL desplegados en Render contra Neon. Un proyecto depende de este paquete vía
SPM en lugar de mantener copias propias de ficheros `.swift` que acaban divergiendo de
las correcciones hechas aquí. Un proyecto consumidor enlaza los targets Swift de abajo y
monta su propio wrapper delgado para ejecución — todo lo demás queda libre para que se
centre en su propia lógica de negocio.

Paquete complementario: [`WorkOSBearerAuth`](https://github.com/manugs8/WorkOSBearerAuth)
cubre la autenticación; este paquete cubre todo lo demás que no es ni autenticación ni
lógica de negocio.

También hay un [catálogo DocC](#documentación-docc) con artículos y tutoriales que
explican no solo el qué, sino el porqué de cada pieza.

## Contenido

- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Entrypoint de la app](#entrypoint-de-la-app)
- [Configuración de Postgres](#configuración-de-postgres)
- [Servir OpenAPI / Swagger UI](#servir-openapi--swagger-ui)
- [Montaje del servidor MCP](#montaje-del-servidor-mcp)
- [Modo E2E (rutas backdoor)](#modo-e2e-rutas-backdoor)
- [Utilidades de testing](#utilidades-de-testing)
- [Soporte E2E](#soporte-e2e)
- [Documentación DocC](#documentación-docc)
- [Estándar de ingeniería](#estándar-de-ingeniería)
- [Ejecutar los tests de este repo](#ejecutar-los-tests-de-este-repo)
- [Licencia](#licencia)

## Requisitos

- Swift 6 (concurrencia estricta, `swiftLanguageModes: [.v6]`)
- macOS 13+ / Linux
- Vapor 4.115+

## Instalación

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "2.0.0")
```

Añade `"VaporSkeletonKit"` como dependencia del target que llama a `configure(_:)` sobre
tu `Application` — y también `"VaporSkeletonKitMCP"` si montas el servidor MCP
(`mountMCPServer`, `MCPTool`, `GetHealthTool`...), que vive en un producto aparte.

## Entrypoint de la app

`runApp(configure:)` envuelve la detección de entorno, el arranque del logging y el
código repetitivo de ciclo de vida (`Application.make`, ejecutar hasta el apagado,
desmontar) que es idéntico en todos los proyectos construidos a partir de este kit. Tu
entrypoint `@main` solo necesita indicar qué `configure(_:)` ejecutar:

```swift
import Vapor
import VaporSkeletonKit

@main
enum Entrypoint {
    static func main() async throws {
        try await runApp(configure: configure)
    }
}
```

Si `configure` lanza un error — o si el propio servidor (`execute()`) falla, p. ej. por
un puerto ya ocupado —, este se registra en el log y la `Application` se apaga antes de
relanzarlo — el servidor nunca empieza a servir peticiones sobre una app a medio
configurar.

## Configuración de Postgres

`makePostgresConfiguration(from:)` construye un `DatabaseConfigurationFactory` a partir
de un `PostgresEnvironmentConfig` — bien una única `DATABASE_URL` (el formato de Neon,
siempre con TLS), bien valores discretos de host/port/username/password/database
(desarrollo local, TLS opcional). Nunca lee `Environment` por sí misma — tu app lee sus
propias variables de entorno (con los nombres que prefiera) y pasa aquí los valores,
mismo patrón que sigue `configureBearerAuth` de `WorkOSBearerAuth`:

```swift
import FluentPostgresDriver // DatabaseID.psql
import VaporSkeletonKit

app.databases.use(
    try makePostgresConfiguration(from: PostgresEnvironmentConfig(
        databaseURL: Environment.get("DATABASE_URL"),
        host: Environment.get("DATABASE_HOST"),
        port: Environment.get("DATABASE_PORT").flatMap(Int.init),
        username: Environment.get("DATABASE_USERNAME"),
        password: Environment.get("DATABASE_PASSWORD"),
        database: Environment.get("DATABASE_NAME"),
        tlsDisabled: Environment.get("DATABASE_TLS") == "disable"
    )),
    as: .psql
)
```

TLS se establece con un `NIOSSLContext` permisivo (verificación de certificado
desactivada, firmado por CA pública) adecuado para proveedores gestionados como Neon a
los que se accede sin pinning.

## Servir OpenAPI / Swagger UI

`registerOpenAPIDocs(_:specData:docsTitle:)` registra `GET /openapi.yaml` (sirve el
fichero de spec en crudo) y `GET /docs` (una página Swagger UI cargada desde un CDN
público, que apunta a él):

```swift
import VaporSkeletonKit

registerOpenAPIDocs(app, specData: openapiData, docsTitle: "MyProject API Docs")
```

El spec se inyecta como `Data` en lugar de leerse del disco directamente con una ruta.
De esta forma, en vez de depender de rutas relativas o absolutas, el proyecto consumidor
debe proveer el documento (por ejemplo importándolo como bundle o desde un paquete externo).

## Montaje del servidor MCP

`mountMCPServer(_:name:version:instructions:tools:resources:path:)` monta un servidor
[MCP](https://modelcontextprotocol.io) stateless en `POST/GET/DELETE /mcp` (u otro
`path`), haciendo de puente entre los tipos HTTP de Vapor y el transporte del SDK de
MCP. Se construye un `MCP.Server` nuevo por cada petición — el modo stateless del SDK
rechaza una segunda llamada a `initialize` sobre un servidor ya inicializado y no lleva
ningún id de sesión que permita distinguir entre clientes independientes.

```swift
import VaporSkeletonKitMCP

try mountMCPServer(
    app,
    name: "MyProject",
    version: "1.0.0",
    instructions: "Tools for inspecting and managing MyProject.",
    tools: [GetHealthTool(app: app), ListItemsTool(app: app)],
    resources: [ItemsResource(app: app)]
)
```

Implementa `MCPTool`/`MCPResource` para tus propios tipos de dominio — ni el protocolo
ni el código de montaje/despacho conocen ningún modelo de negocio concreto. Se espera
que la autenticación ya esté adjunta a `app` (p. ej. vía `WorkOSBearerAuth`) antes de
llamar a esta función, de modo que REST y MCP compartan la misma comprobación en lugar
de que MCP reimplemente la suya propia.

Lanza `MCPToolError` desde el `call(arguments:)` de una herramienta para cualquier fallo
que el modelo llamador pueda razonablemente ver y ante el que pueda reaccionar
(`invalidArgument`, `notFound`, `database`, `internalError`) — se reportan como un
resultado de herramienta con `isError: true`, no como un fallo a nivel de transporte.

`mountMCPServer` lanza `MCPServerMountError` si dos `tools` comparten `name`, o dos
`resources` comparten `uri` — sin esta comprobación, el despacho interno elegiría el
primero en silencio y el resto quedarían inalcanzables sin ningún aviso.

## Modo E2E (rutas backdoor)

`registerE2EMode(_:scenarioFactory:)` monta dos rutas de apoyo para suites E2E: inyección
de fallos (`POST`/`DELETE /_test/fault`, ver `E2EHTTPClient.armFault`) y preparación de
estado (`POST /e2e/prepare`, que puede truncar todas las tablas del schema si
`reset: true` antes de aplicar el escenario pedido).

Solo se activa en el entorno `testing`: en cualquier otro lanza
`E2EModeError.requiresTestingEnvironment` en vez de registrar nada. Eso incluye
`.development`, el que usa Vapor cuando el proceso arranca sin `--env`, así que un
despliegue de producción mal configurado tampoco puede exponer estas rutas; el error de
configuración se convierte en un fallo de arranque. La instancia E2E de tu imagen se
arranca con `serve --env testing` (o `VAPOR_ENV=testing`):

```swift
import VaporSkeletonKit

if Environment.get("E2E_MODE") == "true" {
    try registerE2EMode(app, scenarioFactory: MyScenarioFactory())
}
```

Implementa `E2EScenarioFactory` (un único método, `make(scenario:) throws -> any
E2EScenario`) para mapear el identificador que envía el test en el campo `scenario`
(p. ej. `"populated_dashboard"`) a tu propio código de seed — `E2EScenario.apply(req:)`
recibe el `Request` en curso, así que puede usar `req.db` igual que cualquier otro
handler. Si la factory lanza (un identificador que no reconoce), `/e2e/prepare`
responde `400`.

## Utilidades de testing

Un producto separado, `VaporSkeletonKitTesting`, contiene utilidades exclusivas de
testing para el propio target de tests de un proyecto consumidor — no enlazado en
`VaporSkeletonKit` mismo, el mismo split que usa `WorkOSBearerAuth` para su propio
`WorkOSBearerAuthTesting`:

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "2.0.0")

// En las dependencias de tu target de tests:
.product(name: "VaporSkeletonKitTesting", package: "VaporSkeletonKit")
```

`withTestApp(environment:configure:test:)` arranca una `Application` de test, ejecuta tu
`configure(_:)`, migra, ejecuta el cuerpo de tu test y siempre revierte las migraciones y
apaga la app después — incluso si `configure` o el cuerpo del test lanzan un error.
`environment` establece variables de entorno de proceso (p. ej. el flag propio de un
paquete de autenticación para "desactivar auth en tests") antes de que se ejecute
`Application.make(.testing)`; está vacío por defecto y no asume ningún paquete de
autenticación en concreto:

```swift
import VaporSkeletonKitTesting

func withMigratedApp(_ test: (Application) async throws -> Void) async throws {
    try await withTestApp(environment: ["AUTH_DISABLED": "true"], configure: configure, test: test)
}
```

`sendMCP(_:_:path:)` envía una única petición JSON-RPC tipada a la ruta montada por
`mountMCPServer(_:...)` y decodifica la respuesta tipada, para usar en tests de
integración basados en `VaporTesting`. Vive en `VaporSkeletonKitMCPTesting`, un producto
aparte de `VaporSkeletonKitTesting` (solo lo necesitas si tu proyecto monta MCP):

```swift
import MCP
import VaporSkeletonKitMCPTesting

let response = try await sendMCP(app, ListTools.request(id: 1, ListTools.Parameters()))
let tools = try response.result.get().tools
```

`withE2EServer(masterConfig:configure:test:)` combina lo mejor de `withTestApp` (app
completa, migrada) con transporte HTTP real: arranca un servidor Vapor de verdad en un
puerto efímero (el `0` que asigna el SO, nunca una colisión con `8080`) contra una base
de datos Postgres **creada y destruida exclusivamente para esa ejecución** — el
`dynamicDB` que recibe tu `configure` — para que suites E2E que corren en paralelo (como
las que paraleliza Swift Testing por defecto) nunca se pisen. `masterConfig` son
credenciales con permiso de `CREATE`/`DROP DATABASE`; igual que
`makePostgresConfiguration`, esta función nunca lee `Environment` por sí misma:

```swift
import VaporSkeletonKitTesting

let masterConfig = PostgresEnvironmentConfig(
    databaseURL: Environment.get("DATABASE_URL"),
    host: Environment.get("DATABASE_HOST"),
    port: Environment.get("DATABASE_PORT").flatMap(Int.init),
    username: Environment.get("DATABASE_USERNAME"),
    password: Environment.get("DATABASE_PASSWORD"),
    database: Environment.get("DATABASE_NAME"),
    tlsDisabled: Environment.get("DATABASE_TLS") == "disable"
)

try await withE2EServer(masterConfig: masterConfig, configure: { app, dynamicDB in
    // PostgresEnvironmentConfig es inmutable — reconstruye a partir de masterConfig
    // con database: dynamicDB en vez de mutarlo.
    let config = PostgresEnvironmentConfig(
        databaseURL: masterConfig.databaseURL, host: masterConfig.host,
        port: masterConfig.port, username: masterConfig.username,
        password: masterConfig.password, database: dynamicDB,
        tlsDisabled: masterConfig.tlsDisabled
    )
    app.databases.use(try makePostgresConfiguration(from: config), as: .psql)
    try configure(app) // el configure(_:) real de tu proyecto
}) { client in
    let response = try await client.get("health")
    #expect(response.status == 200)
}
```

## Soporte E2E

Un tercer producto, `VaporSkeletonKitE2ESupport`, contiene utilidades exclusivas de
testing para suites E2E que hablan HTTP/MCP real con un servidor ya en ejecución
(normalmente la imagen Docker de producción en CI) en lugar de una `Application` en
proceso — deliberadamente ligero en dependencias (sin Vapor/Fluent), de modo que también
sea seguro enlazarlo desde un target de seed determinista:

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "2.0.0")

// En las dependencias de tus targets de soporte E2E/tests:
.product(name: "VaporSkeletonKitE2ESupport", package: "VaporSkeletonKit")
```

`E2EEnvironment.baseURL` lee `E2E_BASE_URL`, con la dirección local por defecto de
`swift run` como valor por defecto (`http://127.0.0.1:8080`). Si `E2E_BASE_URL` está
definida pero no es una URL válida, falla rápido con un mensaje que indica el valor
recibido, en vez de un crash silencioso o de caer en el valor por defecto.

`E2EHTTPClient` es un cliente REST mínimo. Igual que `makePostgresConfiguration`, nunca
asume un paquete de autenticación concreto: `authToken` es un closure que produce el
bearer token para las peticiones autenticadas (o `nil` para no enviar ninguno), llamado
en cada petición:

```swift
import VaporSkeletonKitE2ESupport

let client = E2EHTTPClient(authToken: { try await myTokenSigner.validToken() })
let response = try await client.get("items", authorization: .none) // sin cabecera Authorization
let item = try await client.post("items", json: NewItem(name: "Widget"), as: Item.self)
```

Las sobrecargas que decodifican (`post(json:as:)`, `get(as:)`) aceptan cualquier status
de éxito (`200..<300`), no solo `200` — incluido `201 Created`, el caso canónico de un
`POST` de creación.

`path` se trata siempre como un componente de ruta literal — `"items?filter=x"` no
funciona como query string, ya que `?`/`&`/`=` se escapan como caracteres de ruta
normales. Para eso está `query: [URLQueryItem]`, disponible en `get`/`send` (y en la
sobrecarga que decodifica). Los valores se escapan por completo, incluido `+` (que el
servidor decodificaría como un espacio, p. ej. en el offset `+02:00` de una fecha):

```swift
let response = try await client.get(
    "items", query: [URLQueryItem(name: "filter", value: "active"), URLQueryItem(name: "page", value: "2")]
)
```

`E2EMCPClient.connect(...)` construye un `MCP.Client` real sobre `HTTPClientTransport`,
de la misma forma en que lo haría un agente externo. Vive en `VaporSkeletonKitMCPE2ESupport`,
un producto aparte de `VaporSkeletonKitE2ESupport` (solo lo necesitas si tu proyecto monta
MCP). A diferencia de `E2EHTTPClient`, `authToken` se resuelve una única vez aquí en
`connect(...)` y el token resultante se adjunta a cada petición de esa conexión — no se
vuelve a llamar a `authToken` por petición:

```swift
import VaporSkeletonKitMCPE2ESupport

let client = try await E2EMCPClient.connect(authToken: { try await myTokenSigner.validToken() })
let (content, isError) = try await client.callTool(name: "list_items")
```

## Documentación DocC

Además de este README, el target `VaporSkeletonKit` incluye un catálogo DocC
(`Sources/VaporSkeletonKit/VaporSkeletonKit.docc`) con artículos que explican el porqué
de cada decisión de diseño (con esquemas del flujo de una petición MCP, la arquitectura
de los seis productos, la estrategia de testing en tres niveles, etc.) y tutoriales paso
a paso para montar un backend nuevo desde cero y añadirle una herramienta MCP propia.

Para generarla y abrirla en Xcode:

```bash
swift package --disable-sandbox preview-documentation --target VaporSkeletonKit
```

O, sin el plugin, directamente con `docc` (requiere Xcode):

```bash
xcrun docc preview Sources/VaporSkeletonKit/VaporSkeletonKit.docc \
    --additional-symbol-graph-dir .build/symbol-graphs
```

## Estándar de ingeniería

[`docs/EstandarDeIngenieria.md`](docs/EstandarDeIngenieria.md) es la norma, no la
implementación: qué debe cumplir un backend de este stack (arquitectura, niveles de
test, estrategia de Neon, checklist de
adopción...) y por qué, independientemente de cómo lo resuelva este paquete en concreto.
El catálogo DocC de arriba documenta el cómo de cada pieza que este kit ya resuelve;
donde ambos solapan, el documento del estándar enlaza al artículo correspondiente en vez
de repetirlo.

## Ejecutar los tests de este repo

```bash
swift test
```

Sin más, `swift test` ejecuta todo lo que no necesita base de datos y marca como
*skipped* los tests que sí necesitan un Postgres real (repartidos entre
`HealthRouteTests`, `GetHealthToolTests`, `E2EModeTests`, `WithTestAppTests` y
`WithE2EServerTests`). Para
ejecutarlos también, levanta un Postgres alcanzable en `localhost:5432` con
usuario/contraseña/base de datos `postgres`/`postgres`/`postgres` (sobreescribible vía
`DATABASE_HOST`/`DATABASE_PORT`/`DATABASE_USERNAME`/`DATABASE_PASSWORD`/`DATABASE_NAME`,
los mismos nombres que lee `configure(_:)` en un proyecto consumidor) y activa esos
tests con `CI=true`:

```bash
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16
CI=true swift test
```

La otra forma de activarlos, `DATABASE_URL`, fuerza TLS (es el camino de Neon, ver
`makePostgresConfiguration`), así que no sirve contra un Postgres local sin TLS como el
de arriba. El usuario debe poder hacer `CREATE`/`DROP DATABASE` (`WithE2EServerTests`
crea y destruye una base de datos por test).

Este repo no tiene pipeline de CI remoto — consistente con la estrategia "pruebas
locales primero" de
[`docs/EstandarDeIngenieria.md`](docs/EstandarDeIngenieria.md#12-pruebas-locales-y-testsupport).
Valida localmente con `swift test` antes de cada commit/push.

## Licencia

MIT — ver [`LICENSE`](LICENSE).
