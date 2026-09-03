import Testing
import Vapor

@testable import VaporSkeletonKit

/// Exercises the internal `runApp(_:configure:)` core against `Application.make(.testing)`
/// rather than the public `runApp(configure:)` entrypoint — the latter calls
/// `LoggingSystem.bootstrap(from:)`, which can only run once per process and so can't be
/// invoked repeatedly from a test suite.
@Suite("Run App")
struct RunAppTests {
    @Test("Calls configure with the booted Application before serving")
    func callsConfigureBeforeServing() async throws {
        actor Recorder {
            private(set) var received = false
            func markReceived() { received = true }
        }
        let recorder = Recorder()
        struct StopEarly: Error {}

        let app = try await Application.make(.testing)
        await #expect(throws: StopEarly.self) {
            try await runApp(app) { app in
                await recorder.markReceived()
                _ = app.logger
                throw StopEarly()
            }
        }
        #expect(await recorder.received)
    }

    @Test("Propagates a configure error, shutting the Application down instead of serving")
    func propagatesConfigureErrors() async throws {
        struct BoomError: Error, Equatable {}

        let app = try await Application.make(.testing)
        await #expect(throws: BoomError.self) {
            try await runApp(app) { _ in throw BoomError() }
        }
    }
}
