import Logging
import NIOCore
import NIOPosix
import Vapor

/// Arranca una `Application` de Vapor y la ejecuta hasta su apagado — la detección de
/// entorno, el arranque del logging y el código repetitivo de ciclo de vida que es
/// idéntico en todos los proyectos construidos a partir de este kit, de modo que el
/// `@main` de un proyecto solo tiene que indicar qué hace su propio `configure(_:)`.
///
/// ```swift
/// @main
/// enum Entrypoint {
///     static func main() async throws {
///         try await runApp(configure: configure)
///     }
/// }
/// ```
///
/// Si `configure` lanza un error, este se registra en el log y la `Application` se
/// apaga antes de relanzarlo — el servidor nunca empieza a servir peticiones sobre una
/// app a medio configurar.
///
/// - Parameter configure: Configura la `Application` (base de datos, migraciones,
///   rutas, etc.) antes de que empiece a servir peticiones.
public func runApp(configure: (Application) async throws -> Void) async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)

    let app = try await Application.make(env)
    try await runApp(app, configure: configure)
}

/// El núcleo testeable de ``runApp(configure:)``: ejecuta `configure` sobre una
/// `Application` ya arrancada y luego sirve peticiones hasta el apagado.
///
/// Separado de ``runApp(configure:)`` para poder ejercitarlo en tests directamente
/// contra `Application.make(.testing)`, sin pasar por
/// `Environment.detect()`/`LoggingSystem.bootstrap(from:)` — esto último solo puede
/// ejecutarse una vez por proceso, así que no es algo que una suite de tests pueda
/// invocar más de una vez.
///
/// - Parameters:
///   - app: Una `Application` ya arrancada.
///   - configure: Configura la `Application` antes de que empiece a servir peticiones.
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
