# Testing y E2E

Los tres niveles de testing que sigue todo proyecto construido con este kit, y qué
utilidades aporta `VaporSkeletonKitTesting` (o `VaporSkeletonKitMCPTesting`)/`VaporSkeletonKitE2ESupport` en cada uno.

## Tres niveles, cada uno probando lo que el anterior no puede

![Pirámide de testing en tres niveles: unitarios en la base (la mayoría), integración en el medio (con VaporSkeletonKitTesting), y E2E arriba (con VaporSkeletonKitE2ESupport, contra un servidor real).](piramide-testing)

- **Unitarios** — lógica de dominio pura, sin red ni base de datos. Responsabilidad
  exclusiva del proyecto consumidor; este kit no aporta nada aquí porque no hay lógica
  de dominio que probar.
- **Integración** — la app completa, montada en proceso, contra un Postgres real.
  Aportado por `VaporSkeletonKitTesting` (o `VaporSkeletonKitMCPTesting`).
- **E2E** — HTTP real contra un servidor ya en ejecución. Aportado por `VaporSkeletonKitE2ESupport` (o `VaporSkeletonKitMCPE2ESupport`).

Cada nivel existe porque el anterior no puede detectar cierta clase de fallo: un test
unitario no puede detectar que una migración de Fluent falla contra Postgres real; un
test de integración en proceso no puede detectar que dos procesos independientes (cliente y servidor) no logran hablar por HTTP
real.

## Integración: `withTestApp` + Postgres real

`withTestApp(environment:configure:test:)` (de `VaporSkeletonKitTesting` (o `VaporSkeletonKitMCPTesting`)) arranca una `Application` de test real,
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
``makePostgresConfiguration(from:)`` (ver <doc:ConfiguracionPostgres>). Cada variable se
restaura a su valor previo (o se elimina, si no existía) al terminar el test — incluso
si lanza —, así que no deja contaminado el proceso para los tests que se ejecuten
después en él.

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

`E2EEnvironment.baseURL` (de `VaporSkeletonKitE2ESupport` (o `VaporSkeletonKitMCPE2ESupport`)) lee `E2E_BASE_URL`, con la dirección local de `swift run`
como valor por defecto, para que las mismas pruebas funcionen tanto contra un servidor
arrancado a mano en local o los equivalentes en CI.

`E2EHTTPClient` es un cliente REST mínimo:

```swift
let client = E2EHTTPClient(authToken: { try await myTokenSigner.validToken() })
let response = try await client.get("items", authorization: .none) // sin cabecera Authorization
let item = try await client.post("items", json: NewItem(name: "Widget"), as: Item.self)
```

`authorization` acepta tres valores (`E2EHTTPClient.Authorization`):

- `.default` (el implícito en todos los métodos) — llama a `authToken` en cada
  petición.
- `.none` — omite la cabecera `Authorization` por completo, sin llamar a `authToken`
  — para los escenarios que verifican el rechazo de una petición no autenticada.
- `.bearer(String)` — adjunta un token concreto en vez del que produciría `authToken`
  — para los escenarios que prueban el rechazo de un token inválido o caducado, sin
  necesidad de que el proyecto consumidor sepa firmar uno "malo" con su propio paquete
  de autenticación.

`send`/`get`/`post`/`put` devuelven una `Response` con `status`, `body`, y también
`headers` (nombres en minúsculas) — para afirmar sobre `WWW-Authenticate` en un `401`,
o `Content-Type` en un `200`. Si el servidor responde con dos cabeceras que solo
difieren en mayúsculas/minúsculas, se queda con la última — nunca crashea por una
colisión de claves al normalizar. `send(_:_:body:contentType:authorization:)` acepta un
`contentType` explícito (`application/json` por defecto) — la única vía para probar que
el servidor rechaza correctamente un `Content-Type` incompatible en vez de intentar
decodificarlo. `put`/`put(encoding:)` existen junto a los `post` ya vistos, para
ejercitar endpoints `PUT`.

`post(json:as:)`/`get(as:)` (las sobrecargas que decodifican directamente a un tipo)
aceptan cualquier status `200..<300`, no solo `200` — así `post(json:as:)` sirve tal
cual contra un endpoint de creación que responde `201 Created`, sin tener que caer a
`post(json:)` + decodificar el cuerpo a mano.

`get`/`send` (y la sobrecarga de `get` que decodifica) aceptan `query: [URLQueryItem]`
para paginación/filtros. `path` se trata siempre como un componente de ruta literal —
`baseURL.appendingPathComponent(path)` escapa `?`/`&`/`=` como caracteres normales de
ruta, así que un `path` como `"items?filter=x"` nunca llega como query string al
servidor; hay que pasarlo por `query:`, que se adjunta vía `URLComponents`:

```swift
let response = try await client.get(
    "items", query: [URLQueryItem(name: "filter", value: "active")]
)
```

`E2EMCPClient` construye un `MCP.Client` real sobre `HTTPClientTransport` — un cliente
MCP genuino, hablando HTTP/JSON-RPC real, exactamente como lo haría un agente externo:

```swift
let client = try await E2EMCPClient.connect(authToken: { try await myTokenSigner.validToken() })
let (content, isError) = try await client.callTool(name: "list_items")
```

Ambos comparten el mismo patrón que `PostgresEnvironmentConfig` y
`BearerAuthEnvironmentConfig`: `authToken` es un closure que produce el bearer token (o
`nil` para no enviar ninguno) — ninguno de los dos tipos asume qué paquete de
autenticación usa el proyecto consumidor. El momento en que se llama sí difiere:
`E2EHTTPClient` invoca `authToken` en cada petición individual (nunca cachea el
resultado), mientras que `E2EMCPClient.connect(...)` lo resuelve una única vez al
conectar y reutiliza ese mismo token para toda la sesión — coherente con que una
conexión MCP es de larga duración, a diferencia de una petición REST suelta.

## `withRunningServer`: probando este kit consigo mismo

Los propios tests de `VaporSkeletonKitE2ESupportTests` en este repo necesitan un
servidor real escuchando para poder ejercitar `E2EHTTPClient`/`E2EMCPClient` de verdad
— no tendría sentido probar un cliente HTTP contra una `Application` en proceso, que es
justo lo que este cliente existe para evitar. `withRunningServer(port:mount:test:)`
arranca una `Application` real, la vincula a un socket TCP real en
`127.0.0.1:port`, y garantiza su desmontaje al terminar — la única pieza de este
artículo que no forma parte de la API pública del kit, porque es un detalle interno de
cómo este mismo repo se testea a sí mismo.



## Tests de Componente / E2E In-Process: `withE2EServer`

Mientras que `withTestApp` prueba la integración en-memoria, y los tests E2E puros atacan componentes de red desplegados mediante `E2EEnvironment`, `VaporSkeletonKitTesting` ofrece un puente ideal: **`withE2EServer`**.

Esta función aprovisiona un entorno idéntico al de `withTestApp` (levantando una instancia de Vapor completa y migrando base de datos de manera aislada) combinándolo con las garantías de la capa de transporte real. Se enciende un NIO Server efímero sobre el "Port 0" provisto por el sistema operativo, permitiendo probar la aplicación usando TCP HTTP puro sin peligro de colisión de puertos:

```swift
// Credenciales con permiso de CREATE/DROP DATABASE — igual que makePostgresConfiguration,
// withE2EServer nunca lee Environment por sí misma; el llamador las resuelve.
let masterConfig = PostgresEnvironmentConfig(
    databaseURL: Environment.get("DATABASE_URL"),
    host: Environment.get("DATABASE_HOST"),
    port: Environment.get("DATABASE_PORT").flatMap(Int.init),
    username: Environment.get("DATABASE_USERNAME"),
    password: Environment.get("DATABASE_PASSWORD"),
    database: Environment.get("DATABASE_NAME"),
    tlsDisabled: Environment.get("DATABASE_TLS") == "disable"
)

try await withE2EServer(
    masterConfig: masterConfig,
    configure: { app, dynamicDB in
        // PostgresEnvironmentConfig es inmutable — reconstruye a partir de masterConfig
        // con `database: dynamicDB` en vez de mutarlo.
        let config = PostgresEnvironmentConfig(
            databaseURL: masterConfig.databaseURL,
            host: masterConfig.host,
            port: masterConfig.port,
            username: masterConfig.username,
            password: masterConfig.password,
            database: dynamicDB,                 // 🚀 Aislamiento absoluto concurrente
            tlsDisabled: masterConfig.tlsDisabled
        )
        app.databases.use(try makePostgresConfiguration(from: config), as: .psql)
        try configureRoutes(app)
    }
) { client in
    let response = try await client.get("/ping")
    #expect(response.status == 200)
}
```

(Versión completa, compilada y ejercitada de verdad en cada `swift test`: `WithE2EServerTests` en este mismo repo.)

Es especialmente útil para habilitar la concurrencia verdadera (como la que exige el framework `Swift Testing`) de tests funcionales E2E sin que estos se pisen las bases de datos ni arrojen errores de `Port 8080 is already in use`. El bloque subyacente interactúa como *Root* frente a Postgres creando una **base de datos temporal aleatoria** (vía UUID, de ahí el parámetro delegado `dynamicDB`) y se ocupa posteriormente de ejecutar `DROP DATABASE` al terminar el hilo, incluso si surge un crash.

## Inyección de Fallos y modo E2E

Para simular fallos 500, timeouts o comportamientos impredecibles durante tests E2E y de Integración, el Kit incluye un middleware `TestFaultInjectionMiddleware` que permite *armar* temporalmente un error en una ruta concreta, junto con el endpoint `POST /e2e/prepare` para preparar/resetear estado de base de datos entre tests (ver ``E2EScenario``/``E2EScenarioFactory``). Ambos se activan a la vez con ``registerE2EMode(_:scenarioFactory:)`` — no hay ninguna variable de entorno que los active por su cuenta.

``registerE2EMode(_:scenarioFactory:)`` **se niega a registrar nada** —lanza
``E2EModeError/refusedInProduction`` en vez de montar ninguna ruta— si
`app.environment == .production`. Es la única barrera real contra una activación
accidental: qué condición decide *cuándo* llamar a esta función (una variable de
entorno propia del proyecto, un flag de build...) sigue siendo responsabilidad del
proyecto consumidor, pero un error en esa condición ya no puede exponer
`/e2e/prepare` (que puede truncar todas las tablas del schema) ni `/_test/fault` en
un despliegue real — el error de configuración se convierte en un fallo de arranque
explícito, capturado por ``runApp(configure:)`` igual que cualquier otro error de
`configure(_:)` (ver <doc:ArranqueDeLaApp>), en lugar de un servidor de producción con
estas rutas abiertas:

```swift
func configure(_ app: Application) async throws {
    // ...
    if Environment.get("E2E_MODE") == "true" {
        try registerE2EMode(app, scenarioFactory: MyScenarioFactory())
    }
}
```

Si `scenarioFactory.make(scenario:)` rechaza el identificador recibido en
`POST /e2e/prepare` (porque no reconoce ese nombre de escenario), la ruta responde
`400 Bad Request` — no el `500` por defecto de Vapor ante un error no reconocido como
`AbortError`. Es un dato de entrada inválido enviado por el propio cliente E2E, no un
fallo interno del servidor.

Cuando está habilitado, los clientes E2E como `E2EHTTPClient` ganan la habilidad de preparar un fallo para que cualquier proceso (como una app iOS en tests de sistema) reciba un error al consumir un endpoint:

```swift
let client = E2EHTTPClient()
// Hacemos que la siguiente llamada nativa a GET /owners sea un 500
try await client.armFault(method: "GET", path: "/owners", status: 500)
```

`/_test/fault` valida lo que recibe: `status` debe estar en `100...599` y
`delayMilliseconds` en `0...30000` (30 segundos) — un valor fuera de rango responde
`400 Bad Request` sin armar nada, en vez de aceptar un status HTTP inválido o dejar que
un test arme un delay desmedido que cuelgue la suite entera.
