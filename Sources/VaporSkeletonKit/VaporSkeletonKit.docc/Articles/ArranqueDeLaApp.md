# Arranque de la app

Cómo ``runApp(configure:)`` sustituye el código repetitivo de arranque y apagado que
tendría cada `@main` por separado.

## El problema

Todo `@main` de un backend Vapor necesita, en este orden: detectar el entorno
(`Environment.detect()`), arrancar el sistema de logging a partir de ese entorno,
construir la `Application`, ejecutar el `configure(_:)` propio del proyecto, servir
peticiones hasta recibir la señal de apagado, y desmontar limpiamente la `Application`.
Ese código es idéntico en cualquier backend Vapor que use este kit — la única pieza que
varía de un proyecto a otro es qué hace `configure(_:)`.

## La solución: un entrypoint de una línea

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

`runApp(configure:)` hace exactamente esos pasos por ti. Si `configure` lanza un error
— una variable de entorno obligatoria que falta, una URL de base de datos con un
formato inválido — el error se registra en el log **y la `Application` se apaga antes de
relanzarlo**. El servidor nunca llega a aceptar tráfico sobre una app a medio
configurar; falla rápido y de forma visible en los logs, en lugar de arrancar en un
estado roto.

## Por qué está partida en dos funciones

`runApp(configure:)` es en realidad un envoltorio muy fino sobre una segunda función,
`runApp(_:configure:)`, que no es pública:

```swift
public func runApp(configure: (Application) async throws -> Void) async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)

    let app = try await Application.make(env)
    try await runApp(app, configure: configure)
}

func runApp(_ app: Application, configure: (Application) async throws -> Void) async throws {
    do {
        try await configure(app)
    } catch {
        app.logger.report(error: error)
        try? await app.asyncShutdown()
        throw error
    }

    try await app.execute()
    try await app.asyncShutdown()
}
```

La razón de la separación es puramente de testabilidad: `LoggingSystem.bootstrap(from:)`
solo se puede invocar **una vez por proceso** — es una limitación del propio
`swift-log`, no de este kit. Eso significa que una suite de tests no puede llamar a
`runApp(configure:)` más de una vez (cada test que lo intentara después del primero
crashearía). `RunAppTests` en este mismo repo ejercita en su lugar el núcleo interno
`runApp(_:configure:)` directamente contra `Application.make(.testing)`, sin pasar en
ningún momento por `Environment.detect()`/`LoggingSystem.bootstrap(from:)`:

```swift
let app = try await Application.make(.testing)
await #expect(throws: BoomError.self) {
    try await runApp(app) { _ in throw BoomError() }
}
```

Esto prueba exactamente la lógica que importa (propagar el error de `configure`,
desmontar la app en lugar de dejarla servir) sin depender de un estado global de
proceso que un test no controla.
