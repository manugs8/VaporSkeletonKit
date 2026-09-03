import Vapor

/// Arranca una `Application` real, la vincula a un socket TCP real en
/// `127.0.0.1:port`, ejecuta `test` contra su URL base `http://` real y garantiza
/// después su desmontaje.
///
/// Se usa para ejercitar `E2EHTTPClient`/`E2EMCPClient` contra un servidor real
/// escuchando — todo el sentido de ambos tipos es hablar HTTP real, no el despacho de
/// peticiones en proceso de `VaporTesting`.
func withRunningServer(
    port: Int,
    mount: (Application) throws -> Void,
    test: (URL) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        try mount(app)
        try await app.asyncBoot()
        try await app.server.start(address: .hostname("127.0.0.1", port: port))
        try await test(URL(string: "http://127.0.0.1:\(port)")!)
        await app.server.shutdown()
    } catch {
        await app.server.shutdown()
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
