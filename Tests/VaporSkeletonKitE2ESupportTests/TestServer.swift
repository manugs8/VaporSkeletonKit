import Vapor

/// Boots a real `Application`, binds it to an actual TCP socket on `127.0.0.1:port`, runs
/// `test` against its real `http://` base URL, then guarantees teardown.
///
/// Used to exercise `E2EHTTPClient`/`E2EMCPClient` against a genuine listening server —
/// the whole point of both types is talking real HTTP, not `VaporTesting`'s in-process
/// request dispatch.
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
