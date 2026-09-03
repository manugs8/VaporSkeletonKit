# VaporSkeletonKit

Infraestructura genérica y libre de lógica de negocio para backends Vapor 4 + Fluent +
PostgreSQL desplegados en Render contra Neon. Un proyecto depende de este paquete vía
SPM, y referencia los workflows de CI/CD de este repo por path, en lugar de mantener
copias propias de ficheros `.swift`/`.yml` que acaban divergiendo de las correcciones
hechas aquí. Un proyecto consumidor enlaza los targets Swift de abajo y monta su propio
wrapper delgado para las [GitHub Actions compartidas](#github-actions-compartidas) —
todo lo demás queda libre para que se centre en su propia lógica de negocio.

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
- [Utilidades de testing](#utilidades-de-testing)
- [Soporte E2E](#soporte-e2e)
- [GitHub Actions compartidas](#github-actions-compartidas)
- [Documentación DocC](#documentación-docc)
- [Ejecutar los tests de este repo](#ejecutar-los-tests-de-este-repo)

## Requisitos

- Swift 6 (concurrencia estricta, `swiftLanguageModes: [.v6]`)
- macOS 13+ / Linux
- Vapor 4.115+

## Instalación

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "0.1.0")
```

Añade `"VaporSkeletonKit"` como dependencia del target que llama a `configure(_:)` sobre
tu `Application`.

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

Si `configure` lanza un error, este se registra en el log y la `Application` se apaga
antes de relanzarlo — el servidor nunca empieza a servir peticiones sobre una app a
medio configurar.

## Configuración de Postgres

`makePostgresConfiguration(from:)` construye un `DatabaseConfigurationFactory` a partir
de un `PostgresEnvironmentConfig` — bien una única `DATABASE_URL` (el formato de Neon,
siempre con TLS), bien valores discretos de host/port/username/password/database
(desarrollo local, TLS opcional). Nunca lee `Environment` por sí misma — tu app lee sus
propias variables de entorno (con los nombres que prefiera) y pasa aquí los valores,
mismo patrón que sigue `configureBearerAuth` de `WorkOSBearerAuth`:

```swift
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

`registerOpenAPIDocs(_:specFilePath:docsTitle:)` registra `GET /openapi.yaml` (sirve el
fichero de spec en crudo) y `GET /docs` (una página Swagger UI cargada desde un CDN
público, que apunta a él):

```swift
import VaporSkeletonKit

registerOpenAPIDocs(app, specFilePath: "Sources/App/openapi.yaml", docsTitle: "MyProject API Docs")
```

`specFilePath` se resuelve relativo a `app.directory.workingDirectory`, así que la misma
llamada funciona tanto en desarrollo local como dentro de la imagen Docker de producción,
siempre que el fichero YAML se copie a esa misma ruta relativa dentro de la imagen.

## Montaje del servidor MCP

`mountMCPServer(_:name:version:instructions:tools:resources:path:)` monta un servidor
[MCP](https://modelcontextprotocol.io) stateless en `POST/GET/DELETE /mcp` (u otro
`path`), haciendo de puente entre los tipos HTTP de Vapor y el transporte del SDK de
MCP. Se construye un `MCP.Server` nuevo por cada petición — el modo stateless del SDK
rechaza una segunda llamada a `initialize` sobre un servidor ya inicializado y no lleva
ningún id de sesión que permita distinguir entre clientes independientes.

```swift
import VaporSkeletonKit

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

## Utilidades de testing

Un producto separado, `VaporSkeletonKitTesting`, contiene utilidades exclusivas de
testing para el propio target de tests de un proyecto consumidor — no enlazado en
`VaporSkeletonKit` mismo, el mismo split que usa `WorkOSBearerAuth` para su propio
`WorkOSBearerAuthTesting`:

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "0.3.0")

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
integración basados en `VaporTesting`:

```swift
import MCP
import VaporSkeletonKitTesting

let response = try await sendMCP(app, ListTools.request(id: 1, ListTools.Parameters()))
let tools = try response.result.get().tools
```

## Soporte E2E

Un tercer producto, `VaporSkeletonKitE2ESupport`, contiene utilidades exclusivas de
testing para suites E2E que hablan HTTP/MCP real con un servidor ya en ejecución
(normalmente la imagen Docker de producción en CI) en lugar de una `Application` en
proceso — deliberadamente ligero en dependencias (sin Vapor/Fluent), de modo que también
sea seguro enlazarlo desde un target de seed determinista:

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "0.5.0")

// En las dependencias de tus targets de soporte E2E/tests:
.product(name: "VaporSkeletonKitE2ESupport", package: "VaporSkeletonKit")
```

`E2EEnvironment.baseURL` lee `E2E_BASE_URL`, con la dirección local por defecto de
`swift run` como valor por defecto (`http://127.0.0.1:8080`).

`E2EHTTPClient` es un cliente REST mínimo. Igual que `makePostgresConfiguration`, nunca
asume un paquete de autenticación concreto: `authToken` es un closure que produce el
bearer token para las peticiones autenticadas (o `nil` para no enviar ninguno), llamado
en cada petición:

```swift
import VaporSkeletonKitE2ESupport

let client = E2EHTTPClient(authToken: { try await myTokenSigner.validToken() })
let response = try await client.get("items", authenticated: false) // sin cabecera Authorization
let item = try await client.post("items", json: NewItem(name: "Widget"), as: Item.self)
```

`E2EMCPClient.connect(...)` construye un `MCP.Client` real sobre `HTTPClientTransport`,
de la misma forma en que lo haría un agente externo, adjuntando un bearer token de la
misma manera:

```swift
import VaporSkeletonKitE2ESupport

let client = try await E2EMCPClient.connect(authToken: { try await myTokenSigner.validToken() })
let (content, isError) = try await client.callTool(name: "list_items")
```

## GitHub Actions compartidas

Además del paquete Swift, este repo aloja las copias canónicas de un pipeline de CI/CD
completo: tres workflows reutilizables y una composite action, referenciados por
path desde el propio `.github/workflows/` de un proyecto consumidor en lugar de
copiados dentro de él — una corrección hecha aquí llega a cada consumidor sin tener que
editar a mano el fichero de workflow de cada proyecto, de la misma forma en que subir de
versión este paquete SPM lo hace.

El propio `ci.yml`, delgado, de un proyecto consumidor conecta triggers/permisos y llama
a los workflows:

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  ci:
    uses: manugs8/VaporSkeletonKit/.github/workflows/reusable-ci.yml@main

  protected-paths-check:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: manugs8/VaporSkeletonKit/.github/actions/protected-paths-check@main
```

Fija a un tag (p. ej. `@v0.5.0` en lugar de `@main`) en cuanto un consumidor quiera que
una corrección hecha aquí requiera un opt-in explícito en lugar de aplicarse en su
siguiente ejecución de CI.

### `reusable-ci.yml`

El pipeline de build/test/lint. `unit-tests` e `integration-tests` corren cada uno sobre
la imagen Swift/OS exacta que indica el stage `build` del `Dockerfile` del consumidor
(leída directamente de la línea `FROM <image> AS build`, de modo que nunca puede
divergir silenciosamente de lo que realmente se despliega); `integration-tests` además
recibe un contenedor de servicio `postgres:16`. `docker-build` construye la imagen de
producción del consumidor (sin publicarla) para que un `Dockerfile` roto falle en CI en
lugar de aparecer solo al desplegar. `lint-openapi` valida `Sources/App/openapi.yaml`
con Redocly. Requiere que el consumidor tenga ambos ficheros en esas rutas.

### `reusable-deploy-smoke.yml`

Consulta un `/health` desplegado con backoff después de que la propia integración de
Render con GitHub redespliegue al hacer push a `main` — este workflow no dispara el
despliegue en sí, solo lo verifica. Recibe `render-service-url` (input, obligatorio).

### `reusable-e2e.yml`

Ejecuta la suite E2E real del consumidor contra su imagen Docker de producción exacta,
sobre una rama Neon efímera creada a partir de `e2e-base` y siempre destruida después —
nunca contra una `Application` en proceso. Recibe `neon-project-id` (input, obligatorio)
más `neon-api-key` y `e2e-auth-test-private-key` (secrets, obligatorios); los inputs
opcionales `resource-indicator`, `seed-command` y `db-failure-container` cubren un
resource indicator OAuth fijo, un paso de seed de datos de referencia y un segundo
contenedor de caída de base de datos. Consulta los propios comentarios del workflow para
la mecánica completa (la rama Neon efímera, un túnel rápido de Cloudflare que hace de
issuer de WorkOS AuthKit, limpieza de disco en el runner, etc.) — nada de eso es
específico de un consumidor en concreto.

### `protected-paths-check` (composite action)

Marca una PR que toca alguna ruta listada en el propio
`.github/protected-paths.txt` del consumidor (pathspec `:(glob)` de git, una por línea)
— resumen del job + una etiqueta `protected-change`, sin bloquear el merge por sí sola.
Un consumidor le da dientes de verdad con branch protection que exija revisión de
CODEOWNERS. Recibe un input opcional `paths-file`, con `.github/protected-paths.txt`
como valor por defecto.

## Documentación DocC

Además de este README, el target `VaporSkeletonKit` incluye un catálogo DocC
(`Sources/VaporSkeletonKit/VaporSkeletonKit.docc`) con artículos que explican el porqué
de cada decisión de diseño (con esquemas del flujo de una petición MCP, la arquitectura
de los tres productos, la estrategia de testing en tres niveles, etc.) y tutoriales paso
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

## Ejecutar los tests de este repo

```bash
swift test
```

`HealthRouteTests` ejercita `DatabaseHealthChecker` contra un Postgres real, así que
necesita uno alcanzable en `localhost:5432` con usuario/contraseña/base de datos
`postgres`/`postgres`/`postgres` (sobreescribible vía `DATABASE_HOST`/`DATABASE_PORT`/
`DATABASE_USERNAME`/`DATABASE_PASSWORD`/`DATABASE_NAME`, los mismos nombres que lee
`configure(_:)` en un proyecto consumidor):

```bash
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16
swift test
```

`.github/workflows/ci.yml` ejecuta la misma suite contra un contenedor de servicio
`postgres:16` en cada push/PR a `main`.
