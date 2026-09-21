import Vapor

/// Arranca una `Application` real, la vincula a un puerto TCP efímero asignado por el
/// SO en `127.0.0.1`, ejecuta `test` contra su URL base `http://` real y garantiza
/// después su desmontaje.
///
/// Se usa para ejercitar `E2EHTTPClient`/`E2EMCPClient` contra un servidor real
/// escuchando — todo el sentido de ambos tipos es hablar HTTP real, no el despacho de
/// peticiones en proceso de `VaporTesting`. Un puerto efímero (`port: 0`, igual que
/// `withE2EServer`) en vez de uno fijo por test evita colisiones de bind cuando varios
/// tests de este fichero corren en paralelo — ver "Puertos fijos hardcodeados" en la
/// sección "Calidad de los tests existentes" de `docs/InformeDeAuditoria.md`.
func withRunningServer(
    mount: (Application) throws -> Void,
    test: (URL) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        try mount(app)
        app.http.server.configuration.port = 0
        try await app.asyncBoot()
        try app.server.start()

        guard let port = app.http.server.shared.localAddress?.port else {
            fatalError("No se ha podido obtener el puerto efímero asignado localmente en withRunningServer")
        }

        try await test(URL(string: "http://127.0.0.1:\(port)")!)
        await app.server.shutdown()
    } catch {
        await app.server.shutdown()
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
