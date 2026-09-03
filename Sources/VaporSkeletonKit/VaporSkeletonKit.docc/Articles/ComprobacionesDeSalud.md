# Comprobaciones de salud

Cómo ``registerHealthRoute(_:)`` y ``GetHealthTool`` comparten exactamente la misma
comprobación, y por qué `/health` no se genera desde el spec OpenAPI.

## Un protocolo, dos formas de exponerlo

``HealthChecking`` es la abstracción que respalda toda comprobación de salud en este
kit:

```swift
public protocol HealthChecking: Sendable {
    func check(on database: any Database) async -> HealthStatus
}
```

``DatabaseHealthChecker`` es la única implementación real: ejecuta `SELECT 1` contra la
base de datos configurada para confirmar que la conexión está viva, y devuelve un
``HealthStatus`` describiendo el resultado. Ese mismo `HealthStatus` se expone de dos
formas distintas, ambas leyendo `app.healthChecker`:

- `GET /health` (``registerHealthRoute(_:)``), para que Render, `reusable-deploy-smoke.yml`
  y las suites E2E puedan consultarlo por HTTP normal.
- ``GetHealthTool``, la herramienta MCP `get_health`, para que un agente conectado al
  servidor MCP pueda hacer la misma comprobación sin necesitar una segunda ruta.

Ninguna de las dos duplica la lógica de comprobación — ambas llaman a
`app.healthChecker.check(on:)` y formatean el mismo `HealthStatus` a su manera (código
HTTP 200/503 en un caso, `CallTool.Result` con `isError` implícito en el otro).

## Por qué es una propiedad de `Application`, no un parámetro

`healthChecker` vive en `app.storage`, con `DatabaseHealthChecker` como valor por
defecto:

```swift
extension Application {
    public var healthChecker: any HealthChecking {
        get { self.storage[HealthCheckerKey.self] ?? DatabaseHealthChecker() }
        set { self.storage[HealthCheckerKey.self] = newValue }
    }
}
```

Esto hace que la comprobación sea sobreescribible en tests sin tocar la ruta ni la
herramienta MCP: un test puede inyectar un stub que siempre devuelva el mismo resultado,
y tanto `/health` como `get_health` lo usarán automáticamente, sin necesitar ningún
Postgres real de por medio:

```swift
app.healthChecker = StubHealthChecker(result: HealthStatus(isHealthy: false, message: "boom"))
```

`HealthRouteTests` en este mismo repo tiene un test dedicado exactamente a demostrar
esto: que la ruta depende solo del protocolo `HealthChecking`, no de una comprobación de
base de datos concreta.

## Por qué `/health` está escrita a mano

El resto de la superficie de API de un proyecto consumidor normalmente se genera desde
un spec OpenAPI (ver <doc:DocumentacionOpenAPI>). `/health` es la excepción deliberada:
es un endpoint de operaciones — lo consultan Render, `reusable-deploy-smoke.yml` y las
suites E2E que verifican el comportamiento ante una caída de base de datos —, no forma
parte de la API de negocio contra la que integra un cliente externo.

Que todos los consumidores compartan exactamente la misma ruta y la misma forma de
respuesta, en lugar de cada uno generar la suya desde su propio spec, es justo lo que
garantiza que nunca puedan divergir de un proyecto a otro — el mismo motivo por el que
existe este kit. `/health` tampoco aparecerá en el `/docs`/`openapi.yaml` propio de un
proyecto consumidor: si un proyecto quiere que aparezca documentada ahí, se añade como
un addendum fijo al spec, no generada.
