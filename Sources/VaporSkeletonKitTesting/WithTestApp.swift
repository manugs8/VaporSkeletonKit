import Fluent
import Vapor

/// Arranca una `Application` de test completamente configurada — incluyendo la
/// ejecución de las migraciones de Fluent —, ejecuta `test` contra ella y garantiza
/// después su desmontaje (revirtiendo migraciones y apagando la app) incluso si `test`
/// lanza un error.
///
/// Este es el nivel "Postgres real, app completa montada en proceso vía `VaporTesting`"
/// de la estrategia de testing en tres niveles que sigue todo proyecto construido a
/// partir de este kit (lógica pura / integración con base de datos real / E2E con HTTP
/// real). Requiere una instancia de Postgres alcanzable — la que sea que `configure`
/// conecte.
///
/// ```swift
/// func withMigratedApp(_ test: (Application) async throws -> Void) async throws {
///     try await withTestApp(environment: ["AUTH_DISABLED": "true"], configure: configure, test: test)
/// }
/// ```
///
/// - Parameters:
///   - environment: Variables de entorno de proceso a establecer (vía `setenv`) antes
///     de que se ejecute `Application.make(.testing)` — p. ej. el flag propio de un
///     paquete de autenticación para "desactivar auth en tests". Vacío por defecto:
///     esta función no asume ningún paquete de autenticación ni nombre de variable en
///     concreto, igual que `makePostgresConfiguration` no lee `Environment` por sí
///     misma.
///   - configure: Configura la `Application` (base de datos, migraciones, rutas, etc.),
///     exactamente igual que el propio `configure(_:)` de un proyecto.
///   - test: El cuerpo del test a ejecutar con la aplicación real y ya migrada.
public func withTestApp(
    environment: [String: String] = [:],
    configure: (Application) async throws -> Void,
    test: (Application) async throws -> Void
) async throws {
    for (key, value) in environment {
        setenv(key, value, 1)
    }

    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        try await app.autoMigrate()
        try await test(app)
        try await app.autoRevert()
    } catch {
        try? await app.autoRevert()
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
