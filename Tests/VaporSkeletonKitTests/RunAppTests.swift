import Testing
import Vapor

@testable import VaporSkeletonKit

/// Ejercita el núcleo interno `runApp(_:configure:)` contra `Application.make(.testing)`
/// en lugar del entrypoint público `runApp(configure:)` — este último llama a
/// `LoggingSystem.bootstrap(from:)`, que solo puede ejecutarse una vez por proceso y
/// por tanto no es algo que una suite de tests pueda invocar repetidamente.
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
