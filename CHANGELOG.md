# Changelog

Todos los cambios notables de este paquete se documentan aquí. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), y este proyecto usa
[Versionado Semántico](https://semver.org/lang/es/).

## [Sin publicar]

## [2.0.1] - 2026-09-21

### Añadido

- `POST /_test/fault` (y `E2EHTTPClient.armFault`) aceptan un `body` (y opcionalmente
  `headers`) para sobreescribir la `FaultBody` fija que `TestFaultInjectionMiddleware`
  devolvía siempre al consumir un fallo armado. Permite que un test verifique el
  contrato de error real de su propia app (p. ej. un `AbortError` de Vapor) en vez de
  aceptar la forma fija de `FaultBody`, o de necesitar un fallo genuino (una base de
  datos inalcanzable, Docker...) solo para ver esa forma. `nil` conserva el
  comportamiento previo. `body` está acotado a 64 KiB
  (`TestFaultInjectionMiddleware.maxBodyBytes`), igual que `delayMilliseconds` ya estaba
  acotado a 30 segundos.

## [2.0.0] - 2026-09-21

### Cambiado

- **Incompatible:** `registerE2EMode(_:scenarioFactory:)` solo se activa con
  `app.environment == .testing`; en cualquier otro entorno (incluido `.development`, el
  que usa Vapor si el proceso arranca sin `--env`) lanza
  `E2EModeError.requiresTestingEnvironment(current:)` en vez de registrar `/e2e/prepare`
  y `/_test/fault`. Antes no existía ninguna barrera contra una activación accidental en
  un despliegue real. La instancia E2E debe arrancar con `--env testing` (o
  `VAPOR_ENV=testing`).
- **Incompatible:** `Scenery` se renombra a `Scenario` en toda la API del modo E2E:
  `E2Escenery` → `E2EScenario`, `SceneryFactoryProtocol` → `E2EScenarioFactory`,
  `make(scenery:)` → `make(scenario:)`, `registerE2EMode(_:sceneryFactory:)` →
  `registerE2EMode(_:scenarioFactory:)`. El campo JSON de `POST /e2e/prepare` pasa de
  `"scenery"` a `"scenario"` (`PrepareScenarioRequest`): los clientes E2E que lo envían
  deben actualizarse.
- `post(_:json:as:)`/`get(_:as:)` de `E2EHTTPClient` aceptan cualquier status `2xx`
  (incluido `201 Created`), no solo `200`.
- `mountMCPServer` lanza `MCPServerMountError` si dos herramientas comparten `name` o
  dos recursos comparten `uri`, en vez de dejar inalcanzables los duplicados en
  silencio.
- `POST /e2e/prepare` responde `400` (no `500`) cuando la factory rechaza el escenario
  pedido.
- `POST /_test/fault` responde `400` si `status` no está en `100...599`, si
  `delayMilliseconds` no está en `0...30000`, o si el cuerpo no se puede decodificar
  (antes, esto último cerraba la conexión sin respuesta HTTP).
- La página `/docs` fija `swagger-ui-dist@5.33.0` con hashes SRI, en vez de cargar
  `@5` sin verificación de integridad.
- `withTestApp` restaura las variables de `environment` a su valor previo al terminar.

### Añadido

- `query: [URLQueryItem]` en `E2EHTTPClient.send`/`get`, para query strings reales
  (con `+` escapado como `%2B`).
- Licencia MIT (`LICENSE`).

### Corregido

- `VaporSkeletonKitTesting` no declaraba su dependencia de `VaporSkeletonKit`, que usa
  `withE2EServer` (6 avisos "missing a dependency" en Xcode, y un producto que no
  enlazaba por sí solo).
- `/health` y `get_health` ya no hacen *trap* sin ninguna base de datos configurada:
  responden no sano (`503` en `/health`).
- `runApp` apaga la `Application` también si `execute()` lanza, no solo `configure`.
- `docsTitle` se escapa como HTML antes de interpolarse en la página Swagger UI.
- `E2EHTTPClient` ya no hace *trap* con dos cabeceras de respuesta que solo difieren en
  mayúsculas/minúsculas.
- `E2EEnvironment.baseURL` falla con un mensaje legible si `E2E_BASE_URL` no es una URL
  válida.
- `withE2EServer` apaga sus `Application` auxiliares si `CREATE`/`DROP DATABASE`
  fallan, y elimina la base de datos temporal aunque falle el apagado del servidor.
- Documentación: ejemplos que no compilaban, módulos equivocados, afirmaciones falsas
  sobre CI y `E2E_MODE`, y avisos del catálogo DocC.

## [1.3.5] - 2026-09-20

### Cambiado

- **Incompatible:** `withE2EServer` deja de leer `Environment` por sí misma. Las
  credenciales máster pasan a ser un parámetro obligatorio (`masterConfig:`) en vez de
  construirse internamente con `Environment.get(...) ?? "postgres"` — esos defaults
  ocultaban en silencio un fallo real de configuración en el consumidor.

## [1.3.1] - [1.3.4] - 2026-09-20

### Interno

- Varias reordenaciones y ajustes sucesivos en `withE2EServer`
  (`Sources/VaporSkeletonKitTesting/WithE2EApp.swift`), sin efecto observable sobre la
  API pública.

## [1.3.0] - 2026-09-20

### Añadido

- `withE2EServer(configure:test:)`: arranca un servidor Vapor real en un puerto efímero
  contra una base de datos Postgres creada y destruida por ejecución, para suites E2E
  concurrentes que no se pisan entre sí.

### Corregido

- Dependencia que faltaba en el target `VaporSkeletonKitTesting`.

## [1.2.1] - 2026-09-20

### Interno

- Ajustes internos en `E2EMode.swift`, sin cambio de API pública.

## [1.2.0] - 2026-09-19

### Añadido

- Modo E2E: `registerE2EMode(_:sceneryFactory:)`, inyección de fallos
  (`TestFaultInjectionMiddleware`, `/_test/fault`) y preparación de estado
  (`/e2e/prepare` vía `SceneryFactoryProtocol`/`E2Escenery`).

## [1.1.0] - 2026-09-19

### Cambiado

- MCP se extrae a módulos independientes (`VaporSkeletonKitMCP`,
  `VaporSkeletonKitMCPTesting`, `VaporSkeletonKitMCPE2ESupport`) y se elimina la
  dependencia de `AuthMock`.

## [1.0.0] - 2026-09-19

Extracción inicial desde `BackendSkeleton`:

- Entrypoint de app (`runApp(configure:)`).
- Comprobaciones de salud (`HealthChecking`, `DatabaseHealthChecker`,
  `registerHealthRoute(_:)`, `GetHealthTool`).
- Configuración de Postgres (`PostgresEnvironmentConfig`, `makePostgresConfiguration`).
- Documentación OpenAPI/Swagger UI (`registerOpenAPIDocs`).
- Servidor MCP (`mountMCPServer`, `MCPTool`, `MCPResource`, `MCPToolError`).
- Utilidades de testing e integración (`VaporSkeletonKitTesting`) y soporte E2E
  (`VaporSkeletonKitE2ESupport`).
- Catálogo DocC en español con artículos y tutoriales.

[Sin publicar]: https://github.com/manugs8/VaporSkeletonKit/compare/2.0.1...main
[2.0.1]: https://github.com/manugs8/VaporSkeletonKit/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.3.5...2.0.0
[1.3.5]: https://github.com/manugs8/VaporSkeletonKit/compare/1.3.4...1.3.5
[1.3.1] - [1.3.4]: https://github.com/manugs8/VaporSkeletonKit/compare/1.3.0...1.3.4
[1.3.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.2.1...1.3.0
[1.2.1]: https://github.com/manugs8/VaporSkeletonKit/compare/1.2.0...1.2.1
[1.2.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/manugs8/VaporSkeletonKit/releases/tag/1.0.0
