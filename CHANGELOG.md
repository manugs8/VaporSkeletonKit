# Changelog

Todos los cambios notables de este paquete se documentan aquí. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), y este proyecto usa
[Versionado Semántico](https://semver.org/lang/es/).

## [Sin publicar]

### Cambiado

- **Incompatible:** `registerE2EMode(_:sceneryFactory:)` ahora lanza
  `E2EModeError.refusedInProduction` en vez de registrar `/e2e/prepare` y `/_test/fault`
  cuando `app.environment == .production` — antes no existía ninguna barrera real contra
  una activación accidental en un despliegue real.

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

[Sin publicar]: https://github.com/manugs8/VaporSkeletonKit/compare/1.3.5...main
[1.3.5]: https://github.com/manugs8/VaporSkeletonKit/compare/1.3.4...1.3.5
[1.3.1] - [1.3.4]: https://github.com/manugs8/VaporSkeletonKit/compare/1.3.0...1.3.4
[1.3.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.2.1...1.3.0
[1.2.1]: https://github.com/manugs8/VaporSkeletonKit/compare/1.2.0...1.2.1
[1.2.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/manugs8/VaporSkeletonKit/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/manugs8/VaporSkeletonKit/releases/tag/1.0.0
